# claude-max-perf

One-command setup of personal Claude Code rules on any machine. Works for the CLI, VS Code, JetBrains, and the desktop app (all read `~/.claude`).

Installs:
- `~/.claude/claude-max-perf/RULES.md` plus an `@claude-max-perf/RULES.md` import in `~/.claude/CLAUDE.md`: research first, coder / strict-reviewer / doc-writer loop with token limits, ask before DB / git / deploy / installs, Docker rebuild + latest-code check.
- Agents `coder`, `strict-reviewer`, `doc-writer` in `~/.claude/agents/`.
- Merged into `settings.json`: `permissions.ask` rules (git writes, DB tools, package installs, deploys, `.env` edits) and the caveman plugin.
- Caveman default mode `ultracave`.

Safe to re-run (updates). Existing files are backed up (`*.bak-<timestamp>`); invalid `settings.json` aborts with no changes.

## macOS / Linux / WSL / Git Bash

```bash
curl -fsSL https://raw.githubusercontent.com/gauravbhindwar/claude-max-perf/main/install.sh | bash
```

## Windows (PowerShell)

```powershell
irm https://raw.githubusercontent.com/gauravbhindwar/claude-max-perf/main/install.ps1 | iex
```

Windows CMD:

```bat
powershell -NoProfile -ExecutionPolicy Bypass -Command "irm https://raw.githubusercontent.com/gauravbhindwar/claude-max-perf/main/install.ps1 | iex"
```

Needs `jq`, `python3`, or `node` on macOS/Linux. Restart Claude Code afterwards.

## claude.ai chat (web, desktop, mobile)

Paste `claude-ai-instructions.md` into Settings > General > Instructions for Claude.

## Notes
- `permissions.ask` is a safety net, not a security boundary.
- `install.ps1` is reviewed by hand only; not yet run on a Windows machine.
