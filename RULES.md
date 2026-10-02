# Global rules (every repo, every session)

Read before any answer or change. Repo instruction files override these rules only for repo conventions (style, commands, framework rules). These rules win on safety and workflow. Real conflict: ask user.

## 0. Session start
1. Caveman: context must show `CAVEMAN MODE ACTIVE — level: ultra`. Missing or other level: run Skill `caveman:caveman` with args `ultra` before first reply.
2. Repo instruction files: read every one not already in context. Nested file applies when working in its directory.
   ```bash
   find . \( -name node_modules -o -name .git -o -name .next -o -name dist -o -name build -o -name .venv \) -prune -o -type f \( -iname agents.md -o -iname claude.md -o -iname claude.local.md -o -iname gemini.md -o -name .cursorrules -o -name .windsurfrules -o -name copilot-instructions.md -o -path '*/.cursor/rules/*' -o -path '*/.claude/rules/*' \) -print
   ```

## 1. Research before answer or change
Do all three, cheapest first. Skip step 3 only for pure repo-content questions ("where is X defined").
1. Repo docs: README*, docs/, CONTRIBUTING*, ADRs, CHANGELOG, comments near code.
2. Installed package docs and types for the lockfile version (e.g. `node_modules/<pkg>/docs`, `node_modules/next/dist/docs/`).
3. Online, credible sources only: official docs, release notes, specs/RFCs, MDN, maintainer GitHub repos/issues. No SEO blogs, content farms, unverified posts. Match installed version.
Main session: end reply to user with `Sources:` links. Subagents: no `Sources:` line; follow own output schema. Pass findings (URL + fact) into subagent briefs so subagents do not repeat research.

## 2. Sensitive actions: ask first
Ask in chat, wait for explicit yes, every time. One approval never covers a later action. State exact command and target.
- Any DB read or write: SQL/ORM CLIs, migrations, seeds, studio tools, DB MCP tools (`execute_sql`, `apply_migration`, ...), scripts that hit a DB.
- git commit, push, merge, rebase, reset, revert, tag, branch delete, stash drop, any `--force`; `gh pr create/merge`.
- Deploy, publish, release; edits to `.env*` or secrets; add/remove dependencies; delete files this task did not create; messages to external services.
Subagents never run these. Subagent stops and reports; main session asks user.
`permissions.ask` in `~/.claude/settings.json` prompts on common Bash and PowerShell forms of these commands, `Edit(.env*)`, and DB MCP tools. Safety net, not a security boundary: other forms (e.g. `git -c ... push`, wrappers, custom scripts) slip past. Still ask.

## 3. Code changes: coder / reviewer / doc loop
Main session only. Subagent reading this file: skip section 3, never spawn agents, follow brief.
Every code change uses subagents `coder`, `strict-reviewer`, `doc-writer` (`~/.claude/agents/`).
1. Main: research (section 1), scope task. Big task (more than 5 files or more than 1 feature): split into slices. One slice per user prompt. Ask before next slice.
2. Spawn `coder` with brief.
3. Spawn `strict-reviewer` with changed paths.
4. Reviewer `FAIL`: relay findings verbatim to coder with SendMessage (resume, never respawn). Coder fixes. SendMessage reviewer `re-review` + changed paths. Repeat until `PASS`. Max 2 rounds (see Cost guard); then stop and show open findings to user.
5. After `PASS`: spawn `doc-writer`.
6. Final reply to user: what changed, Mermaid workflow diagram, verification (commands + results), files as links, Sources.
Questions without code change: answer directly, no agents.

### Cost guard (hard limits)
- Before spawning any agent: tell user scope in one line (files, rounds, model) and ask yes. Skip only for a 1-2 file fix.
- Do only what the user asked. No unrequested extras: CI workflows, mutation tests, large test suites, extra platforms, hardening beyond the request. Offer them as a follow-up instead.
- Max 2 review rounds. Round 2 fixes BLOCK/MAJOR only. Reviewer never reports NITs; main session never forwards them. Still failing after round 2: stop and ask user.
- Subagent models: coder and reviewer `sonnet`, doc-writer `haiku`. `opus` only if user asks.
- One agent at a time. Never start a review while the coder still runs.
- Brief caps scope: max 3 files per agent call, no spec over 120 words. Bigger work: slice, one slice per prompt.
- After PASS: stop. No extra polish rounds.

## 4. Token budget
- Agent-to-agent messages: terse English (caveman ultra style) in each agent's fixed output schema. Code, paths, line numbers, identifiers, commands, error strings stay verbatim.
- Pass references, not content: file paths, line ranges, diff commands, URLs. Agents with write tools: output longer than the report cap goes to a scratchpad file; return its path.
- Brief max 120 words: objective, output format, paths, tools/sources to use, boundaries, research facts, applicable repo rules. No pasted file content.
- Subagent report max 15 lines. Exceptions: `doc-writer` max 20 lines including its Mermaid diagram; `strict-reviewer` has no line cap and lists every finding, one line each. No file dumps, praise, or recap.
- Resume with SendMessage; send deltas only.
- Read needed line ranges only. Never re-read a file already in context.
- Reviewer reads diff plus direct callers and callees of changed symbols only.
- Never spend whole budget in one prompt: slice big work (section 3.1).
