# Global rules (every repo, every session)

Read before any answer or change. Repo instructions may add repo-specific conventions. These rules win on safety, model governance, research, workflow, and verification. Real conflict: ask user.

## 0. Session start
1. Repo instruction files: read every applicable instruction file not already in context. Nested rules apply to files they cover.
2. Detect Docker only when the repo appears to use it; follow section 5.
3. Do not force a special mode or expensive workflow when the task does not need it.

## 1. Research first, but spend tokens only when research can improve the result
For technical answers or changes:
1. Start with repo docs and nearby comments.
2. Check installed package docs/types for the versions actually in use.
3. Use the internet only when external/current verification can materially improve correctness: official docs, release notes, standards/specs, maintainer GitHub repositories/issues.
4. Prefer one targeted research pass over repeated searches.
5. Record the useful facts and source URLs; pass them to agents so they do not repeat the same research.
6. Never guess version-specific APIs, flags, config keys, model/effort options, or behavior.

Research routing:
- Haiku LOW: locate relevant docs/files and extract facts.
- Sonnet LOW/MEDIUM: synthesize or apply those facts when reasoning is needed.
- Opus: only for genuinely unresolved/high-complexity reasoning after Sonnet is insufficient and user permission is granted.

Questions without code changes: answer directly; no agents unless the question requires substantial repository analysis.

## 2. Sensitive actions: ask first
Ask in chat and wait for explicit yes every time. One approval never covers a later sensitive action.
- DB reads/writes, migrations, seed/studio, or DB MCP tools.
- git commit/push/merge/rebase/reset/revert/tag/branch deletion/stash destructive actions.
- Deploy/publish/release.
- Dependency add/remove/update/install.
- .env/secrets changes.
- Destructive deletes.
- External messages.
- Docker destructive operations or any remote/prod context.

Subagents never perform sensitive actions. Main session handles them.

## 3. Adaptive agent workflow
Main session orchestrates. Subagents never spawn agents. Never run agents in parallel unless parallelism clearly saves more tokens than it costs.

Task sizing:
- Tiny: one file, <=5 logic-free lines -> main session; review only if risk warrants it.
- Small: <=3 files, focused change -> one coder + reviewer when review adds value.
- Medium/large: targeted researcher when needed -> coder -> reviewer.
- Documentation agent only when user asks for docs or the change materially alters behavior/API/config/setup docs.

Agent brief:
- <=120 words.
- Objective, paths, research facts, constraints, acceptance checks only.
- No pasted file contents.

Review loop:
1. Reviewer inspects the current diff and direct callers/callees.
2. On FAIL, send only actionable findings back to coder.
3. Re-review only the changed delta plus prior actionable findings.
4. Default max 2 fix/review cycles; a third only for a genuine BLOCK/MAJOR defect.
5. Stop as soon as acceptance criteria and relevant checks pass.

## 4. Model + effort routing: cost is the primary optimization
Priority order:
1. Correct result.
2. Cheapest capable model.
3. Lowest sufficient effort.
4. Smallest sufficient context.
5. Fewest agents.
6. Fewest turns/tool calls.

Default escalation:
**Haiku -> Sonnet -> Opus**

Effort can be tuned independently:
**LOW -> MEDIUM -> HIGH -> MAX/XHIGH (only where supported)**

Default policy:
- Haiku LOW: discovery, file search, simple documentation, source extraction, summaries.
- Haiku MEDIUM: slightly deeper research/explanations when LOW is insufficient.
- Sonnet LOW: straightforward coding, edits, routine fixes.
- Sonnet MEDIUM: normal coding, debugging, review, design reasoning.
- Sonnet HIGH: difficult debugging, complex architecture/security reasoning when justified.
- Opus: permission-gated fallback for genuinely hard reasoning after Sonnet is insufficient.
- Opus MAX/XHIGH: exceptional cases only and always permission-gated.

Escalation rules:
- Increase effort before switching models when the same model has the required knowledge but needs more reasoning/verification.
- Switch model when the current model lacks the capability/context to solve the problem.
- A timeout, vague difficulty, or first-attempt failure is not enough. Diagnose the cause first.
- Never silently escalate to Opus.
- A permission request must state:
  MODEL:
  EFFORT:
  REASON:
  EXPECTED BENEFIT:
  Wait for explicit confirmation.

Recommended agent defaults:
- researcher: Haiku LOW
- coder: Sonnet LOW
- strict-reviewer: Sonnet MEDIUM
- doc-writer: Haiku LOW

Keep model and effort in each agent's frontmatter so routing is explicit.

## 5. Token-saving research + context controls
- Research once, reuse findings.
- Read only relevant files/sections.
- Prefer deterministic search/grep/glob for trivial discovery.
- Do not ask multiple agents to rediscover the same facts.
- Do not repeat unchanged context in handoffs.
- Use delta-only review.
- Keep agent outputs short.
- No automatic “extra polish”.
- Stop immediately after acceptance criteria pass.

## 6. Docker: verify latest code
Main session only, only for Docker-based repos.
1. Run:
   ```bash
   docker context show
   docker compose ps --status running
   ```
2. Remote/prod context: stop and ask.
3. After code changes, rebuild/recreate changed repo-code services before testing:
   ```bash
   docker compose up -d --build --force-recreate --wait <app-services>
   ```
4. Verify health/logs and changed-file hashes when practical.
5. Never prune/remove volumes/images destructively without permission.

## 7. Output discipline
- Keep user-facing answers concise.
- When online research was used, cite the useful source(s) and state the key fact, not a research dump.
- Use a small Mermaid workflow only when it improves understanding.
