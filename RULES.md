# Global rules (every repo, every session)

Read before any answer or change. Repo instruction files may add repo-specific conventions. These rules win on safety, model governance, workflow, and verification. Real conflict: ask user.

## 0. Session start
1. Caveman: context must show `CAVEMAN MODE ACTIVE` with mode `ultracave` (alias `ultra`). Missing or other mode: run Skill `caveman:ultracave` before first reply.
2. Repo instruction files: read every applicable instruction file not already in context. Nested file applies when working in its directory.
   ```bash
   find . \( -name node_modules -o -name .git -o -name .next -o -name dist -o -name build -o -name .venv \) -prune -o -type f \( -iname agents.md -o -iname claude.md -o -iname claude.local.md -o -iname gemini.md -o -iname agent.md -o -iname agent.local.md -o -name .cursorrules -o -name .windsurfrules -o -name copilot-instructions.md -o -path '*/.cursor/rules/*' -o -path '*/.claude/rules/*' \) -print
   ```
3. Docker: check if this repo runs in Docker (section 5). Remember result for task.

## 1. Research before answer or change
Do only relevant research, cheapest first:
1. Repo docs: README*, docs/, CONTRIBUTING*, ADRs, CHANGELOG, comments near code.
2. Installed package docs/types for lockfile versions.
3. Online credible sources when external/current verification is needed: official docs, release notes, specs/RFCs, MDN, maintainer GitHub repos/issues. No SEO blogs or unverified content.
Never guess an API, flag, config key, or version-specific behavior. Find root cause before fixing.
Pass research findings (URL + fact) into subagents so they do not repeat research.
Questions without code change: answer directly; no agents. Pure repo-content questions may skip online research.

## 2. Sensitive actions: ask first
Ask in chat and wait for explicit yes every time. State exact action and target. One approval never covers a later action.
- Any DB read/write, migration, seed, studio, or DB MCP tool.
- git commit, push, merge, rebase, reset, revert, tag, branch delete, stash drop/clear, force operations, PR create/merge.
- Deploy, publish, release; edit .env*/secrets; add/remove/update dependencies; delete files not created in current task; external messages.
- Docker destructive operations or any remote/prod context.
Subagents never run sensitive actions. Main session asks user.
permissions.ask is a safety net, not a security boundary.

## 3. Code-change workflow: adaptive agents
Main session orchestrates. Subagents never spawn agents.
1. Classify task size.
   - Tiny: one file, <=5 logic-free lines -> main edits, reviewer only.
   - Small: <=3 files, one focused change -> coder + reviewer.
   - Medium/large: researcher only when needed, then coder + reviewer.
2. Spawn only the minimum agents that add value. Never parallel agents.
3. Coder receives a brief with objective, relevant paths, research facts, constraints, and required checks. Max 3 files per call; no pasted file content.
4. Strict-reviewer reviews the diff plus direct callers/callees. It must hunt defects line by line and prove findings.
5. On FAIL, resume coder with only actionable findings. Then resume reviewer with only the delta. Default max 2 fix/review cycles; a 3rd cycle only when a genuine BLOCK/MAJOR issue remains.
6. After PASS, run the requested/cheapest relevant verification. No automatic polish round.
7. Run doc-writer only when behavior/API/config/setup documentation actually changed or the user asks for documentation. Otherwise skip it.
8. Final response: concise change summary, verification, workflow diagram only when useful, and sources when research was used.

## 4. Model governance + token economy
Goal: maximum quality with minimum model cost, context, agents, and turns.

### Allowed automatically
- Haiku: discovery, simple repo reading, docs lookup, summaries, straightforward documentation.
- Sonnet LOW: simple coding, small fixes, routine refactors.
- Sonnet MEDIUM: default for normal coding, debugging, review, architecture, and security-sensitive reasoning.

### Permission-gated
- Sonnet HIGH / MAX / extra-high: NEVER enable automatically. Ask user first.
- Opus: NEVER use automatically under any circumstance. Ask user first.

Permission prompt must state:
MODEL:
REASON:
EXPECTED BENEFIT:
Wait for explicit confirmation. No confirmation = stay on current allowed model.

Escalation path:
Haiku -> Sonnet LOW -> Sonnet MEDIUM -> (ask) Sonnet HIGH -> (ask) Opus

A failed task, complex task, reviewer disagreement, or timeout does not authorize escalation.

### Hard token controls
- One agent at a time. Never parallel agents.
- Prefer one capable agent over redundant agents.
- Max 120-word agent brief. No pasted file content; use paths, line ranges, diff commands, and research references.
- Agent reports: coder <=15 lines; reviewer one line per actionable finding + final PASS/FAIL; doc-writer <=20 lines only when invoked.
- Agent messages: terse, delta-only. Never repeat full context or prior findings.
- Re-review only changed delta plus prior actionable findings.
- Do not re-research a fact already established for the task.
- Do not read files already in context unless needed lines changed.
- Use deterministic tools for simple work instead of agents.
- Do not spawn an agent for trivial file inspection or a simple command.
- Stop immediately when acceptance criteria are met and checks pass.

## 5. Docker: verify latest code
Main session only. Applies when Docker runs containers for this repo.
1. Detect:
   ```bash
   docker context show
   docker compose ps --status running
   ```
   Remote/non-local context or prod/production target: stop and ask user.
2. After code changes, rebuild/recreate repo-code services before testing:
   ```bash
   docker compose up -d --build --force-recreate --wait <app-services>
   ```
3. Verify services running/healthy and logs have no startup errors. For changed files, compare local/container hashes when practical.
4. Never destructive-prune/remove volumes/images without permission.
