#!/usr/bin/env bash
#
# DevAgent installer: puts your resident rules where Claude Code loads them.
#
#   ./install.sh                 no rules yet: copy templates/CLAUDE.md to
#                                ~/.claude/CLAUDE.md for you to edit
#   ./install.sh --rules FILE    link ~/.claude/CLAUDE.md to your own rules file
#                                (for example in a private repository you keep)
#   ./install.sh --rules FILE --copy   copy instead of link (cannot dangle, drifts)
#   ./install.sh --check         report state; exit 1 if the rules are not loaded
#   --no-search-rule             do not write the web-search allow rule
#
# The plugins are NOT installed by this script; see README.md for the two
# /plugin commands. Only individual FILES are placed, never directories, so
# anything else under ~/.claude/ is left alone. An existing file is never
# overwritten: it is moved aside to <name>.bak-<timestamp> first.

set -euo pipefail

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CLAUDE_DIR="${HOME}/.claude"
STAMP="$(date +%Y%m%d-%H%M%S)"
MODE="install"
LINK="symlink"
RULES=""
SEARCH_RULE=1

while [ $# -gt 0 ]; do
  case "$1" in
    --rules) [ $# -ge 2 ] || { echo "--rules needs a file" >&2; exit 2; }; RULES="$2"; shift ;;
    --copy) LINK="copy" ;;
    --check) MODE="check" ;;
    --no-search-rule) SEARCH_RULE=0 ;;
    --help|-h) sed -n '2,16p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
    *) echo "unknown option: $1 (try --help)" >&2; exit 2 ;;
  esac
  shift
done

green() { printf '\033[32m%s\033[0m\n' "$1"; }
yellow() { printf '\033[33m%s\033[0m\n' "$1"; }
red() { printf '\033[31m%s\033[0m\n' "$1"; }

if [ -n "$RULES" ]; then
  [ -f "$RULES" ] || { red "rules file not found: $RULES"; exit 2; }
  RULES="$(cd "$(dirname "$RULES")" && pwd)/$(basename "$RULES")"
fi

# ------------------------------------------ research: pre-approve web-search
# The delivery researcher runs ONE script, web-search. An agent's `tools:` line
# only limits which tools exist; it cannot pre-approve a command, so without a
# rule every search query prompts. This writes one allow rule naming the EXACT
# path Claude Code loads the plugin from - a wildcard would also approve a
# planted copy of a script with the same name anywhere on disk. The project's
# deny-list is still checked by the script before any query leaves the machine.
# Skip it with --no-search-rule to approve each query by hand instead.
delivery_root() {
  local r=""
  if command -v claude >/dev/null 2>&1; then
    r="$(claude plugin list --json 2>/dev/null | python3 -c 'import json,sys
try: ps=json.load(sys.stdin)
except Exception: ps=[]
for p in ps if isinstance(ps,list) else []:
    if p.get("id")=="delivery@devagent":
        print(p.get("readFromFolder") or p.get("installPath") or ""); break' 2>/dev/null || true)"
  fi
  printf '%s' "${r:-${REPO}/plugins/delivery}"
}
search_rule() {  # add|check  -> 0 ok, 1 missing/stale, 2 refused
  SETTINGS="${CLAUDE_DIR}/settings.json" ROOT="$(delivery_root)" ACTION="$1" STAMP="$STAMP" python3 - <<'PY'
import json, os, re, shutil, sys
path, root, action = os.environ["SETTINGS"], os.environ["ROOT"], os.environ["ACTION"]
if not root.startswith("/") or re.search(r"[\s*?()\[\]{}'\"\\]", root):
    print(f"refused: plugin path is not a plain absolute path: {root!r}"); sys.exit(2)
rule = f"Bash({root}/scripts/web-search:*)"
# An older rule for this script: the repository layout (.../delivery/scripts/...)
# or the plugin-cache layout, which carries the version (.../delivery/1.0.0/scripts/...).
stale = re.compile(r"^Bash\(/[^()*?\s]*/delivery(?:/[0-9][^/()*?\s]*)?/scripts/web-search:\*\)$")
try:
    cfg = json.load(open(path)) if os.path.exists(path) else {}
except (OSError, ValueError) as e:
    print(f"refused: {path} is not valid JSON ({type(e).__name__}); left untouched"); sys.exit(2)
allow = ((cfg.get("permissions") or {}).get("allow")) or []
if action == "check":
    print(("OK       research rule " + rule) if rule in allow else ("MISSING  research rule " + rule)); sys.exit(0 if rule in allow else 1)
new = [a for a in allow if not (stale.match(a) and a != rule)]
if rule not in new: new.append(rule)
if new == allow:
    print("unchanged research rule " + rule); sys.exit(0)
if os.path.exists(path):
    shutil.copy2(path, f"{path}.bak-{os.environ['STAMP']}")
    print(f"backed up settings.json -> settings.json.bak-{os.environ['STAMP']}")
cfg.setdefault("permissions", {})["allow"] = new
os.makedirs(os.path.dirname(path), exist_ok=True)
tmp = path + ".tmp"
fd = os.open(tmp, os.O_WRONLY | os.O_CREAT | os.O_TRUNC, 0o600)
with os.fdopen(fd, "w") as f: json.dump(cfg, f, indent=2); f.write("\n")
if os.path.exists(path): os.chmod(tmp, os.stat(path).st_mode & 0o777)
os.replace(tmp, path)
print("added    research rule " + rule)
PY
}

# ---------------------------------------------------------------- check mode
if [ "$MODE" = "check" ]; then
  echo "DevAgent - state check"
  # Part of the check command, so it must be able to FAIL: a missing rules
  # file or a dangling link means the resident rules are NOT loaded.
  bad=0
  dest="${CLAUDE_DIR}/CLAUDE.md"
  if [ -L "$dest" ]; then
    if [ -e "$dest" ]; then green "OK       CLAUDE.md -> $(readlink "$dest")"
    else red "DANGLING CLAUDE.md -> $(readlink "$dest")  (rules NOT loaded)"; bad=1; fi
  elif [ -f "$dest" ]; then green "OK       CLAUDE.md (your own file)"
  else red "MISSING  CLAUDE.md  (rules NOT loaded; run ./install.sh)"; bad=1; fi
  for f in claudedocs/notes-template.md clients.local.md; do
    if [ -e "${CLAUDE_DIR}/$f" ]; then green "OK       $f"; else yellow "missing  $f (run ./install.sh)"; fi
  done
  search_rule check || yellow "         (research searches will ask each time; ./install.sh adds it)"
  [ "$bad" -eq 0 ] || { red "FAIL: the resident rules are not loaded"; exit 1; }
  exit 0
fi

place() {  # place SRC DEST - link or copy; a different real file is backed up first
  local src="$1" dest="$2"
  mkdir -p "$(dirname "$dest")"
  if [ -L "$dest" ]; then rm "$dest"
  elif [ -e "$dest" ]; then
    if cmp -s "$src" "$dest"; then rm "$dest"
    else mv "$dest" "${dest}.bak-${STAMP}"; yellow "backed up ${dest} -> ${dest}.bak-${STAMP}"; fi
  fi
  if [ "$LINK" = "symlink" ]; then ln -s "$src" "$dest"; green "linked  ${dest#"$HOME"/}"
  else cp "$src" "$dest"; green "copied  ${dest#"$HOME"/}"; fi
}

mkdir -p "$CLAUDE_DIR"

# --------------------------------------------------------------- resident rules
if [ -n "$RULES" ]; then
  place "$RULES" "${CLAUDE_DIR}/CLAUDE.md"
elif [ -e "${CLAUDE_DIR}/CLAUDE.md" ] || [ -L "${CLAUDE_DIR}/CLAUDE.md" ]; then
  yellow "kept    .claude/CLAUDE.md (already present; use --rules FILE to point it elsewhere)"
else
  cp "${REPO}/templates/CLAUDE.md" "${CLAUDE_DIR}/CLAUDE.md"
  green "created .claude/CLAUDE.md from templates/CLAUDE.md - edit it: replace every [PLACEHOLDER]"
fi

# ------------------------------------------------------------ notes template
place "${REPO}/templates/notes-template.md" "${CLAUDE_DIR}/claudedocs/notes-template.md"

# --------------------------------------------------- client brand list (600)
# CLAUDE.md imports @clients.local.md. Every client name is already
# constrained by the rules themselves, so an empty list is a safe state; the
# file only withdraws the single exception (explicit authorization) for the
# brands listed. A rules repository of your own may keep it beside CLAUDE.md.
clients="${CLAUDE_DIR}/clients.local.md"
if [ -n "$RULES" ] && [ -f "$(dirname "$RULES")/clients.local.md" ]; then
  place "$(dirname "$RULES")/clients.local.md" "$clients"
elif [ ! -e "$clients" ]; then
  ( umask 077
    { printf '# Client brands that cannot be authorized - LIVE FILE, never commit\n\n'
      printf 'Created by install.sh on %s. An empty list below is a deliberate,\n' "$(date +%Y-%m-%d)"
      printf 'safe state: every client name is already constrained by the rules.\n\n'
      sed -n '/^---$/,$p' "${REPO}/templates/clients.local.md.example"; } > "$clients" )
  green "created .claude/clients.local.md (optional, mode 600)"
fi
[ -L "$clients" ] || chmod 600 "$clients"

# ------------------------------------------------------------ research rule
echo
if [ "$SEARCH_RULE" -eq 1 ]; then
  search_rule add || { rc=$?; [ "$rc" -eq 2 ] && red "research rule not written (see above)"; }
fi

# ------------------------------------------------------------------- verify
[ -e "${CLAUDE_DIR}/CLAUDE.md" ] || { red "VERIFY FAILED: ~/.claude/CLAUDE.md is not readable"; exit 1; }
green "rules in place: ~/.claude/CLAUDE.md"

cat <<'NEXT'

Next, inside Claude Code, install the plugins:

  /plugin marketplace add https://github.com/mrjones-cs/devagent
  /plugin install devagent-standards@devagent
  /plugin install delivery@devagent

Then run ./install.sh once more, so the research rule names the path the
plugin actually loads from, and start a NEW session: /context should list
the 14 devagent-standards skills and the 9 delivery skills.
NEXT
