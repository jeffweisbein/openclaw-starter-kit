# Multi-Mac OpenClaw Mesh

Run multiple OpenClaw agents across machines that can talk to each other.

## Architecture

```
┌─────────────────────┐     tailscale      ┌─────────────────────┐
│   Mac Studio #1     │◄──────────────────►│   Mac Studio #2     │
│   "clawd"           │    100.x.x.x       │   "nova" (or w/e)   │
│                     │                     │                     │
│   • imessage        │                     │   • research tasks  │
│   • cackles plugin  │   sessions_send()   │   • build server    │
│   • main agent      │◄──────────────────►│   • heavy compute   │
│   • your phone DMs  │   webhook hooks     │   • background jobs │
└─────────────────────┘                     └─────────────────────┘
```

## Setup

### Prerequisites
- Both Macs on the same Tailscale network
- Generate a pre-auth key at https://login.tailscale.com/admin/settings/keys

### Mac 1 (already running)
1. Make sure tailscale is connected:
   ```bash
   tailscale up --hostname=openclaw-clawd
   tailscale ip -4  # note this IP
   ```

2. Enable tailscale mode in openclaw config:
   ```json
   "gateway": {
     "tailscale": { "mode": "on" }
   }
   ```

### Mac 2 (new)
```bash
# One-liner bootstrap:
./bootstrap-mac.sh \
  --identity nova \
  --tailscale-key tskey-auth-xxxxx \
  --peer http://100.x.x.x:18789 \
  --alert +15166334684
```

### Accounts & Identity

| Thing | Same or Separate? | Why |
|-------|-------------------|-----|
| macOS user account | **separate** | clean isolation, own keychain |
| Apple ID | **separate** | own iCloud, own iMessage number |
| iMessage | **separate** | each agent gets its own number/identity |
| GitHub | **same** (deploy key per repo) | access same repos, separate SSH keys |
| Anthropic API | **same account** | one bill, separate API keys |
| Tailscale | **same network** | they need to see each other |
| OpenClaw license | **separate install** | each gateway is independent |

**Recommended**: create a new Apple ID (e.g. nova-agent@icloud.com) so Mac 2 has its own iMessage identity. This way both agents can DM you independently.

### Cross-Gateway Communication

Once both are on tailscale, they can talk to each other. But there's a critical distinction:

#### True Compute Delegation (recommended)

Use `chat.send` via SSH to run AI compute on the remote machine:

```bash
ssh nova@100.x.x.x "openclaw gateway call chat.send \
  --token '<nova-gateway-token>' \
  --params '{
    \"sessionKey\": \"agent:main:main\",
    \"message\": \"run the test suite on cackles repo\",
    \"idempotencyKey\": \"task-$(date +%s)\"
  }'"
```

This runs the AI inference on nova's hardware using nova's auth. The compute is truly delegated.

#### What does NOT delegate compute

`sessions_spawn` with `gatewayUrl` does NOT run compute remotely. It still runs locally. Don't use it for delegation.

#### Other communication methods

1. **Webhook hooks**: configure hooks to POST to peer gateway on events
2. **Shared workspace via git**: both agents push/pull from same repos

### Setup Gotchas

1. **Device pairing**: the remote machine must approve the calling machine's device pairing first
2. **Trusted proxies**: add the calling machine to `trustedProxies` in the remote machine's config
3. **Auth profiles**: remote machine's `auth-profiles.json` needs both access AND refresh token fields for auto-refresh to work

### Security
- Gateway tokens are per-machine (never shared)
- Tailscale handles encryption + auth between machines
- Each agent has its own memory store (no cross-contamination)
- Peer communication goes through authenticated gateway endpoints
