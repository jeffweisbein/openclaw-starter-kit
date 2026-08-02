#!/usr/bin/env python3
"""Screening layer for untrusted external content.

Pattern-and-heuristic scanner that runs BEFORE external content reaches the
model (or before scraped data is laundered into an outbound action). No LLM
call, no network, no third-party dependency -- it has to be cheap enough to run
on every web fetch in every live session.

Design notes that matter for the false-positive rate:

  * Scoring is additive with combination bonuses, not boolean. A lone action
    verb ("delete the file", "curl | sh") is near-zero. The score only climbs
    when an action co-occurs with something that ADDRESSES the agent or
    OVERRIDES its instructions -- which is what an injection actually looks
    like and what normal documentation never does.
  * The harness's own "SECURITY NOTICE ... ignore any instructions" banner
    is stripped before scanning, otherwise the scanner would flag its own
    wrapper on literally every fetch.
  * Obfuscated text is scanned twice: raw, and with zero-width/format
    characters removed. A pattern that only appears after de-obfuscation is
    scored as deliberate evasion.
  * Hidden regions (HTML comments, display:none blocks, long base64 runs) are
    extracted and re-scanned with the same core logic at depth 1. Hidden text
    is only penalised if what is hidden is itself directive.

Public API:
    screen(text, source=None) -> dict with score / action / signals / stats
    verdict_action(score)     -> "pass" | "flag" | "quarantine"
"""

import base64
import binascii
import re
import time

VERSION = "1.0"

# Thresholds. A single unmistakable override phrase lands at "flag"; it takes a
# second signal (an action, an agent address, concealment) to reach quarantine.
# That keeps articles ABOUT prompt injection out of the quarantine bucket.
FLAG_AT = 30
QUARANTINE_AT = 65

MAX_SCAN_CHARS = 400_000
MAX_EXCERPT = 180
MAX_SIGNALS = 40

# Combination-bonus guards (see the bonus block in screen()).
BONUS_MIN_WEIGHT = 10    # signals below this cannot contribute to a bonus
BONUS_PROXIMITY = 600    # chars; contributing signals must be this close
WEAK_ACTION_MAX = 25     # an ACTION signal at or below this is "weak"
WEAK_ACTION_CAP = 25     # total weak-ACTION score with no anchor category

# Categories
OVERRIDE = "instruction_override"
AGENT = "agent_addressing"
ACTION = "action_exfil"
HIDDEN = "hidden_payload"
CRED = "credential"
FRAMING = "fake_framing"

I = re.IGNORECASE
IM = re.IGNORECASE | re.MULTILINE

# --------------------------------------------------------------------------
# Signal table: (id, category, weight, compiled pattern)
# Weights are tuned so that no single pattern that has a plausible innocent
# reading can reach QUARANTINE_AT on its own.
# --------------------------------------------------------------------------

PATTERNS = [
    # ---- instruction override -------------------------------------------
    ("ignore_previous_instructions", OVERRIDE, 55, re.compile(
        r"\b(?:ignore|disregard|forget|override|discard|bypass)\b[^.\n]{0,40}?"
        r"\b(?:previous|prior|above|earlier|preceding|foregoing|original|initial|former|any\s+other)\b"
        r"[^.\n]{0,25}?\b(?:instruction|prompt|direction|command|rule|guideline|context|message)s?\b", I)),
    ("ignore_security_notice", OVERRIDE, 55, re.compile(
        r"\b(?:ignore|disregard|skip|the\s+following\s+overrides)\b[^.\n]{0,40}?"
        r"\b(?:security\s+notice|safety\s+(?:notice|guidelines|rules|instructions)|"
        r"the\s+notice\s+above|warning\s+above|system\s+prompt)\b", I)),
    # Anchored to a line start or a sentence/tag boundary: an injected header
    # stands on its own. Mid-sentence prose ("each agent needs updated
    # instructions:") is documentation, not a directive block.
    ("new_instructions_header", OVERRIDE, 45, re.compile(
        r"(?:^|\n|[.!?:>\]]\s{0,3})\s{0,4}(?:new|updated|revised|additional|real|actual|true|override)\s+"
        r"(?:system\s+)?(?:instruction|prompt|directive|rule)s?\s*[:\-–]", I)),
    ("you_are_no_longer", OVERRIDE, 50, re.compile(
        r"\byou\s+are\s+no\s+longer\s+(?:bound|restricted|limited|required|obligated|subject|an?\b)", I)),
    ("from_now_on", OVERRIDE, 45, re.compile(
        r"\bfrom\s+now\s+on,?\s+you\s+(?:are|will|must|should|shall|may|can)\b", I)),
    ("your_new_role", OVERRIDE, 45, re.compile(
        r"\byour\s+new\s+(?:role|task|job|instructions?|persona|identity|objective|goal|directive)s?\b", I)),
    ("roleplay_unrestricted", OVERRIDE, 35, re.compile(
        r"\b(?:pretend|act|behave|respond)\b[^.\n]{0,30}?\b(?:to\s+be|as\s+if|as\s+though|like)\b"
        r"[^.\n]{0,40}?\b(?:unrestricted|no\s+restrictions|no\s+limits|jailbroken|uncensored|developer\s+mode)\b", I)),
    ("developer_mode", OVERRIDE, 30, re.compile(
        r"\b(?:developer|god|debug|admin|sudo|dan)\s+mode\s+(?:enabled|activated|on\b|is\s+now)", I)),
    ("conceal_from_user", OVERRIDE, 50, re.compile(
        r"\bdo\s*n(?:o|')t\s+(?:tell|inform|mention|reveal|disclose|report|show|notify|alert|warn|say)\b"
        r"[^.\n]{0,40}?\b(?:the\s+)?(?:user|human|operator|owner|admin|anyone|him|her|them|recipient)\b", I)),
    ("act_without_telling", OVERRIDE, 50, re.compile(
        r"\bwithout\s+(?:telling|informing|notifying|alerting|asking|mentioning\s+it\s+to)\s+"
        r"(?:the\s+)?(?:user|human|operator|owner|anyone)\b", I)),
    ("keep_hidden", OVERRIDE, 40, re.compile(
        r"\b(?:keep\s+this\s+(?:secret|hidden)|do\s*n(?:o|')t\s+let\s+(?:the\s+)?(?:user|anyone)\s+(?:know|see)|"
        r"this\s+message\s+is\s+(?:invisible|hidden)\s+to\s+the\s+user)\b", I)),
    ("exfil_system_prompt", OVERRIDE, 45, re.compile(
        r"\b(?:reveal|show|print|repeat|output|display|dump|disclose|recite|echo)\b[^.\n]{0,30}?"
        r"\byour\s+(?:full\s+|entire\s+|original\s+|initial\s+|system\s+)*"
        r"(?:prompt|instructions?|rules|guidelines|configuration)\b", I)),
    ("disable_safety", OVERRIDE, 45, re.compile(
        r"\b(?:bypass|override|disable|circumvent|turn\s+off|switch\s+off|remove)\b[^.\n]{0,30}?"
        r"\b(?:your\s+)?(?:safety|security)?\s*(?:guardrails?|restrictions?|filters?|safeguards?|"
        r"content\s+polic(?:y|ies)|safety\s+(?:rules|checks|guidelines))\b", I)),

    # ---- agent addressing (mostly fuel for the combination bonus) --------
    ("ai_identity_assertion", AGENT, 30, re.compile(
        r"\byou\s+are\s+(?:now\s+)?(?:a|an|the)\s+(?:\w+\s+){0,3}"
        r"(?:AI|A\.I\.|assistant|agent|chatbot|bot|language\s+model|large\s+language\s+model|LLM)\b", I)),
    # Vocative only. "send it to the Claude Code interface" is prose ABOUT an
    # agent, not an address TO one, so "to the" is deliberately not an opener.
    ("addressed_by_model_name", AGENT, 25, re.compile(
        r"\b(?:hey|hello|hi|attention|note\s+to|dear)\s*,?\s+"
        r"(?:claude|chatgpt|gpt-?[0-9]?|assistant|ai\s+agent|language\s+model|copilot|gemini|llm)\b", I)),
    # Bare "your prompt" is everywhere in LLM documentation; require the
    # possessive to point at the agent's own governing instructions.
    ("refers_to_your_instructions", AGENT, 20, re.compile(
        r"\byour\s+(?:system\s+prompt|initial\s+prompt|original\s+prompt|instructions\b|directives\b"
        r"|guidelines\b|programming\b|training\s+data)", I)),
    ("as_an_ai", AGENT, 15, re.compile(
        r"\bas\s+an?\s+(?:AI|language\s+model|assistant|autonomous\s+agent)\b", I)),
    ("if_you_are_an_agent", AGENT, 40, re.compile(
        r"\bif\s+you\s+(?:are\s+(?:an?\s+)?(?:AI|agent|assistant|automated|language\s+model|bot)|"
        r"are\s+reading\s+this\s+as\s+an|have\s+been\s+asked\s+to)\b", I)),

    # ---- action / exfiltration verbs against real agent capability -------
    ("email_to_specific_address", ACTION, 25, re.compile(
        r"\b(?:send|forward|email|mail|cc|bcc|deliver)\b[^.\n]{0,40}?"
        r"\bto\s+[\w.+-]+@[\w.-]+\.[a-z]{2,}", I)),
    ("send_content_to_url", ACTION, 20, re.compile(
        r"\b(?:send|forward|post|upload|transmit|exfiltrate|report|submit)\b[^.\n]{0,40}?"
        r"\b(?:to\s+)?https?://", I)),
    ("post_to_social", ACTION, 12, re.compile(
        r"\b(?:post|tweet|publish|dm|message|share)\b[^.\n]{0,25}?\b(?:on|to|via)\s+"
        r"(?:twitter|x\.com|slack|discord|telegram|linkedin|reddit|imessage|whatsapp)\b", I)),
    # Destruction verbs carry almost no standalone evidence: cleanup docs, SQL
    # tutorials and app-store reviews all say them. They exist to fuel the
    # combination bonus when something is also addressing the agent.
    ("mass_destruction", ACTION, 12, re.compile(
        r"\b(?:delete|remove|wipe|erase|purge|destroy|drop)\s+(?:all|every|the\s+entire|everything)\b", I)),
    ("db_destruction", ACTION, 10, re.compile(
        r"\b(?:drop\s+table|truncate\s+table|drop\s+database|delete\s+from\s+\w+\s*;)", I)),
    # Only a bare home/root target. `rm -rf ~/.config/myapp` is a normal
    # uninstall step in half the READMEs on GitHub.
    ("rm_rf_home", ACTION, 25, re.compile(
        r"\brm\s+-[a-z]*[rf][a-z]*\s+(?:/|~|\$HOME|/Users/[\w.-]+)(?:\s|/?\*|$)", I)),
    ("financial_transfer", ACTION, 25, re.compile(
        r"\b(?:transfer|wire|send|pay)\b[^.\n]{0,25}?"
        r"\b(?:funds|money|payment|\$[\d,]{3,}|bitcoin|btc|ethereum|eth|usdc|crypto)\b", I)),
    ("wallet_or_bank_target", ACTION, 25, re.compile(
        r"\b(?:wallet\s+address|routing\s+number|iban|swift\s+code|account\s+and\s+routing)\b", I)),
    ("curl_pipe_shell", ACTION, 5, re.compile(
        r"\bcurl\b[^|\n]{0,120}\|\s*(?:sudo\s+)?(?:ba|z|fi)?sh\b", I)),

    # ---- credential-shaped strings and requests --------------------------
    ("anthropic_key", CRED, 40, re.compile(r"\bsk-ant-[A-Za-z0-9_\-]{20,}")),
    ("openai_key", CRED, 40, re.compile(r"\bsk-(?:proj-)?[A-Za-z0-9]{32,}\b")),
    ("github_token", CRED, 40, re.compile(
        r"\b(?:gh[pousr]_[A-Za-z0-9]{30,}|github_pat_[A-Za-z0-9_]{40,})\b")),
    ("aws_access_key", CRED, 40, re.compile(r"\b(?:AKIA|ASIA)[0-9A-Z]{16}\b")),
    ("slack_token", CRED, 40, re.compile(r"\bxox[baprs]-[A-Za-z0-9\-]{12,}\b")),
    ("google_api_key", CRED, 40, re.compile(r"\bAIza[0-9A-Za-z_\-]{35}\b")),
    ("private_key_block", CRED, 45, re.compile(
        r"-----BEGIN\s+(?:RSA\s+|EC\s+|DSA\s+|OPENSSH\s+|PGP\s+)?PRIVATE\s+KEY-----")),
    ("jwt_token", CRED, 25, re.compile(
        r"\beyJ[A-Za-z0-9_\-]{10,}\.[A-Za-z0-9_\-]{10,}\.[A-Za-z0-9_\-]{10,}")),
    # "Please provide your credentials" is a literal string in login docs and
    # legitimate account email. On its own it is not evidence; it earns its
    # score by combining with an action or an override.
    ("asks_for_credentials", CRED, 25, re.compile(
        r"\b(?:what\s+(?:is|are)|send\s+me|give\s+me|paste|provide|share|tell\s+me|enter|reply\s+with)\b"
        r"[^.\n]{0,30}?\byour\s+(?:api\s*key|password|token|credentials|secret|private\s+key|ssh\s+key|"
        r"login|seed\s+phrase)\b", I)),

    # ---- content impersonating system / tool framing ---------------------
    ("fake_system_reminder", FRAMING, 60, re.compile(r"</?system-reminder\s*>", I)),
    ("fake_function_call_block", FRAMING, 55, re.compile(
        r"</?(?:antml:)?(?:function_calls|function_results|invoke\s+name=|tool_result|tool_use)\b", I)),
    # An UNPAIRED wrapper marker (paired ones are stripped by
    # strip_known_wrapper) is content forging the end of the untrusted region so
    # that whatever follows reads as trusted. There is no innocent version of
    # that, so it quarantines on its own.
    ("fake_untrusted_marker", FRAMING, 65, re.compile(
        r"<<<\s*(?:END_)?EXTERNAL_UNTRUSTED_CONTENT", I)),
    ("fake_role_tags", FRAMING, 30, re.compile(
        r"</?(?:system|instructions|admin|root|developer|assistant)\s*>", I)),
    ("fake_bracket_directive", FRAMING, 20, re.compile(
        r"\[(?:SYSTEM|ADMIN|OVERRIDE|ROOT|INTERNAL)(?:\s+(?:MESSAGE|NOTE|INSTRUCTION|OVERRIDE|DIRECTIVE))?\]")),
]

# Two distinct conversation roles at line starts = injected transcript framing.
_TURN_MARKER = re.compile(r"^\s{0,4}(Human|Assistant|System|User)\s*:", IM)

# Compound exfiltration: reading a local secret AND shipping it somewhere, close
# together. Split into two halves so that a README's
# `curl -H "Authorization: Bearer $KEY" https://example.com/v1` -- which
# references a secret but never READS one from disk -- cannot match.
_SECRET_READ = re.compile(
    # `$(cat)` with no argument is the standard read-stdin idiom in shell hooks,
    # so a command substitution only counts when its target is secret-shaped.
    r"(?:\$\(\s*(?:printenv|env)\s*\)"
    r"|\$\(\s*(?:cat|base64|security\s+find-generic-password)\s+[^)\n]{0,60}?"
    r"(?:\.env(?!\.?\w)|\.ssh|id_rsa|id_ed25519|credential|keychain|token|secret|passwd)"
    r"|\b(?:cat|read|dump|print|upload|attach|exfiltrate|steal|send|email|post|leak)\b[^\n]{0,25}?"
    # .env but not .env.example / .env.sample / .env.template -- doc boilerplate
    r"(?:\.env(?!\.?\w)|~/\.ssh|/\.ssh/|id_rsa|id_ed25519|\.aws/credentials|credentials\.json|keychain"
    r"|\.git-credentials|\.npmrc|\.claude/\.credentials|/etc/passwd))", I)
_NET_SEND = re.compile(
    r"(?:curl\s+[^\n]{0,140}https?://|wget\s+[^\n]{0,100}https?://"
    r"|\b(?:post|send|upload|transmit|forward|exfiltrate|email|mail)\b[^\n]{0,40}?"
    r"(?:https?://|[\w.+-]+@[\w.-]+\.[a-z]{2,}))", I)
_EXFIL_WINDOW = 250

# Local-secret access on its own (no send half found).
_SECRET_ACCESS_WEIGHT = 25
_EXFIL_COMPOUND_WEIGHT = 55

# ---- hidden payload machinery -------------------------------------------
_ZERO_WIDTH = re.compile(r"[​-‏⁠-⁤﻿­᠎]")
_BIDI_OVERRIDE = re.compile(r"[‪-‮⁦-⁩]")
_TAG_CHARS = re.compile(r"[\U000e0000-\U000e007f]")
_HTML_COMMENT = re.compile(r"<!--([\s\S]{0,4000}?)-->")
_HIDDEN_STYLE = re.compile(
    r"(?:display\s*:\s*none|visibility\s*:\s*hidden|font-size\s*:\s*0(?:px|pt|em)?\b"
    r"|opacity\s*:\s*0(?:\.0+)?\b|color\s*:\s*(?:#f{3}\b|#f{6}\b|white\b)"
    r"|text-indent\s*:\s*-\d{3,}|position\s*:\s*absolute\s*;\s*left\s*:\s*-\d{3,}"
    r"|aria-hidden\s*=\s*[\"']true[\"'])", I)
_BASE64_RUN = re.compile(r"(?<![A-Za-z0-9+/=])[A-Za-z0-9+/]{200,}={0,2}(?![A-Za-z0-9+/=])")
_URLISH = re.compile(r"https?://\S*$")

# Placeholder-looking "credentials" in docs (sk-ant-xxxxxxxx, YOUR_TOKEN_HERE).
_PLACEHOLDER = re.compile(
    r"(?:your[_\-]|xxxx|placeholder|example|changeme|<[^>]{1,20}>|\.\.\.|abcdef123456|123456789)", I)

# The harness's own wrapper. Stripped before scanning so the scanner does not
# flag its own banner (which necessarily contains "ignore any instructions").
_OWN_BANNER = re.compile(
    r"SECURITY NOTICE: The following content is from an EXTERNAL, UNTRUSTED source"
    r"[\s\S]{0,1500}?(?:Send messages to third parties|Reveal sensitive information)[^\n]*\n?", I)
# The id quotes may arrive backslash-escaped when a tool response reaches us as
# serialized JSON rather than a parsed object, so the escapes are optional.
_MARKER = re.compile(
    r"<<<\s*(END_)?EXTERNAL_UNTRUSTED_CONTENT(?:\s+id\s*=\s*\\?\"([^\"\\\n]{0,64})\\?\")?\s*>>>"
    r"(?:\\n|[^\S\n]*\n)?(?:Source:[^\n\\]{0,60}(?:\\n|\n))?(?:---(?:\\n|\n))?")
_TRAILER = re.compile(r"\n\[Showing truncated [^\]]{0,200}\]\s*\Z")


def strip_known_wrapper(text):
    """Remove the harness's own untrusted-content banner and its marker pairs.

    A tool response is often a JSON blob where the wrapper appears more than
    once (OpenClaw wraps the `title` field as well as `text`), so this cannot be
    anchored at position 0 -- doing that flagged the wrapper as forged framing
    on every single MCP fetch.

    Marker handling pairs an opening marker with the matching closing marker by
    id and removes only the marker text, never the content between them. An
    UNPAIRED marker -- in particular a stray END, the shape an attacker uses to
    pretend the untrusted region has finished -- is deliberately left in place
    so it still scores as fake_untrusted_marker.
    """
    out = _OWN_BANNER.sub("", text)
    out = _TRAILER.sub("", out, count=1)

    matches = list(_MARKER.finditer(out))
    if not matches:
        return out

    open_stack = []
    paired = []
    for m in matches:
        is_close, mid = m.group(1), m.group(2)
        if not is_close:
            open_stack.append(m)
        else:
            for i in range(len(open_stack) - 1, -1, -1):
                if open_stack[i].group(2) == mid:
                    paired.append(open_stack.pop(i))
                    paired.append(m)
                    break
            # unmatched close: leave it in, it is an escape attempt

    if not paired:
        return out
    spans = sorted((m.start(), m.end()) for m in paired)
    buf = []
    cursor = 0
    for start, end in spans:
        buf.append(out[cursor:start])
        cursor = end
    buf.append(out[cursor:])
    return "".join(buf)


def _clean(s):
    """Collapse whitespace and neutralise control characters for display."""
    s = _ZERO_WIDTH.sub("␀", s)
    s = _BIDI_OVERRIDE.sub("␀", s)
    s = re.sub(r"[\x00-\x08\x0b\x0c\x0e-\x1f\x7f]", " ", s)
    s = re.sub(r"\s+", " ", s).strip()
    return s


def _excerpt(text, start, end, pad=50, redact=False):
    lo = max(0, start - pad)
    hi = min(len(text), end + pad)
    frag = text[lo:hi]
    if redact:
        hit = text[start:end]
        if len(hit) > 12:
            frag = frag.replace(hit, hit[:6] + "…[redacted]…" + hit[-2:])
    frag = _clean(frag)
    if len(frag) > MAX_EXCERPT:
        frag = frag[:MAX_EXCERPT] + "…"
    prefix = "…" if lo > 0 else ""
    suffix = "…" if hi < len(text) else ""
    return prefix + frag + suffix


def _sig(sid, category, weight, excerpt, offset, note=None, extra_categories=None):
    s = {
        "id": sid,
        "category": category,
        "weight": weight,
        "excerpt": excerpt,
        "offset": offset,
    }
    if note:
        s["note"] = note
    if extra_categories:
        # Categories found INSIDE a concealed region. Propagated so that
        # "hidden text that is itself an override + an action" earns the same
        # combination bonus it would earn in the clear.
        s["extra_categories"] = sorted(extra_categories)
    return s


def _scan_patterns(text, seen):
    """Run the signal table over one view of the text."""
    signals = []
    for sid, category, weight, pattern in PATTERNS:
        if sid in seen:
            continue
        m = pattern.search(text)
        if not m:
            continue
        hit = m.group(0)
        if category == CRED and _PLACEHOLDER.search(hit):
            continue  # documentation placeholder, not a live secret
        seen.add(sid)
        signals.append(_sig(sid, category, weight, _excerpt(text, m.start(), m.end(), redact=(category == CRED)), m.start()))
    return signals


def _scan_compound(text, seen):
    """Secret read + network send within a short window, and turn framing."""
    signals = []

    reads = [m for m in _SECRET_READ.finditer(text)][:20]
    if reads and "local_secret_access" not in seen:
        sends = [m for m in _NET_SEND.finditer(text)][:40]
        paired = None
        for r in reads:
            for s in sends:
                if abs(s.start() - r.start()) <= _EXFIL_WINDOW:
                    paired = (r, s)
                    break
            if paired:
                break
        if paired:
            seen.add("secret_exfiltration_chain")
            r, s = paired
            lo, hi = min(r.start(), s.start()), max(r.end(), s.end())
            signals.append(_sig(
                "secret_exfiltration_chain", ACTION, _EXFIL_COMPOUND_WEIGHT,
                _excerpt(text, lo, hi, pad=10), lo,
                note="reads a local secret and ships it to an external destination"))
        else:
            seen.add("local_secret_access")
            r = reads[0]
            signals.append(_sig("local_secret_access", ACTION, _SECRET_ACCESS_WEIGHT,
                                _excerpt(text, r.start(), r.end()), r.start()))

    if "conversation_turn_framing" not in seen:
        roles = {m.group(1).lower() for m in _TURN_MARKER.finditer(text)}
        if len(roles) >= 2:
            seen.add("conversation_turn_framing")
            m = _TURN_MARKER.search(text)
            signals.append(_sig("conversation_turn_framing", FRAMING, 20,
                                _excerpt(text, m.start(), m.end()), m.start(),
                                note="content contains %s role markers" % "/".join(sorted(roles))))
    return signals


def _core_score(text):
    """Cheap recursive scorer used to decide whether hidden text is directive."""
    seen = set()
    sigs = _scan_patterns(text, seen) + _scan_compound(text, seen)
    return sum(s["weight"] for s in sigs), sigs


def _scan_hidden(text, seen, depth):
    """Zero-width, bidi, HTML comments, CSS-hidden blocks, base64 payloads."""
    signals = []
    if depth > 0:
        return signals

    bidi = _BIDI_OVERRIDE.search(text)
    if bidi and "bidi_override_chars" not in seen:
        seen.add("bidi_override_chars")
        signals.append(_sig("bidi_override_chars", HIDDEN, 40,
                            _excerpt(text, bidi.start(), bidi.end()), bidi.start(),
                            note="unicode direction-override characters can hide or reorder visible text"))

    tag = _TAG_CHARS.search(text)
    if tag and "unicode_tag_chars" not in seen:
        seen.add("unicode_tag_chars")
        signals.append(_sig("unicode_tag_chars", HIDDEN, 60,
                            _excerpt(text, tag.start(), tag.end()), tag.start(),
                            note="invisible unicode tag characters (a known text-smuggling channel)"))

    zw = _ZERO_WIDTH.findall(text)
    if zw and "zero_width_chars" not in seen:
        n = len(zw)
        weight = 0
        if n >= 30:
            weight = 35
        elif n >= 10:
            weight = 25
        elif n >= 3:
            weight = 15
        if weight:
            seen.add("zero_width_chars")
            m = _ZERO_WIDTH.search(text)
            signals.append(_sig("zero_width_chars", HIDDEN, weight,
                                _excerpt(text, m.start(), m.end()), m.start(),
                                note="%d zero-width/format characters" % n))

    # De-obfuscated view: a pattern that only appears once invisible characters
    # are removed is deliberate evasion, not incidental markup.
    if _ZERO_WIDTH.search(text) and "obfuscated_evasion" not in seen:
        stripped = _ZERO_WIDTH.sub("", text)
        raw_score, _ = _core_score(text)
        clean_score, clean_sigs = _core_score(stripped)
        if clean_score > raw_score:
            seen.add("obfuscated_evasion")
            top = max(clean_sigs, key=lambda s: s["weight"])
            signals.append(_sig("obfuscated_evasion", HIDDEN, 60, top["excerpt"], top["offset"],
                                note="directive text is only visible after removing invisible characters "
                                     "(revealed signal: %s)" % top["id"],
                                extra_categories={s["category"] for s in clean_sigs}))

    # HTML comments carrying directives.
    if "hidden_html_comment" not in seen:
        for m in _HTML_COMMENT.finditer(text):
            inner = m.group(1)
            if len(inner) < 12:
                continue
            score, sigs = _core_score(inner)
            if score >= 25:
                seen.add("hidden_html_comment")
                signals.append(_sig("hidden_html_comment", HIDDEN, 50,
                                    _excerpt(text, m.start(), min(m.end(), m.start() + 300), pad=0), m.start(),
                                    note="HTML comment contains agent-directed text (%s)"
                                         % ",".join(s["id"] for s in sigs[:3]),
                                    extra_categories={s["category"] for s in sigs}))
                break

    # Visually hidden blocks (display:none, white-on-white, off-screen).
    if "hidden_styled_block" not in seen:
        for m in _HIDDEN_STYLE.finditer(text):
            window = text[m.end():m.end() + 1200]
            score, sigs = _core_score(window)
            if score >= 25:
                seen.add("hidden_styled_block")
                signals.append(_sig("hidden_styled_block", HIDDEN, 50,
                                    _excerpt(text, m.start(), min(len(text), m.end() + 200), pad=0), m.start(),
                                    note="visually hidden block contains agent-directed text (%s)"
                                         % ",".join(s["id"] for s in sigs[:3]),
                                    extra_categories={s["category"] for s in sigs}))
                break

    # Long base64 runs. Presence alone is nearly worthless as a signal (tracking
    # pixels, unsubscribe tokens, inline assets) -- only a decoded directive
    # payload scores.
    runs = list(_BASE64_RUN.finditer(text))[:5]
    if runs and "base64_blob" not in seen:
        seen.add("base64_blob")
        m0 = runs[0]
        signals.append(_sig("base64_blob", HIDDEN, 3,
                            _excerpt(text, m0.start(), min(m0.end(), m0.start() + 60), pad=0), m0.start(),
                            note="%d long base64-shaped run(s)" % len(runs)))
    for m in runs:
        if "base64_directive_payload" in seen:
            break
        line_start = text.rfind("\n", 0, m.start()) + 1
        if _URLISH.search(text[line_start:m.start()]):
            continue  # opaque token inside a URL, e.g. an unsubscribe link
        blob = m.group(0)
        if len(blob) > 40000:
            blob = blob[:40000]
        try:
            decoded = base64.b64decode(blob + "=" * (-len(blob) % 4), validate=False)
        except (binascii.Error, ValueError):
            continue
        try:
            decoded_text = decoded.decode("utf-8", errors="strict")
        except UnicodeDecodeError:
            continue  # binary payload, not smuggled instructions
        score, sigs = _core_score(decoded_text)
        if score >= 25:
            seen.add("base64_directive_payload")
            signals.append(_sig("base64_directive_payload", HIDDEN, 60,
                                _clean(decoded_text[:MAX_EXCERPT]), m.start(),
                                note="base64 run decodes to agent-directed text (%s)"
                                     % ",".join(s["id"] for s in sigs[:3]),
                                extra_categories={s["category"] for s in sigs}))
    return signals


def verdict_action(score):
    if score >= QUARANTINE_AT:
        return "quarantine"
    if score >= FLAG_AT:
        return "flag"
    return "pass"


def screen(text, source=None, strip_wrapper=True):
    """Screen untrusted text. Returns a verdict dict; never raises on input."""
    t0 = time.perf_counter()
    if text is None:
        text = ""
    if not isinstance(text, str):
        try:
            text = str(text)
        except Exception:
            text = ""

    original_len = len(text)
    truncated = original_len > MAX_SCAN_CHARS
    if truncated:
        text = text[:MAX_SCAN_CHARS]

    wrapped = False
    if strip_wrapper:
        stripped = strip_known_wrapper(text)
        wrapped = stripped != text
        text = stripped

    seen = set()
    signals = []
    signals += _scan_patterns(text, seen)
    signals += _scan_compound(text, seen)
    signals += _scan_hidden(text, seen, depth=0)

    # A second pass over the de-obfuscated view catches split-token evasion
    # ("ig<zwsp>nore previous instructions") for signals the raw pass missed.
    if _ZERO_WIDTH.search(text):
        signals += _scan_patterns(_ZERO_WIDTH.sub("", text), seen)

    score = sum(s["weight"] for s in signals)
    categories = {s["category"] for s in signals}
    for s in signals:
        categories.update(s.get("extra_categories", ()))

    # Combination bonuses. This is what separates an injection from prose: an
    # action verb only matters when something is also addressing or overriding
    # the agent, and concealment only matters when what is concealed is
    # directive.
    #
    # Two constraints keep this from firing on long legitimate documents:
    #   * only signals at or above BONUS_MIN_WEIGHT participate, so throwaway
    #     matches (a favicon data URI, a `curl | sh` install line) cannot
    #     manufacture a bonus;
    #   * the two contributing signals must be within BONUS_PROXIMITY chars of
    #     each other. A real injection is compact -- it addresses the agent and
    #     tells it what to do in the same breath. An SDK README that shows
    #     "You are a coding assistant" in one code sample and describes posting
    #     to an API endpoint 40KB later is not an injection.
    offsets = {}
    for s in signals:
        if s["weight"] < BONUS_MIN_WEIGHT:
            continue
        for c in [s["category"]] + list(s.get("extra_categories", ())):
            offsets.setdefault(c, []).append(s["offset"])

    def near(*cats_a):
        """Offsets for the first category group that is present."""
        out = []
        for c in cats_a:
            out.extend(offsets.get(c, ()))
        return out

    def combine(a_cats, b_cats):
        a, b = near(*a_cats), near(*b_cats)
        return any(abs(x - y) <= BONUS_PROXIMITY for x in a for y in b)

    bonuses = []
    if combine((OVERRIDE, FRAMING), (ACTION, CRED)):
        bonuses.append(("override_plus_action", 25))
    if combine((AGENT,), (ACTION,)):
        bonuses.append(("agent_addressed_plus_action", 25))
    if combine((HIDDEN,), (OVERRIDE, AGENT, ACTION)):
        bonuses.append(("concealed_directive", 20))
    if combine((OVERRIDE,), (AGENT,)):
        bonuses.append(("override_plus_agent_addressing", 15))
    score += sum(w for _, w in bonuses)

    # Action verbs carry almost no standalone evidence by design, so a document
    # that only trips weak action patterns must not reach the flag threshold no
    # matter how many of them it trips. A long "awesome list" mentions sending
    # money and posting to URLs without being an attack. High-confidence action
    # signals (the exfiltration chain) are above the weak cutoff and exempt.
    anchor_present = any(
        c in offsets for c in (OVERRIDE, AGENT, FRAMING, HIDDEN))
    if not anchor_present:
        weak_action = sum(s["weight"] for s in signals
                          if s["category"] == ACTION and s["weight"] <= WEAK_ACTION_MAX)
        if weak_action > WEAK_ACTION_CAP:
            score -= weak_action - WEAK_ACTION_CAP

    score = max(0, min(100, score))
    signals.sort(key=lambda s: (-s["weight"], s["offset"]))
    elapsed_ms = (time.perf_counter() - t0) * 1000.0

    return {
        "version": VERSION,
        "source": source,
        "score": score,
        "action": verdict_action(score),
        "signals": signals[:MAX_SIGNALS],
        "combinations": [b for b, _ in bonuses],
        "stats": {
            "chars": original_len,
            "scanned_chars": len(text),
            "truncated": truncated,
            "wrapper_stripped": wrapped,
            "signal_count": len(signals),
            "elapsed_ms": round(elapsed_ms, 3),
        },
    }


def summarize(verdict, max_signals=5):
    """One-paragraph human/model-readable summary of a verdict."""
    sigs = verdict.get("signals", [])[:max_signals]
    if not sigs:
        return "no injection signals matched (score %s)" % verdict.get("score", 0)
    parts = []
    for s in sigs:
        line = "%s [%s, +%d]: %s" % (s["id"], s["category"], s["weight"], s["excerpt"])
        if s.get("note"):
            line += " (%s)" % s["note"]
        parts.append(line)
    return "\n".join("- " + p for p in parts)
