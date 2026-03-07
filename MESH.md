# multi-mac openclaw mesh

run multiple openclaw agents across machines that can delegate AI compute to each other.

## architecture

```
┌─────────────────────┐     tailscale      ┌─────────────────────┐
│   mac studio #1     │◄──────────────────►│   mac studio #2     │
│   "primary"         │    100.x.x.x       │   "forge"           │
│                     │                     │                     │
│   • imessage        │   ssh + chat.send   │   • heavy compute   │
│   • main agent      │──────────────────►│   • background jobs  │
│   • your phone DMs  │                     │   • separate credits │
│   • orchestrator    │   read transcripts  │   • own gateway      │
│                     │◄──────────────────│                     │
└─────────────────────┘                     └─────────────────────┘
```

## what works vs what doesn't

| method | delegates compute? | notes |
|--------|-------------------|-------|
| `sessions_spawn` + `gatewayUrl` | ❌ no | runs locally despite accepting |
| `sessions_send` + `gatewayUrl` | ❌ no | same - local execution |
| `ssh + openclaw gateway call chat.send` | ✅ yes | proven working |
| `gateway.remote.url` connection | ✅ connects | but only for probe/status, not session delegation |

**key insight**: `gatewayUrl`/`gatewayToken` params on tools control session *metadata* routing, not where AI compute actually runs. to run AI on another machine, you must trigger a session directly on that machine's gateway.

## setup guide

### prerequisites
- both macs on the same tailscale network
- ssh access between machines (password or key-based)
- openclaw installed and running on both machines

### step 1: tailscale

```bash
# on both machines
tailscale up --hostname=openclaw-primary  # or openclaw-forge
tailscale ip -4  # note the IPs
```

### step 2: install openclaw on machine 2

```bash
npm install -g openclaw@latest
openclaw onboard  # follow the wizard
```

important: do NOT copy machine 1's `~/.openclaw` directory. each machine needs its own device identity. copying creates duplicate device IDs that break pairing.

### step 3: configure gateway on machine 2

edit `~/.openclaw/openclaw.json`:

```json
{
  "gateway": {
    "port": 18789,
    "mode": "local",
    "bind": "lan",
    "auth": {
      "mode": "token",
      "token": "your-secure-token-here"
    },
    "trustedProxies": ["127.0.0.1", "::1"]
  }
}
```

the `trustedProxies` is critical if using tailscale. without it, proxied connections get rejected.

### step 4: configure remote on machine 1

add to machine 1's `~/.openclaw/openclaw.json`:

```json
{
  "gateway": {
    "remote": {
      "url": "wss://openclaw-forge.your-tailnet.ts.net",
      "token": "machine-2-gateway-token"
    }
  }
}
```

### step 5: approve device pairing

this is the step most people miss. after configuring the remote URL, machine 1 will try to connect to machine 2's gateway. machine 2 must approve this:

```bash
# on machine 2
openclaw devices list
# you'll see machine 1 in "Pending"

openclaw devices approve <request-id>
```

### step 6: verify connection

```bash
# on machine 1
openclaw gateway probe
# should show: Remote wss://... -> Connect: ok (xxxms) · RPC: ok
```

### step 7: delegate work

```bash
# from machine 1, send a task to machine 2's agent
ssh forge@100.x.x.x "openclaw gateway call chat.send \
  --token 'machine-2-token' \
  --timeout 120000 \
  --params '{
    \"sessionKey\": \"agent:main:main\",
    \"message\": \"your task here\",
    \"idempotencyKey\": \"job-$(date +%s)\"
  }'"
```

machine 2's gateway will:
1. receive the message via its own gateway RPC
2. run the AI session using its own auth/credits
3. execute any tools (exec, file read/write) on machine 2's filesystem
4. store results in machine 2's session transcript

### step 8: read results

```bash
# read machine 2's session transcript
ssh forge@100.x.x.x "python3 -c \"
with open('/Users/forge/.openclaw/agents/main/sessions/<session-id>.jsonl') as f:
    for line in f.readlines()[-5:]:
        print(line[:200])
\""
```

## accounts and identity

| thing | same or separate? | why |
|-------|-------------------|-----|
| macos user account | **separate** | clean isolation, own keychain |
| openclaw install | **separate** | each gateway needs own device identity |
| device identity | **separate** (auto-generated) | never copy ~/.openclaw/identity between machines |
| gateway token | **separate** | each gateway has its own auth token |
| anthropic/ai auth | **can be same or separate** | separate = separate credit pools |
| tailscale | **same network** | they need to see each other |
| ssh keys | **set up between machines** | for delegation commands |

## auth options for machine 2

machine 2 needs its own way to call AI APIs:

1. **copilot-proxy plugin** (uses github copilot credits)
   ```json
   "plugins": { "entries": { "copilot-proxy": { "enabled": true } } }
   ```

2. **anthropic API key** (direct billing)
   ```json
   "auth": { "profiles": { "anthropic:default": { "provider": "anthropic", "apiKey": "sk-ant-..." } } }
   ```

3. **openai-codex oauth** (uses claude.ai pro subscription)
   ```json
   "auth": { "profiles": { "openai-codex:default": { "provider": "openai-codex", "mode": "oauth" } } }
   ```

## troubleshooting

### "pairing required" error
machine 2 hasn't approved machine 1's device. run `openclaw devices list` on machine 2 and approve the pending request.

### "proxy headers detected from untrusted address"
add `"trustedProxies": ["127.0.0.1", "::1"]` to machine 2's gateway config. tailscale terminates TLS at localhost.

### "gateway token mismatch"
the token in machine 1's `gateway.remote.token` must match machine 2's `gateway.auth.token`.

### sessions_spawn seems to work but runs locally
this is expected. `sessions_spawn` with `gatewayUrl` creates session metadata on the remote gateway but executes AI locally. use the `ssh + chat.send` method instead.

### version mismatch
keep both machines on the same openclaw version:
```bash
ssh forge@100.x.x.x "npm install -g openclaw@latest && openclaw gateway restart"
```

## security notes

- gateway tokens are per-machine (never share between gateways)
- tailscale handles encryption between machines
- ssh adds another auth layer for delegation commands
- each agent has its own memory store
- session transcripts stay on the machine that ran them
