# TOOLS.md - Local Notes

Skills define *how* tools work. This file is for *your* specifics — the stuff unique to your setup.

## What Goes Here

Things like:
- Camera names and locations
- SSH hosts and aliases
- Preferred voices for TTS
- Speaker/room names
- Device nicknames
- API quirks you've discovered

## Examples

```markdown
### Cameras
- living-room → Main area, 180° wide angle
- front-door → Entrance, motion-triggered

### SSH
- home-server → 192.168.1.100, user: admin

### TTS
- Preferred voice: "Nova" (warm, slightly British)
```

## Why Separate?

Skills are shared. Your setup is yours. Keeping them apart means you can update skills without losing your notes, and share skills without leaking your infrastructure.

## Exa AI Search

OpenClaw 2026.3.22+ includes Exa AI as a built-in web search provider. Exa provides neural search, keyword search, date filtering, and content extraction.

### Enabling Exa

```bash
# 1. Enable the Exa plugin
openclaw plugins enable exa

# 2. Add your API key to ~/.openclaw/.env
echo "EXA_API_KEY=your-api-key-here" >> ~/.openclaw/.env

# 3. Set Exa as your default search provider in openclaw.json
# Add this to your openclaw.json:
```

```json
{
  "tools": {
    "web": {
      "search": {
        "provider": "exa"
      }
    }
  }
}
```

Once configured, your agent can search the web, fetch page content, and extract highlights — all through Exa's API. Get an API key at [exa.ai](https://exa.ai).

---

Add whatever helps you do your job. This is your cheat sheet.
