#!/usr/bin/env bash
#
# Behaviour tests for install.sh, run against a throwaway HOME.
#
#     bash scripts/test-install.sh
#
# install.sh targets "${HOME}/.claude", so overriding HOME is enough to
# exercise it for real without touching your config. Every test asserts on
# OBSERVED state (files, links, modes, exit codes), not on the script's output.

set -uo pipefail

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PASS=0
FAIL=0
# Every sandbox lives under ONE parent removed on exit. (A list appended to
# inside "$(sandbox)" would be lost: command substitution runs in a subshell.)
ROOT="$(mktemp -d /tmp/devagent-test.XXXXXX)"
trap 'rm -rf "$ROOT"' EXIT

sandbox() { mktemp -d "$ROOT/home.XXXXXX"; }

ok()   { PASS=$((PASS+1)); printf '  \033[32mPASS\033[0m  %s\n' "$1"; }
bad()  { FAIL=$((FAIL+1)); printf '  \033[31mFAIL\033[0m  %s\n' "$1"; }
check() { if [ "$1" = "$2" ]; then ok "$3"; else bad "$3 (expected '$2', got '$1')"; fi; }
mode_of() { ls -l "$1" | awk '{print substr($1,1,10)}'; }

echo "install.sh behaviour tests"
echo "repo: $REPO"
echo

# ---------------------------------------------------------------- 1. syntax
bash -n "$REPO/install.sh" && ok "install.sh parses" || bad "install.sh has a syntax error"

# --------------------------------------- 2. default: no rules yet, template
H="$(sandbox)"
HOME="$H" "$REPO/install.sh" >/dev/null 2>&1
check "$?" "0" "default install exits 0 on a virgin HOME"
[ -f "$H/.claude/CLAUDE.md" ] && [ ! -L "$H/.claude/CLAUDE.md" ] \
  && ok "CLAUDE.md is a real file the user can edit" || bad "CLAUDE.md was not created as a real file"
cmp -s "$H/.claude/CLAUDE.md" "$REPO/templates/CLAUDE.md" \
  && ok "CLAUDE.md starts as templates/CLAUDE.md" || bad "CLAUDE.md is not the template"
[ "$(readlink "$H/.claude/claudedocs/notes-template.md")" = "$REPO/templates/notes-template.md" ] \
  && ok "notes template is linked" || bad "notes template is not linked"
check "$(mode_of "$H/.claude/clients.local.md")" "-rw-------" "clients.local.md is created mode 600"
grep -q 'LIVE FILE' "$H/.claude/clients.local.md" \
  && ok "the created brand list is marked live, not the template" || bad "the brand list still reads as the template"

HOME="$H" "$REPO/install.sh" --check >/dev/null 2>&1
check "$?" "0" "--check exits 0 when the rules are in place"

# ------------------------------- 3. never clobbers a user's own CLAUDE.md
printf 'my own rules\n' > "$H/.claude/CLAUDE.md"
HOME="$H" "$REPO/install.sh" >/dev/null 2>&1
check "$(cat "$H/.claude/CLAUDE.md")" "my own rules" "an existing CLAUDE.md is kept, never overwritten"
printf 'machine-local\n' > "$H/.claude/claudedocs/my-local-note.md"
HOME="$H" "$REPO/install.sh" >/dev/null 2>&1
[ -f "$H/.claude/claudedocs/my-local-note.md" ] \
  && ok "other files under claudedocs/ survive" || bad "a machine-local file was removed"

# --------------------------------------------- 4. --rules FILE links it
H="$(sandbox)"; R="$(sandbox)"
printf '# Org rules\n@clients.local.md\n' > "$R/CLAUDE.md"
printf '# brands\n- Example Brand\n' > "$R/clients.local.md"; chmod 600 "$R/clients.local.md"
mkdir -p "$H/.claude"; printf 'old real file\n' > "$H/.claude/CLAUDE.md"
HOME="$H" "$REPO/install.sh" --rules "$R/CLAUDE.md" >/dev/null 2>&1
check "$?" "0" "--rules exits 0"
check "$(readlink "$H/.claude/CLAUDE.md")" "$R/CLAUDE.md" "--rules links CLAUDE.md to the given file"
check "$(ls "$H/.claude/" | grep -c 'CLAUDE.md.bak-')" "1" "the real file it replaced is backed up first"
check "$(readlink "$H/.claude/clients.local.md")" "$R/clients.local.md" "a clients.local.md beside the rules file is linked too"

HOME="$H" "$REPO/install.sh" --rules "$R/CLAUDE.md" >/dev/null 2>&1
check "$(ls "$H/.claude/" | grep -c 'CLAUDE.md.bak-')" "1" "re-running --rules makes no further backup"

H2="$(sandbox)"
HOME="$H2" "$REPO/install.sh" --rules "$R/CLAUDE.md" --copy >/dev/null 2>&1
[ -f "$H2/.claude/CLAUDE.md" ] && [ ! -L "$H2/.claude/CLAUDE.md" ] && cmp -s "$H2/.claude/CLAUDE.md" "$R/CLAUDE.md" \
  && ok "--copy places a real copy" || bad "--copy did not place a copy"
HOME="$H2" "$REPO/install.sh" --rules "$R/CLAUDE.md" --copy >/dev/null 2>&1
check "$(ls "$H2/.claude/" | grep -c 'CLAUDE.md.bak-')" "0" "re-running --copy on an identical file makes no backup"

HOME="$(sandbox)" "$REPO/install.sh" --rules "$R/NOPE.md" >/dev/null 2>&1
check "$?" "2" "--rules with a missing file exits 2"

# ------------------------------------------- 5. --check must be able to FAIL
H="$(sandbox)"; mkdir -p "$H/.claude"
HOME="$H" "$REPO/install.sh" --check >/dev/null 2>&1
check "$?" "1" "--check exits 1 with no CLAUDE.md"
ln -s "$R/GONE.md" "$H/.claude/CLAUDE.md"
HOME="$H" "$REPO/install.sh" --check >/dev/null 2>&1
check "$?" "1" "--check exits 1 on a dangling CLAUDE.md link"

# --------------------------------------------- 6. research allow rule
RULE="Bash(${REPO}/plugins/delivery/scripts/web-search:*)"
rules() { python3 -c 'import json,sys;print("\n".join(json.load(open(sys.argv[1])).get("permissions",{}).get("allow",[])))' "$1/.claude/settings.json"; }
H="$(sandbox)"; HOME="$H" "$REPO/install.sh" >/dev/null 2>&1
check "$(rules "$H" | grep -cxF "$RULE")" "1" "adds the exact-path web-search rule once"
check "$(mode_of "$H/.claude/settings.json")" "-rw-------" "a settings.json it creates is mode 600"
HOME="$H" "$REPO/install.sh" >/dev/null 2>&1
check "$(rules "$H" | grep -cxF "$RULE")" "1" "re-running does not duplicate the rule"
check "$(ls "$H/.claude/" | grep -c 'settings.json.bak-')" "0" "re-running with nothing to change makes no backup"
case "$RULE" in *'*'*':*)'|*'*/'*) bad "rule contains a wildcard path" ;; *) ok "rule names an exact path, no wildcard" ;; esac

H="$(sandbox)"; mkdir -p "$H/.claude"
printf '%s' '{"env":{"KEEP":"1"},"permissions":{"allow":["Bash(git status)","Bash(/old/place/plugins/delivery/scripts/web-search:*)"]}}' > "$H/.claude/settings.json"
HOME="$H" "$REPO/install.sh" >/dev/null 2>&1
check "$(python3 -c 'import json,sys;print(json.load(open(sys.argv[1]))["env"]["KEEP"])' "$H/.claude/settings.json")" "1" "other settings are preserved"
check "$(rules "$H" | grep -cxF 'Bash(git status)')" "1" "other allow rules are preserved"
check "$(rules "$H" | grep -c '/old/place/')" "0" "a stale rule for an old plugin path is replaced"

# A plugin update moves the cache folder (it carries the version). The old
# versioned rule must be replaced, not left behind.
H="$(sandbox)"; mkdir -p "$H/.claude"
printf '%s' '{"permissions":{"allow":["Bash(git status)","Bash(/home/u/.claude/plugins/cache/devagent/delivery/0.9.0/scripts/web-search:*)","Bash(/home/u/other-tool/scripts/web-search:*)"]}}' > "$H/.claude/settings.json"
HOME="$H" "$REPO/install.sh" >/dev/null 2>&1
check "$(rules "$H" | grep -c 'delivery/0.9.0')" "0" "an old versioned cache-path rule is replaced after a plugin update"
check "$(rules "$H" | grep -c 'other-tool')" "1" "a web-search rule for some other tool is left alone"
check "$(rules "$H" | grep -c 'delivery/scripts/web-search\|delivery/[0-9.]*/scripts/web-search')" "1" "exactly one rule for this plugin remains"
check "$(ls "$H/.claude/" | grep -c 'settings.json.bak-')" "1" "an edited settings.json is backed up first"

H="$(sandbox)"; mkdir -p "$H/.claude"; printf '{not json' > "$H/.claude/settings.json"
HOME="$H" "$REPO/install.sh" >/dev/null 2>&1
check "$?" "0" "invalid settings.json does not abort the install"
check "$(cat "$H/.claude/settings.json")" "{not json" "invalid settings.json is left untouched"

H="$(sandbox)"; HOME="$H" "$REPO/install.sh" --no-search-rule >/dev/null 2>&1
[ ! -e "$H/.claude/settings.json" ] && ok "--no-search-rule writes no rule" || bad "--no-search-rule still wrote settings.json"

H="$(sandbox)"; HOME="$H" "$REPO/install.sh" >/dev/null 2>&1
CK="$(HOME="$H" "$REPO/install.sh" --check 2>&1)"
printf '%s\n' "$CK" | grep -qF "OK       research rule $RULE" && ok "--check reports the rule" || bad "--check does not report the rule"

# ------------------------------------------- 7. next-steps install lines
OUT="$(HOME="$(sandbox)" "$REPO/install.sh" 2>&1)"
for p in devagent-standards delivery; do
  printf '%s\n' "$OUT" | grep -qx "  /plugin install $p@devagent" \
    && ok "prints the $p install line" || bad "missing the $p install line"
done

# ------------------------------------- 8. a fresh clone tracks no live list
if command -v git >/dev/null 2>&1 && git -C "$REPO" rev-parse >/dev/null 2>&1; then
  git -C "$REPO" ls-files --error-unmatch templates/clients.local.md >/dev/null 2>&1 \
    && bad "a live clients.local.md is tracked - it must not be" \
    || ok "no live clients.local.md is tracked"
fi

# ------------------------------------------------------- 9. arg handling
HOME="$(sandbox)" "$REPO/install.sh" --bogus >/dev/null 2>&1
check "$?" "2" "an unknown option exits 2"
HOME="$(sandbox)" "$REPO/install.sh" --help >/dev/null 2>&1
check "$?" "0" "--help exits 0"

echo
echo "$PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ] || exit 1
