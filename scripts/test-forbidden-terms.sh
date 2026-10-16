#!/usr/bin/env bash
#
# Tests for scripts/check-forbidden-terms.sh, against throwaway git repositories.
#
#     bash scripts/test-forbidden-terms.sh
#
# A scanner that matches nothing reports clean, so every place a leak can hide
# gets a case that MUST fail, and a failing run must never print the term.
#
set -uo pipefail

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SUBJECT="$REPO/scripts/check-forbidden-terms.sh"
ROOT="$(mktemp -d /tmp/devagent-terms.XXXXXX)"
trap 'rm -rf "$ROOT"' EXIT
TERM_="zq7forbidden"      # a made-up term; the tests never use a real one
PASS=0
FAIL=0

ok()  { PASS=$((PASS+1)); printf '  \033[32mPASS\033[0m  %s\n' "$1"; }
bad() { FAIL=$((FAIL+1)); printf '  \033[31mFAIL\033[0m  %s\n' "$1"; }
check() { if [ "$1" = "$2" ]; then ok "$3"; else bad "$3 (expected '$2', got '$1')"; fi; }

newrepo() {  # prints a fresh repo path with one clean commit. mktemp, not a counter:
             # this runs inside $(...), a subshell, so a counter would never advance
             # and every case would share one repository.
  local d; d="$(mktemp -d "$ROOT/repo.XXXXXX")"
  git -C "$d" init -q -b main
  printf 'nothing to see here\n' > "$d/a.txt"
  git -C "$d" add -A && commit "$d" "first commit" >/dev/null
  printf '%s' "$d"
}
commit() {  # commit DIR MESSAGE [AUTHOR]
  git -C "$1" -c user.name="${3:-tester}" -c user.email=tester@example.invalid \
      -c commit.gpgsign=false -c core.hooksPath=/dev/null commit -q --allow-empty -m "$2"
}
run() {  # run DIR [env pattern] [args...]  -> sets OUT and RC
  local d="$1" pat="$2"; shift 2
  OUT="$(cd "$d" && FORBIDDEN_TERMS="$pat" bash "$SUBJECT" "$@" 2>&1)"; RC=$?
}
leaks() { printf '%s' "$OUT" | grep -ciE -- "$TERM_" || true; }

echo "check-forbidden-terms.sh tests"; echo

R="$(newrepo)"; run "$R" "$TERM_" --require
check "$RC" "0" "a clean repository passes"
printf '%s' "$OUT" | grep -q '^ok:' && ok "and says so" || bad "no ok line: $OUT"

R="$(newrepo)"; printf 'see %s here\n' "$TERM_" > "$R/b.txt"; git -C "$R" add -A; commit "$R" "add b" >/dev/null
run "$R" "$TERM_" --require
check "$RC" "1" "a term in a file's contents fails"
printf '%s' "$OUT" | grep -q 'b.txt' && ok "the file is named" || bad "file not named: $OUT"
check "$(leaks)" "0" "the output does not contain the term"

R="$(newrepo)"; printf 'x %s x\n' "$(printf '%s' "$TERM_" | tr a-z A-Z)" > "$R/c.txt"; git -C "$R" add -A; commit "$R" "add c" >/dev/null
run "$R" "$TERM_" --require
check "$RC" "1" "a term in a different case fails (matching is case-insensitive)"

R="$(newrepo)"; : > "$R/${TERM_}-notes.txt"; git -C "$R" add -A; commit "$R" "add a file" >/dev/null
run "$R" "$TERM_" --require
check "$RC" "1" "a term in a file NAME fails"
printf '%s' "$OUT" | grep -q 'name' && ok "reported as a name hit" || bad "no name report: $OUT"
check "$(leaks)" "0" "the name hit does not print the name"

R="$(newrepo)"; commit "$R" "mentions $TERM_ in the message"
run "$R" "$TERM_" --require
check "$RC" "1" "a term only in a commit MESSAGE fails"
check "$(leaks)" "0" "the message hit does not print the message"

R="$(newrepo)"; commit "$R" "innocent message" "Jane $TERM_"
run "$R" "$TERM_" --require
check "$RC" "1" "a term only in a commit AUTHOR name fails"

R="$(newrepo)"; printf 'x%s\n' "$TERM_" > "$R/d.txt"; git -C "$R" add -A; commit "$R" "add d" >/dev/null
git -C "$R" rm -q d.txt; commit "$R" "remove d" >/dev/null
run "$R" "$TERM_" --require
check "$RC" "1" "a term added and later deleted still fails (it stays in history)"
printf '%s' "$OUT" | grep -q 'history' && ok "and the report says it is in history" || bad "no history report: $OUT"

R="$(newrepo)"; printf 'AB\000CD%s\000EF' "$TERM_" > "$R/e.bin"; git -C "$R" add -A; commit "$R" "add binary" >/dev/null
run "$R" "$TERM_" --require
check "$RC" "1" "a term inside a binary file fails"

# The history scan would also see a COMMITTED leak, so the tree scan is only
# tested alone by an edit that has not been committed.
R="$(newrepo)"; printf 'edited %s\n' "$(printf '%s' "$TERM_" | tr a-z A-Z)" > "$R/a.txt"
run "$R" "$TERM_" --require
check "$RC" "1" "an UNCOMMITTED edit (upper-case) to a tracked file fails: the tree scan alone, case-insensitively"

R="$(newrepo)"; printf 'AB\000CD\000' > "$R/g.bin"; git -C "$R" add -A; commit "$R" "add clean binary" >/dev/null
printf 'AB\000CD%s\000' "$TERM_" > "$R/g.bin"
run "$R" "$TERM_" --require
check "$RC" "1" "an UNCOMMITTED edit to a tracked binary file fails: the tree scan alone"

R="$(newrepo)"; printf 'AB\000CD%s\000EF' "$TERM_" > "$R/h.bin"; git -C "$R" add -A; commit "$R" "add binary" >/dev/null
git -C "$R" rm -q h.bin; commit "$R" "remove binary" >/dev/null
run "$R" "$TERM_" --require
check "$RC" "1" "a term in a binary file that was added and later deleted still fails (history, --text)"

R="$(newrepo)"; printf 'z %s z\n' "$TERM_" > "$R/f.txt"; git -C "$R" add -A; commit "$R" "add f" >/dev/null
run "$R" "other|$TERM_|another" --require
check "$RC" "1" "a pattern with several alternatives finds the one that is present"

R="$(newrepo)"; printf 'z %s z\n' "$TERM_" > "$R/g.txt"; git -C "$R" add -A; commit "$R" "add g" >/dev/null
run "$R" "unrelated" --require
check "$RC" "0" "a pattern that is not present passes"

R="$(newrepo)"; run "$R" ""
check "$RC" "0" "no pattern, no --require: skipped with exit 0"
printf '%s' "$OUT" | grep -q '^skipped' && ok "and says it was skipped" || bad "no skip line: $OUT"
run "$R" "" --require
check "$RC" "2" "no pattern with --require is an error, so CI cannot pass silently"

run "$R" "(" --require
check "$RC" "2" "an invalid pattern is an error"

NOREPO="$ROOT/plain"; mkdir -p "$NOREPO"; run "$NOREPO" "$TERM_" --require
check "$RC" "2" "outside a git repository is an error"

run "$R" "$TERM_" --bogus
check "$RC" "2" "an unknown option is an error"

echo
echo "$PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
