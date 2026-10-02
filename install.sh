#!/usr/bin/env bash
# claude-max-perf installer for macOS, Linux and WSL (Git Bash/MSYS/Cygwin delegate to install.ps1).
#   curl -fsSL https://raw.githubusercontent.com/gauravbhindwar/claude-max-perf/main/install.sh | bash
# Idempotent: re-run to update. Env overrides:
#   CMP_BASE        raw base URL to download from
#   CMP_SRC         local checkout to copy from instead of downloading
#   CMP_JSON_TOOL   force JSON backend: jq | python3 | node
#   CLAUDE_CONFIG_DIR, XDG_CONFIG_HOME   honoured as Claude Code and caveman do
# Nothing runs until `main` on the last line, so a partial download does nothing.
set -euo pipefail

CMP_IMPORT_LINE='@claude-max-perf/RULES.md'
CMP_AGENTS='coder strict-reviewer doc-writer'
CMP_TMP=''
CMP_TS=''
CMP_JSON=''
CMP_OS=''

say() { printf '%s\n' "$*"; }
# show PATH: print PATH with $HOME shortened to ~.
show() {
  case "$1" in
    "$HOME"/*) printf '~%s' "${1#"$HOME"}" ;;
    *) printf '%s' "$1" ;;
  esac
}
warn() { printf 'claude-max-perf: warning: %s\n' "$*" >&2; }
die() {
  printf 'claude-max-perf: error: %s\n' "$*" >&2
  exit 1
}

cleanup() {
  if [ -n "${CMP_TMP:-}" ]; then rm -rf "$CMP_TMP"; fi
}

# Git Bash / MSYS / Cygwin: hand off to the PowerShell installer.
delegate_windows() {
  local base="$1" rc=0
  command -v powershell.exe >/dev/null 2>&1 || die "powershell.exe not found; run install.ps1 from PowerShell"
  if command -v cygpath >/dev/null 2>&1; then
    if [ -n "${CLAUDE_CONFIG_DIR:-}" ]; then CLAUDE_CONFIG_DIR="$(cygpath -w "$CLAUDE_CONFIG_DIR")" && export CLAUDE_CONFIG_DIR; fi
    if [ -n "${XDG_CONFIG_HOME:-}" ]; then XDG_CONFIG_HOME="$(cygpath -w "$XDG_CONFIG_HOME")" && export XDG_CONFIG_HOME; fi
  fi
  if [ -n "${CMP_SRC:-}" ]; then
    local ps1="$CMP_SRC/install.ps1"
    [ -f "$ps1" ] || die "CMP_SRC set but $ps1 not found"
    if command -v cygpath >/dev/null 2>&1; then
      ps1="$(cygpath -w "$ps1")"
      CMP_SRC="$(cygpath -w "$CMP_SRC")" && export CMP_SRC
    fi
    MSYS2_ARG_CONV_EXCL='*' powershell.exe -NoProfile -ExecutionPolicy Bypass -File "$ps1" </dev/null || rc=$?
  else
    MSYS2_ARG_CONV_EXCL='*' powershell.exe -NoProfile -ExecutionPolicy Bypass -Command \
      "[Net.ServicePointManager]::SecurityProtocol = [Net.ServicePointManager]::SecurityProtocol -bor 3072; irm $base/install.ps1 | iex" </dev/null || rc=$?
  fi
  exit "$rc"
}

# Pick JSON backend: jq, else python3 (json importable), else node.
pick_json_tool() {
  local forced="${CMP_JSON_TOOL:-}"
  if [ -n "$forced" ]; then
    case "$forced" in
      jq | python3 | node) ;;
      *) die "CMP_JSON_TOOL must be jq, python3 or node (got: $forced)" ;;
    esac
    json_tool_ok "$forced" || die "CMP_JSON_TOOL=$forced but it is not usable"
    CMP_JSON="$forced"
    return
  fi
  local t
  for t in jq python3 node; do
    if json_tool_ok "$t"; then
      CMP_JSON="$t"
      return
    fi
  done
  die "need one of jq, python3 or node to merge settings.json; install one (e.g. jq) and re-run"
}

json_tool_ok() {
  case "$1" in
    jq) command -v jq >/dev/null 2>&1 && jq -n --slurpfile a /dev/null '{}|keys_unsorted' >/dev/null 2>&1 ;;
    python3)
      command -v python3 >/dev/null 2>&1 || return 1
      # macOS: /usr/bin/python3 without Command Line Tools is a stub that opens an install dialog.
      if [ "$CMP_OS" = Darwin ] && [ "$(command -v python3)" = /usr/bin/python3 ] &&
        ! xcode-select -p >/dev/null 2>&1; then
        return 1
      fi
      python3 -c 'import json' >/dev/null 2>&1
      ;;
    node) command -v node >/dev/null 2>&1 && node -e '' >/dev/null 2>&1 ;;
    *) return 1 ;;
  esac
}

# jq: missing/blank file slurps to [] and is treated as {}.
CMP_JQ_DEFS='
def doc: if length == 0 then {} else .[0] end;
def umerge($x; $y):
  if ($x | type) == "object" and ($y | type) == "object" then
    reduce ($y | keys_unsorted[]) as $k ($x;
      .[$k] = (if has($k) then umerge(.[$k]; $y[$k]) else $y[$k] end))
  elif ($x | type) == "array" and ($y | type) == "array" then
    reduce $y[] as $e ($x; if any(.[]; . == $e) then . else . + [$e] end)
  else $y end;
'

write_helpers() {
  cat >"$CMP_TMP/cmp_json.py" <<'PY'
import json, sys

def load(p):
    try:
        with open(p, encoding="utf-8-sig") as f:
            s = f.read()
    except FileNotFoundError:
        return {}
    if not s.strip():
        return {}
    v = json.loads(s)
    if not isinstance(v, dict):
        raise ValueError("root is not a JSON object")
    return v

def canon(v):
    return json.dumps(v, sort_keys=True, separators=(",", ":"))

def merge(a, b):
    if isinstance(a, dict) and isinstance(b, dict):
        out = dict(a)
        for k, v in b.items():
            out[k] = merge(a[k], v) if k in a else v
        return out
    if isinstance(a, list) and isinstance(b, list):
        out, seen = list(a), {canon(x) for x in a}
        for x in b:
            c = canon(x)
            if c not in seen:
                seen.add(c)
                out.append(x)
        return out
    return b

mode = sys.argv[1]
try:
    if mode == "valid":
        load(sys.argv[2])
    elif mode == "same":
        sys.exit(0 if canon(load(sys.argv[2])) == canon(load(sys.argv[3])) else 1)
    elif mode == "merge":
        m = merge(load(sys.argv[2]), load(sys.argv[3]))
        with open(sys.argv[4], "w", encoding="utf-8", newline="\n") as f:
            f.write(json.dumps(m, indent=2, ensure_ascii=False) + "\n")
except ValueError as e:
    print(e, file=sys.stderr)
    sys.exit(1)
PY
  cat >"$CMP_TMP/cmp_json.js" <<'JS'
const fs = require('fs');
function load(p) {
  let s;
  try { s = fs.readFileSync(p, 'utf8'); } catch (e) { if (e.code === 'ENOENT') return {}; throw e; }
  if (s.charCodeAt(0) === 0xfeff) s = s.slice(1);
  if (!s.trim()) return {};
  const v = JSON.parse(s);
  if (!isObj(v)) throw new Error('root is not a JSON object');
  return v;
}
function isObj(v) { return v !== null && typeof v === 'object' && !Array.isArray(v); }
function canon(v) {
  if (Array.isArray(v)) return '[' + v.map(canon).join(',') + ']';
  if (isObj(v)) return '{' + Object.keys(v).sort().map((k) => JSON.stringify(k) + ':' + canon(v[k])).join(',') + '}';
  return JSON.stringify(v);
}
function merge(a, b) {
  if (isObj(a) && isObj(b)) {
    const out = Object.assign({}, a);
    for (const k of Object.keys(b)) out[k] = Object.prototype.hasOwnProperty.call(a, k) ? merge(a[k], b[k]) : b[k];
    return out;
  }
  if (Array.isArray(a) && Array.isArray(b)) {
    const out = a.slice(), seen = new Set(a.map(canon));
    for (const x of b) { const c = canon(x); if (!seen.has(c)) { seen.add(c); out.push(x); } }
    return out;
  }
  return b;
}
const [mode, p1, p2, p3] = process.argv.slice(2);
try {
  if (mode === 'valid') load(p1);
  else if (mode === 'same') process.exit(canon(load(p1)) === canon(load(p2)) ? 0 : 1);
  else if (mode === 'merge') fs.writeFileSync(p3, JSON.stringify(merge(load(p1), load(p2)), null, 2) + '\n', 'utf8');
} catch (e) { console.error(e.message); process.exit(1); }
JS
}

# json_valid FILE: 0 if missing, blank, or a single JSON object.
json_valid() {
  local f="$1"
  [ -f "$f" ] || return 0
  case "$CMP_JSON" in
    jq) jq -e -n --slurpfile a "$f" '$a | length == 0 or (length == 1 and (.[0] | type) == "object")' >/dev/null 2>&1 ;;
    python3) python3 "$CMP_TMP/cmp_json.py" valid "$f" 2>/dev/null ;;
    node) node "$CMP_TMP/cmp_json.js" valid "$f" 2>/dev/null ;;
  esac
}

# json_merge TARGET FRAGMENT OUT: deep-merge FRAGMENT onto TARGET (may be missing) into OUT.
json_merge() {
  local tgt="$1" frag="$2" out="$3"
  if [ ! -f "$tgt" ]; then
    tgt="$CMP_TMP/empty.json"
    : >"$tgt"
  fi
  case "$CMP_JSON" in
    jq) jq -n --slurpfile a "$tgt" --slurpfile b "$frag" "$CMP_JQ_DEFS"'umerge($a | doc; $b | doc)' >"$out" ;;
    python3) python3 "$CMP_TMP/cmp_json.py" merge "$tgt" "$frag" "$out" ;;
    node) node "$CMP_TMP/cmp_json.js" merge "$tgt" "$frag" "$out" ;;
  esac
}

# json_same A B: 0 if A (may be missing) and B hold equal JSON values.
json_same() {
  local a="$1" b="$2"
  [ -f "$a" ] || return 1
  case "$CMP_JSON" in
    jq) jq -e -n --slurpfile a "$a" --slurpfile b "$b" "$CMP_JQ_DEFS"'($a | doc) == ($b | doc)' >/dev/null 2>&1 ;;
    python3) python3 "$CMP_TMP/cmp_json.py" same "$a" "$b" 2>/dev/null ;;
    node) node "$CMP_TMP/cmp_json.js" same "$a" "$b" 2>/dev/null ;;
  esac
}

fetch() {
  local rel="$1" dst="$2" base="$3"
  mkdir -p "$(dirname "$dst")"
  if [ -n "${CMP_SRC:-}" ]; then
    [ -f "$CMP_SRC/$rel" ] || die "missing $CMP_SRC/$rel"
    cp "$CMP_SRC/$rel" "$dst"
  elif command -v curl >/dev/null 2>&1; then
    curl -fsSL "$base/$rel" -o "$dst" || die "download failed: $base/$rel"
  elif command -v wget >/dev/null 2>&1; then
    wget -qO "$dst" "$base/$rel" || die "download failed: $base/$rel"
  else
    die "need curl or wget to download $base/$rel"
  fi
}

# install_file SRC DST BACKUP(yes|no)
install_file() {
  local src="$1" dst="$2" backup="$3"
  if [ -f "$dst" ] && cmp -s "$src" "$dst"; then
    say "  unchanged  $(show "$dst")"
    return
  fi
  mkdir -p "$(dirname "$dst")"
  if [ -f "$dst" ]; then
    if [ "$backup" = yes ]; then
      cp -p "$dst" "$dst.bak-$CMP_TS"
      say "  backup     $(show "$dst.bak-$CMP_TS")"
    fi
    cat "$src" >"$dst"
    say "  updated    $(show "$dst")"
  else
    cat "$src" >"$dst"
    say "  created    $(show "$dst")"
  fi
}

# has_import FILE: 0 if the import line is present outside fenced code blocks
# (Claude Code ignores imports inside code blocks); 2 if absent and FILE ends
# inside an unclosed fence (an appended line would land in the code block).
# CommonMark fences: <=3 spaces, run of >=3 ` or ~ (no ` in a backtick info string);
# closed only by the same char, run >= opening length, nothing but blanks after.
has_import() {
  [ -f "$1" ] || return 1
  awk '
    { sub(/\r$/, ""); line = $0; i = 0 }
    { while (i < 3 && substr(line, 1, 1) == " ") { line = substr(line, 2); i++ } }
    {
      c = substr(line, 1, 1); n = 0
      if (c == "`" || c == "~") { while (substr(line, n + 1, 1) == c) n++ }
      if (n >= 3) {
        rest = substr(line, n + 1)
        if (fc == "" && (c == "~" || index(rest, "`") == 0)) { fc = c; fn = n; next }
        if (fc != "" && c == fc && n >= fn && rest ~ /^[ \t]*$/) { fc = ""; next }
      }
    }
    fc == "" && /^ ? ? ?@claude-max-perf\/RULES\.md[ \t]*$/ { found = 1; exit }
    END { if (found) exit 0; if (fc != "") exit 2; exit 1 }
  ' "$1"
}

ensure_import() {
  local f="$1" nl=$'\n' rc=0
  has_import "$f" || rc=$?
  if [ "$rc" = 0 ]; then
    say "  unchanged  $(show "$f") (import present)"
    return
  fi
  if [ "$rc" = 2 ]; then
    warn "$f ends inside an unclosed code fence; add the line $CMP_IMPORT_LINE outside it by hand."
    say "  skipped    $(show "$f")"
    return
  fi
  if [ ! -s "$f" ]; then
    printf '%s\n' "$CMP_IMPORT_LINE" >>"$f"
    say "  created    $(show "$f") (import added)"
    return
  fi
  if grep -q $'\r' "$f"; then nl=$'\r\n'; fi
  if [ -n "$(tail -c 1 "$f")" ]; then printf '%s' "$nl" >>"$f"; fi
  printf '%s%s%s' "$nl" "$CMP_IMPORT_LINE" "$nl" >>"$f"
  say "  appended   $(show "$f") (import added)"
}

# has_bom FILE: 0 if FILE starts with a UTF-8 BOM (Node's JSON.parse rejects it).
has_bom() {
  [ -f "$1" ] && [ "$(head -c 3 "$1")" = "$(printf '\357\273\277')" ]
}

# apply_json TARGET MERGED: back up and write TARGET only when its JSON value changes or it has a BOM.
apply_json() {
  local tgt="$1" merged="$2"
  if ! has_bom "$tgt" && json_same "$tgt" "$merged"; then
    say "  unchanged  $(show "$tgt")"
    return
  fi
  mkdir -p "$(dirname "$tgt")"
  if [ -f "$tgt" ]; then
    cp -p "$tgt" "$tgt.bak-$CMP_TS"
    say "  backup     $(show "$tgt.bak-$CMP_TS")"
    cat "$merged" >"$tgt"
    say "  merged     $(show "$tgt")"
  else
    cat "$merged" >"$tgt"
    say "  created    $(show "$tgt")"
  fi
}

install_caveman_plugin() {
  if ! command -v claude >/dev/null 2>&1; then
    say "  note       claude CLI not on PATH; enabledPlugins in settings.json enables caveman on next launch"
    return
  fi
  local out
  if out="$(claude plugin marketplace add JuliusBrussee/caveman </dev/null 2>&1)"; then
    say "  plugin     marketplace caveman added"
  else
    warn "claude plugin marketplace add failed (continuing): $(printf '%s\n' "$out" | tail -n 1)"
  fi
  if out="$(claude plugin install caveman@caveman </dev/null 2>&1)"; then
    say "  plugin     caveman@caveman installed"
  else
    warn "claude plugin install failed (continuing): $(printf '%s\n' "$out" | tail -n 1)"
  fi
}

main() {
  local base="${CMP_BASE:-https://raw.githubusercontent.com/gauravbhindwar/claude-max-perf/main}"
  base="${base%/}"

  CMP_OS="$(uname -s 2>/dev/null || true)"
  case "$CMP_OS" in
    MINGW* | MSYS* | CYGWIN*) delegate_windows "$base" ;;
  esac

  local cfg="${CLAUDE_CONFIG_DIR:-$HOME/.claude}"
  local cave_dir="${XDG_CONFIG_HOME:-$HOME/.config}/caveman"
  local settings="$cfg/settings.json" cave_cfg="$cave_dir/config.json" cave_ok=1

  CMP_TMP="$(mktemp -d 2>/dev/null || mktemp -d -t claude-max-perf)"
  trap cleanup EXIT
  CMP_TS="$(date +%Y%m%d-%H%M%S)"

  pick_json_tool
  write_helpers

  # Stage 1: fetch everything and validate before touching any user file.
  local src="$CMP_TMP/src" a
  fetch RULES.md "$src/RULES.md" "$base"
  fetch settings.fragment.json "$src/settings.fragment.json" "$base"
  for a in $CMP_AGENTS; do fetch "agents/$a.md" "$src/agents/$a.md" "$base"; done
  json_valid "$src/settings.fragment.json" || die "settings.fragment.json from source is not a JSON object"
  json_valid "$settings" || die "$settings is not valid JSON (object expected); fix it and re-run. Nothing was changed."
  json_merge "$settings" "$src/settings.fragment.json" "$CMP_TMP/settings.merged.json" ||
    die "merging $settings failed. Nothing was changed."
  printf '{"defaultMode":"ultra"}\n' >"$CMP_TMP/caveman.fragment.json"
  if ! json_valid "$cave_cfg" ||
    ! json_merge "$cave_cfg" "$CMP_TMP/caveman.fragment.json" "$CMP_TMP/caveman.merged.json"; then
    cave_ok=0
  fi

  # Stage 2: apply.
  say "claude-max-perf: installing into $(show "$cfg") (json: $CMP_JSON)"
  mkdir -p "$cfg/claude-max-perf" "$cfg/agents"
  install_file "$src/RULES.md" "$cfg/claude-max-perf/RULES.md" no
  ensure_import "$cfg/CLAUDE.md"
  for a in $CMP_AGENTS; do install_file "$src/agents/$a.md" "$cfg/agents/$a.md" yes; done
  apply_json "$settings" "$CMP_TMP/settings.merged.json"
  if [ "$cave_ok" = 1 ]; then
    apply_json "$cave_cfg" "$CMP_TMP/caveman.merged.json"
  else
    warn "$cave_cfg is not valid JSON (object expected); left unchanged. Set \"defaultMode\": \"ultra\" in it by hand."
    say "  skipped    $(show "$cave_cfg")"
  fi
  install_caveman_plugin
  say "claude-max-perf: done. Restart Claude Code to load the rules."
}

main "$@"
