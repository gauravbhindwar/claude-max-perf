# Global rules (every repo, every session)

Read before any answer or change. Repo instruction files override these rules only for repo conventions (style, commands, framework rules). These rules win on safety, workflow, and verification. Real conflict: ask user.

## 0. Session start
1. Caveman: context must show `CAVEMAN MODE ACTIVE` with mode `ultracave` (alias `ultra`). Missing or other mode: run Skill `caveman:ultracave` before first reply.
2. Repo instruction files: read every one not already in context. Nested file applies when working in its directory.
   ```bash
   find . \( -name node_modules -o -name .git -o -name .next -o -name dist -o -name build -o -name .venv \) -prune -o -type f \( -iname agents.md -o -iname claude.md -o -iname claude.local.md -o -iname gemini.md -o -name .cursorrules -o -name .windsurfrules -o -name copilot-instructions.md -o -path '*/.cursor/rules/*' -o -path '*/.claude/rules/*' \) -print
   ```
3. Docker: check if this repo runs in Docker (section 5). Remember the result for the task.

## 1. Research before answer or change
Do all three, cheapest first. Skip step 3 only for pure repo-content questions ("where is X defined").
1. Repo docs: README*, docs/, CONTRIBUTING*, ADRs, CHANGELOG, comments near code.
2. Installed package docs and types for the lockfile version (e.g. `node_modules/<pkg>/docs`, `node_modules/next/dist/docs/`).
3. Online, credible sources only: official docs, release notes, specs/RFCs, MDN, maintainer GitHub repos/issues. No SEO blogs, content farms, unverified posts. Match installed version.
Never guess an API, flag, or config key: verify it. Find root cause before fixing; state evidence.
Main session: end reply with `Sources:` links. Subagents: no `Sources:` line. Pass findings (URL + fact) into subagent briefs so subagents do not repeat research.

## 2. Sensitive actions: ask first
Ask in chat, wait for explicit yes, every time. One approval never covers a later action. State exact command and target.
- Any DB read or write: SQL/ORM CLIs, migrations, seeds, studio tools, DB MCP tools (`execute_sql`, `apply_migration`, ...), scripts that hit a DB.
- git commit, push, merge, rebase, reset, revert, tag, branch delete, stash drop, any `--force`; `gh pr create/merge`.
- Deploy, publish, release; edits to `.env*` or secrets; add/remove dependencies; delete files this task did not create; messages to external services.
- Docker: `down -v`, volume/image/system prune or rm, any remote Docker context, any container or context named `prod`/`production`.
Subagents never run these. Subagent stops and reports; main session asks user.
`permissions.ask` in `~/.claude/settings.json` is a safety net, not a security boundary. Still ask.

## 3. Code changes: coder / strict-reviewer / doc-writer loop
Main session only. Subagent reading this file: skip sections 3 and 5, never spawn agents, follow brief.
Every code change runs this loop (agents in `~/.claude/agents/`):
1. Main: research (section 1), scope task. Big task (more than 3 files or more than 1 feature): split into slices, one slice per prompt, ask before next slice.
2. Spawn `coder` with brief.
3. Spawn `strict-reviewer` with changed paths. Its job: hunt every error in the change, line by line, with proof.
4. Reviewer `FAIL`: relay findings verbatim to coder with SendMessage (resume, never respawn). Coder fixes. SendMessage reviewer `re-review` + changed paths. Repeat until `PASS`, max 3 rounds; then stop and show open findings to user.
5. After `PASS`: Docker sync and verify (section 5), if Docker runs.
6. Spawn `doc-writer`: updates affected docs, returns Mermaid workflow diagram.
7. Final reply: what changed, Mermaid diagram, verification (commands + results, Docker proof), files as links, Sources.
Exception: change of 5 lines or fewer in 1 file with no logic (typo, copy, constant): main edits, `strict-reviewer` checks, no `coder`, no `doc-writer`.
Questions without code change: answer directly, no agents.

## 4. Token budget (hard limits)
- Models: `coder` and `strict-reviewer` `sonnet`, `doc-writer` `haiku`. `opus` only if user asks.
- One agent running at a time. Never parallel agents. Never review while coder runs.
- Brief max 120 words: objective, output format, paths, tools/sources, boundaries, research facts, repo rules. Max 3 files per agent call. No pasted file content.
- Agent-to-agent messages: terse English (caveman ultracave style) in each agent's fixed schema. Code, paths, line numbers, identifiers, commands, errors verbatim. Pass references (paths, line ranges, diff commands, URLs), not content.
- Reports: `coder` max 15 lines, `doc-writer` max 20 lines with diagram, `strict-reviewer` lists every BLOCK/MAJOR/MINOR finding, one line each, no NITs.
- Re-review round: prior findings plus new BLOCK/MAJOR only. Main never forwards NITs.
- Do only what the user asked. No unrequested extras (CI, mutation tests, big test suites, extra platforms). Offer them instead.
- Resume with SendMessage, deltas only. Read needed line ranges only. Never re-read a file already in context.
- After `PASS`: stop. No polish rounds.

## 5. Docker: always run latest code
Main session only. Applies when Docker runs containers for this repo.
1. Detect (start of every task):
   ```bash
   docker context show
   docker compose ps --status running
   ```
   Also `docker ps --filter "label=com.docker.compose.project.working_dir=$PWD"`. Context not local (`default`, `desktop-linux`, `colima`, `orbstack`, `rootless`) or name has `prod`: stop, ask user.
2. Restart at task start and after every code change, before testing: rebuild and recreate services that run repo code (have `build:` or a bind mount of the repo). Leave image-only services (postgres, redis) running.
   ```bash
   docker compose up -d --build --force-recreate --wait <app-services>
   ```
3. Verify latest code, with proof in final reply:
   - `docker compose ps`: service `running`/`healthy`.
   - `docker compose logs --tail=50 <service>`: no startup errors.
   - For 1-2 changed files: `sha256sum` local equals `docker compose exec <service> sha256sum <container-path>` (path from bind mount via `docker inspect` or Dockerfile `WORKDIR`/`COPY`).
   - Mismatch: rebuild with `--no-cache`, check again. Still mismatch: stop, report.
4. Never `down -v`, prune, or remove volumes/images without asking (section 2).
