# Multiply Client Onboarding — Remote Access Checklist

This is the only pre-install work we need from you before we set up your agent machine.

Goal: get the Mac online, privately reachable through Tailscale, and ready for a scheduled remote setup session. Once we can connect, we can handle OpenClaw, agents, model login, repo access, updates, and the rest.

---

## Quick Version

Before install day, please complete these steps:

1. Set up the Mac and connect it to power + internet
2. Install Tailscale
3. Join the HypeLab/Multiply Tailscale network using the invite link we send separately
4. Enable **Screen Sharing**
5. Enable **Remote Login**
6. Send us the Mac's Tailscale IP and confirm the admin username we should use

That's enough for us to take it from there during the setup session.

---

## 1. Prepare the Mac

We recommend a dedicated Mac mini as the always-on agent machine.

| Component | Recommended | Why |
|---|---|---|
| Chip | Apple M4 base | Plenty for agent workloads unless you plan to run local models |
| RAM | 24GB minimum | Agents + gateway + background processes need headroom |
| Storage | 256GB minimum | Enough for agent work; use 512GB+ if it will also be a dev machine |
| macOS | Latest stable macOS | macOS 14+ minimum; newer is better |

**Physical setup:**
- Plug in power
- Use ethernet if available; WiFi is okay if stable
- Keep the Mac somewhere cool with airflow
- Complete the first-run macOS setup so you can reach the desktop

---

## 2. Confirm Admin Access

We need an administrator account on the Mac during setup.

You can either:

- use an existing admin account, or
- create a temporary admin account for setup, such as `multiply` or `hypelab`

To create one:

1. Open **System Settings → Users & Groups**
2. Click **Add User**
3. Set type to **Administrator**
4. Save the username and password for the setup session

**Do not put passwords in GitHub, docs, Slack channels, or email threads.** Share credentials only through the secure channel or live setup call we agree on.

---

## 3. Install Tailscale and Join Our Network

Tailscale gives us private, secure access to the Mac without exposing it to the public internet.

1. Go to [tailscale.com/download](https://tailscale.com/download)
2. Download and install Tailscale for Mac
3. Open Tailscale
4. Sign in with Google, Microsoft, GitHub, or email
5. Open the invite link we send separately: `[TAILSCALE_INVITE_LINK — sent separately]`
6. Accept the invite and join the network
7. Click the Tailscale menu bar icon and confirm it says **Connected**
8. Copy the Tailscale IP address. It usually starts with `100.`

Send us:

- the Tailscale IP, e.g. `100.x.y.z`
- the Mac's device name, if shown
- confirmation that Tailscale says **Connected**

---

## 4. Enable Screen Sharing

Screen Sharing lets us help with setup visually when needed.

1. Open **System Settings → General → Sharing**
2. Turn on **Screen Sharing**
3. Click the info button next to Screen Sharing
4. Allow access for the admin account we will use

If macOS shows a connection address like `vnc://...`, you can send it, but the Tailscale IP is the most important part.

---

## 5. Enable Remote Login

Remote Login lets us use SSH over Tailscale for the actual installation work.

1. Open **System Settings → General → Sharing**
2. Turn on **Remote Login**
3. Click the info button next to Remote Login
4. Allow access for the admin account we will use

You do **not** need to paste an SSH key manually before the setup session. If we need key-based access, we will install the correct public key after we are connected.

---

## 6. Send Us This Setup Info

Please send:

- Tailscale IP: `100.x.y.z`
- Mac admin username
- Whether Screen Sharing is enabled
- Whether Remote Login is enabled
- Your timezone
- Any preferred setup window

Share the admin password only through the secure channel or live setup call we agree on.

---

## Optional: AI Subscription Before Install Day

Your agents run on a frontier model — Claude or GPT. We usually use OAuth subscriptions so cost is a flat monthly fee instead of per-token API billing.

You can set this up before install day, or we can do it together during setup.

### Option A: Claude Max

1. Go to [claude.ai](https://claude.ai)
2. Sign up or log in
3. Subscribe to Claude Max:
   - **$100/mo** — good for most single-machine setups
   - **$200/mo** — heavier workloads, multiple agents, or more headroom
4. We will handle the OAuth login on the Mac during setup

### Option B: ChatGPT / Codex OAuth

1. Go to [chatgpt.com](https://chatgpt.com) or [openai.com/codex](https://openai.com/codex)
2. Sign up or log in
3. Subscribe to one of the higher-usage ChatGPT/Codex plans:
   - **$100/mo** — good for most single-machine setups
   - **$200/mo** — heavier workloads, multiple agents, or more headroom
4. We will handle the OAuth login on the Mac during setup using the Codex CLI

With OAuth, you do **not** need to create an OpenAI or Anthropic API key unless we specifically decide API billing is better for your workload.

---

## Optional: Code Repository Access

If agents will work on code, we can set up GitHub access during install day.

Beforehand, just send the GitHub repo URLs you want the agents to work on.

Please do **not** put GitHub personal access tokens in this document, GitHub issues, Slack channels, or email threads. If a token is needed, we will generate or collect it through a secure setup flow.

---

## What Not To Send In Advance

Please do not send these in regular docs or public channels:

- SSH private keys
- GitHub personal access tokens
- OpenAI/Anthropic API keys
- permanent admin passwords
- production secrets

The public starter kit should contain instructions, not live credentials or customer-specific secrets.

---

## After We Connect

Once Tailscale, Screen Sharing, and Remote Login are working, we will handle:

- OpenClaw installation
- agent workspace setup
- OAuth login for Claude or ChatGPT/Codex
- SSH key installation if needed
- GitHub/repo setup if needed
- health checks and auto-update configuration
- first agent tasks and ongoing monitoring

Questions? Reply to your HypeLab/Multiply contact and we’ll walk you through it.
