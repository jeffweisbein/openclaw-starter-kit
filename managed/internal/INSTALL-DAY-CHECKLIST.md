# Multiply Install Day Checklist — Internal

Use this when the client has completed the public pre-install checklist and we are ready to take over.

## 0. Before the Call

- Confirm client sent:
  - Tailscale IP (`100.x.y.z`)
  - admin username
  - timezone
  - setup window
  - Screen Sharing enabled
  - Remote Login enabled
- Pull private snippets from Fubz local doc if needed:
  - `/Users/fubz/clawd/private/multiply-client-access-snippets.md`
- Confirm the client has the right AI subscription ready:
  - Claude Max `$100/$200`, or
  - ChatGPT/Codex OAuth `$100/$200`
- Confirm repo URLs and GitHub org/user access requirements if code agents are part of the setup.

## 1. Connect

- Verify Tailscale device is online.
- SSH over Tailscale:

```bash
ssh <admin-user>@<tailscale-ip>
```

- If needed, connect via Screen Sharing using the Tailscale IP.
- Confirm macOS version, architecture, disk space, and hostname.

```bash
sw_vers
uname -m
df -h /
scutil --get ComputerName
```

## 2. Secure Access

- Install the management SSH public key only if we intentionally need persistent key-based access.
- Confirm `~/.ssh` permissions.
- Do not store client passwords, API keys, or private keys in repo files.
- If a temporary admin password was shared live, ask the client to rotate/remove it after setup.

## 3. Install Base Tooling

- Install/update Xcode Command Line Tools if missing.
- Install Homebrew if missing.
- Install required packages:

```bash
brew install git node pnpm ripgrep jq tmux
```

- Confirm Node/npm/pnpm versions.

## 4. Install OpenClaw

- Install OpenClaw using the current approved install path.
- Create the workspace directory.
- Initialize core config.
- Start/check gateway.

```bash
openclaw status
openclaw gateway status
```

## 5. Model Login

- Complete OAuth login for the selected provider:
  - Claude, or
  - ChatGPT/Codex
- Run a small model smoke test.
- Avoid API keys unless the client explicitly chose API billing.

## 6. Agent Setup

- Copy/apply the managed starter-kit files.
- Configure:
  - main assistant
  - dev/ops agent
  - content agent if included
  - research/growth agent if included
- Start heartbeats/cron jobs only after the baseline smoke test passes.

## 7. Repo Setup, If Applicable

- Clone approved repos.
- Confirm GitHub authentication.
- Confirm git author identity.
- Run a read-only smoke check before allowing write/deploy workflows.

## 8. Health Checks

Run and save outputs for:

- `openclaw status`
- gateway status
- model smoke test
- SSH reconnect test
- Tailscale reconnect/online check
- repo/build smoke if applicable

## 9. Handoff

Send client a short handoff note with:

- what was installed
- how to reach the assistant
- what agents are active
- what recurring jobs are active
- what we still need from them, if anything

## 10. Cleanup

- Remove temporary files.
- Remove or rotate temporary credentials.
- Record internal notes in the client’s private ops file, not the public starter kit.
