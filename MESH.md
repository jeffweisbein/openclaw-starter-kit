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

Once both are on tailscale, they can:

1. **Send messages between sessions**:
   ```
   # From Mac 1, talk to Mac 2's agent:
   sessions_send to nova: "hey, can you run the test suite on the cackles repo?"
   ```

2. **Webhook hooks**: configure hooks to POST to peer gateway on events

3. **Shared workspace via git**: both agents push/pull from same repos

### Security
- Gateway tokens are per-machine (never shared)
- Tailscale handles encryption + auth between machines
- Each agent has its own memory store (no cross-contamination)
- Peer communication goes through authenticated gateway endpoints
