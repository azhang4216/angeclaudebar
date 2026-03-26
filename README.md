# AngeClaudeBar — Context-Aware Status Line for Claude Code

A rich, plan-aware status line for [Claude Code](https://claude.ai/code) with Catppuccin Macchiato colors. Adapts to your terminal width and billing plan — shows visual gauges on wide screens, drops to compact percentages as space shrinks.

![AngeClaudeBar preview](preview.svg)

## Install

**1. Download the script**

> **Note:** If you already have a `~/.claude/statusline.sh`, back it up first — this command will overwrite it.
> ```bash
> cp ~/.claude/statusline.sh ~/.claude/statusline.sh.bak
> ```

```bash
curl -o ~/.claude/statusline.sh \
  https://raw.githubusercontent.com/azhang4216/angeclaudebar/main/statusline.sh
chmod +x ~/.claude/statusline.sh
```

Or clone and symlink:
```bash
git clone https://github.com/azhang4216/angeclaudebar.git ~/repos/claude-statusline
ln -s ~/repos/claude-statusline/statusline.sh ~/.claude/statusline.sh
```

**2. Enable it in Claude Code settings**

Add this to `~/.claude/settings.json`:

```json
{
  "statusLine": {
    "type": "command",
    "command": "bash \"$HOME/.claude/statusline.sh\""
  }
}
```

If you already have a `settings.json`, merge the `statusLine` key into your existing object.

**3. (Optional) Keep it fresh on every session**

Add a `SessionStart` hook to clear the cache so your login info is always up to date:

```json
{
  "hooks": {
    "SessionStart": [
      {
        "hooks": [
          {
            "type": "command",
            "command": "rm -f /tmp/claude/statusline-profile-cache.json /tmp/claude/statusline-usage-cache.json"
          }
        ]
      }
    ]
  }
}
```

**4. Restart Claude Code**

The status line appears at the bottom of each session.

## What it shows

**All plans**
- Full project path and git branch with uncommitted change counts (`2M`, `1A`, `1D`)
- Model name (e.g. `Sonnet-4.6`, `Opus-4.6`)
- Context window usage with a color-coded gauge

**Subscription plans (Pro / Max)**
- 5-hour rolling usage gauge with reset time
- 7-day rolling usage gauge with reset time
- Extra usage budget (if enabled on Max)

**API key plans**
- Session cost in dollars (e.g. `$0.34`) instead of rate-limit windows

**Always**
- Account username and plan label at the far right

The layout adapts to your terminal width — from a full two-line display (with full directory path) down to a compact single line.

## Requirements

- [Claude Code](https://claude.ai/code) with OAuth login (the standard `claude login` flow)
- [`jq`](https://jqlang.github.io/jq/) — JSON processor
- `curl`, `bash` — standard on macOS and Linux
- A terminal with truecolor support for the best experience

Install `jq` on macOS:
```bash
brew install jq
```

On Ubuntu/Debian:
```bash
sudo apt install jq
```

## How it works

On each status line refresh, Claude Code pipes a JSON blob (containing model info, context window state, session cost, etc.) to the script on stdin. The script:

1. Parses the JSON with `jq`
2. Fetches your rate-limit usage from `api.anthropic.com/api/oauth/usage` (cached 5 min)
3. Fetches your account profile from `api.anthropic.com/api/oauth/profile` (cached 30 min)
4. Detects your plan type and renders the appropriate gauges
5. Outputs ANSI-colored text sized to your terminal width

All network calls are cached in `/tmp/claude/` and protected by a lock file, so concurrent Claude Code sessions share a single fetch.

## Colors

Uses the [Catppuccin Macchiato](https://github.com/catppuccin/catppuccin) palette:

| Element | Color |
|---|---|
| Project path | Red `#ed8796` |
| Git branch | Green `#a6da95` |
| Model | Purple `#c6a0f6` |
| Healthy gauge | Teal `#8bd5ca` |
| Warning gauge | Amber `#eed49f` |
| Critical gauge | Red `#ed8796` |
| Labels | Muted `#6e738d` |

## Customization

The script is a single self-contained bash file. Edit `~/.claude/statusline.sh` to:
- Change the color palette (the color variables are at the top)
- Adjust the cache TTL (`CACHE_TTL`, `PROFILE_TTL`)
- Modify tier width thresholds (`avail -ge N`)
- Add or remove fields from any tier

## License

MIT
