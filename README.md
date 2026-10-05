# claude-max-perf

One-command global Claude Code optimization focused on **quality first, token/cost efficiency second, and safe escalation**.

Installs:
- `~/.claude/claude-max-perf/RULES.md` and imports it from `~/.claude/CLAUDE.md`.
- Agents `researcher`, `coder`, `strict-reviewer`, and `doc-writer`.
- Merged `settings.json` safety permissions and the caveman plugin settings.
- Adaptive research + model/effort routing.

## Core strategy

```
Research only when useful
        |
        v
Haiku (LOW) — research/discovery
   | sufficient
   v
Sonnet (LOW -> MEDIUM -> HIGH)
   | genuinely insufficient
   v
Opus (permission only)
```

**Token-saving rules**
- Use deterministic tools for simple discovery.
- Research once and pass findings forward.
- Use the minimum sufficient model, effort, context, agents, and turns.
- Increase effort before changing models when the model already has the needed knowledge.
- Never silently escalate to Opus.
- Review only changed deltas after fixes.
- Stop as soon as acceptance criteria and relevant checks pass.

## Research policy

Use online research when it can materially improve correctness, especially for current or version-specific Claude Code behavior. Prefer official Anthropic/Claude Code docs, release notes, standards/specs, and maintainer repositories. Do not repeat the same research across agents.

## Install

### macOS / Linux / WSL / Git Bash
```bash
curl -fsSL https://raw.githubusercontent.com/gauravbhindwar/claude-max-perf/main/install.sh | bash
```

### Windows (PowerShell)
```powershell
irm https://raw.githubusercontent.com/gauravbhindwar/claude-max-perf/main/install.ps1 | iex
```

Windows CMD:
```bat
powershell -NoProfile -ExecutionPolicy Bypass -Command "irm https://raw.githubusercontent.com/gauravbhindwar/claude-max-perf/main/install.ps1 | iex"
```

Safe to re-run. Existing managed files are backed up when replaced.

## Chat instructions

Paste `claude-ai-instructions.md` into Claude.ai Settings > General > Instructions.

## Notes
- `permissions.ask` is a safety net, not a security boundary.
- `install.ps1` remains hand-reviewed in this repository; it is not claimed as Windows-tested here.
