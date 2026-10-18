#!/usr/bin/env bash
#
# Tests for plugins/delivery/scripts/check-plan.py (T-03).
#
#     bash scripts/test-check-plan.sh              run the tests
#     bash scripts/test-check-plan.sh --coverage   run them under coverage (pinned
#                                                  in plugins/delivery/PINS.md) and
#                                                  print line and branch coverage
#
# The `good` fixture must pass; every `bad-<rule>` fixture must fail AND name
# that rule, and only that rule - a check that cannot fail is not a check (G-2).
# Everything runs on a COPY of the fixtures in a temp directory; the checker
# only reads, and nothing in the repository is modified.

set -uo pipefail

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CHECKER="$REPO/plugins/delivery/scripts/check-plan.py"
FIXTURES="$REPO/tests/fixtures/plans"
COVERAGE_PIN="coverage==7.16.2"

if [ "${1:-}" = "--coverage" ]; then
  covdir="$(mktemp -d /tmp/devagent-checkplan-cov.XXXXXX)"
  trap 'rm -rf "$covdir"' EXIT
  export COVERAGE_FILE="$covdir/.coverage"
  uv run --no-project --with "$COVERAGE_PIN" bash "$0"
  rc=$?
  ( cd "$covdir" && uv run --no-project --with "$COVERAGE_PIN" python -m coverage combine -q \
      && uv run --no-project --with "$COVERAGE_PIN" python -m coverage report --show-missing \
           --include="*check-plan.py" --format=text \
      && uv run --no-project --with "$COVERAGE_PIN" python -m coverage json -q -o "$covdir/cov.json" \
           --include="*check-plan.py" ) || rc=1
  python3 - "$covdir/cov.json" <<'PY' || rc=1
import json, sys
t = json.load(open(sys.argv[1]))["totals"]
line = 100.0 * t["covered_lines"] / t["num_statements"]
branch = 100.0 * t["covered_branches"] / t["num_branches"]
print(f"line coverage {line:.1f}%  branch coverage {branch:.1f}%  (gate G-3: >= 80% each)")
sys.exit(0 if line >= 80 and branch >= 80 else 1)
PY
  exit "$rc"
fi

if [ -n "${COVERAGE_FILE:-}" ]; then
  RUN=(python3 -m coverage run --branch --parallel-mode "$CHECKER")
else
  RUN=(python3 "$CHECKER")
fi

PASS=0
FAIL=0
WORK="$(mktemp -d /tmp/devagent-checkplan.XXXXXX)"
trap 'rm -rf "$WORK"' EXIT
R="$WORK/repo"
mkdir -p "$R/.delivery" "$R/tests/fixtures"
cp -R "$FIXTURES" "$R/tests/fixtures/plans"
# Engagement deny-list for the copy only (bad-deny-list plants this term).
printf '# fixture deny-list\n\nzebra holdings\n' >"$R/.delivery/deny-list"
P="$R/tests/fixtures/plans"

ok()   { PASS=$((PASS+1)); printf '  \033[32mPASS\033[0m %s\n' "$1"; }
bad()  { FAIL=$((FAIL+1)); printf '  \033[31mFAIL\033[0m %s\n' "$1"; [ -n "${2:-}" ] && printf '%s\n' "$2" | sed 's/^/         /'; }

# check DIR-OR-ARGS... : runs the checker from $R, captures stdout+stderr and rc
check() { OUT="$(cd "$R" && "${RUN[@]}" "$@" 2>&1)"; RC=$?; }

# expect_only NAME RULE ARGS... : exit 1, output names RULE, and nothing else
expect_only() {
  local name="$1" rule="$2"; shift 2
  check "$@"
  local others
  others="$(printf '%s\n' "$OUT" | grep -v -F "[$rule]" | grep -v '^$')"
  if [ "$RC" -eq 1 ] && printf '%s' "$OUT" | grep -q -F "[$rule]" && [ -z "$others" ]; then
    ok "$name"
  else
    bad "$name (exit $RC, wanted 1 naming only [$rule])" "$OUT"
  fi
}

# expect_rule NAME RULE ARGS... : exit 1 and output names RULE (others allowed)
expect_rule() {
  local name="$1" rule="$2"; shift 2
  check "$@"
  if [ "$RC" -eq 1 ] && printf '%s' "$OUT" | grep -q -F "[$rule]"; then ok "$name"; else bad "$name (exit $RC, wanted [$rule])" "$OUT"; fi
}

# mutate NEW FILE OLD NEW_TEXT : copy good to $P/NEW and replace OLD (exactly once) in FILE
mutate() {
  rm -rf "${P:?}/$1"; cp -R "$P/good" "$P/$1"
  python3 - "$P/$1/$2" "$3" "$4" <<'PY'
import sys
path, old, new = sys.argv[1:]
text = open(path, encoding="utf-8").read()
assert text.count(old) == 1, f"mutation anchor not unique in {path}: {old!r}"
open(path, "w", encoding="utf-8").write(text.replace(old, new))
PY
}

echo "check-plan.py tests"

# ---- the good fixture -------------------------------------------------------
check tests/fixtures/plans/good
if [ "$RC" -eq 0 ] && [ "$(printf %s "$OUT" | grep -cvE '^checked [0-9]+ documents in [0-9]+ plan folder\(s\): clean$')" -eq 0 ] && printf %s "$OUT" | grep -qE '^checked [0-9]+ documents'; then ok "good fixture passes with only the clean summary"; else bad "good fixture (exit $RC)" "$OUT"; fi
# T-07: a plan folder generated purely from the templates must pass as written.
check tests/fixtures/plans/from-templates
[ "$RC" -eq 0 ] && printf %s "$OUT" | grep -qE '^checked 5 documents' && ok "plan generated from the templates passes" || bad "from-templates fixture (exit $RC)" "$OUT"
# A review finding that sends a question to the operator points at a D-n the
# design template itself defines. The template once wrote decisions as bullets,
# which the checker (rightly) does not read as definitions.
FT="$WORK/from-templates-decision"; cp -R tests/fixtures/plans/from-templates "$FT"
python3 - "$FT/04-review.md" <<'PYX'
import re, sys
p = sys.argv[1]; s = open(p).read()
s = s.replace("- outcome: rejected — out of scope for this tier", "- outcome: needs-decision — D-1", 1)
open(p, "w").write(s)
PYX
check "$FT"
printf '%s\n' "$OUT" | grep -qF 'D-1, which is not defined' && bad "a template-written D-1 is not seen as defined by the checker" "$OUT" || ok "the design template's own D-1 is a definition the checker accepts"

# ---- one bad-<rule> fixture per rule ----------------------------------------
# fixture directory -> rule it must name (and the only rule it may name)
while read -r dir rule; do
  [ -z "$dir" ] && continue
  if [ -d "$P/$dir" ]; then expect_only "$dir" "$rule" "tests/fixtures/plans/$dir"
  else bad "$dir fixture is missing"; fi
done <<'EOF'
bad-duplicate-id duplicate-id
bad-dangling-ref dangling-ref
bad-depends-cycle depends-cycle
bad-evidence evidence
bad-evidence-hash evidence-hash
bad-evidence-log-missing evidence-hash
bad-evidence-zero-tests evidence
bad-evidence-manual evidence
bad-review-outcome review-outcome
bad-review-outcome-vocabulary review-outcome
bad-applied-change applied-change
bad-needs-decision needs-decision
bad-verify-allowlist verify-allowlist
bad-verify-metachar verify-metachar
bad-source-allowlist source-allowlist
bad-source-allowlist-github source-allowlist
bad-deny-list deny-list
bad-blocked-reason blocked-reason
bad-in-progress-owner in-progress-owner
bad-front-matter front-matter
bad-status status
bad-format format
bad-table-separator table-separator
bad-id-pattern id-pattern
bad-change-source change-source
bad-research-grammar research-grammar
bad-task-grammar task-grammar
bad-review-grammar review-grammar
EOF

# the deny-listed term must never be echoed (the deny-list is confidential)
check tests/fixtures/plans/bad-deny-list
if printf '%s' "$OUT" | grep -qi zebra; then bad "deny-list output echoes the term" "$OUT"; else ok "deny-list output does not echo the term"; fi

# ---- every shell metacharacter, each on the allowlist so only it can fire ---
for ch in ';' '|' '&' '$' '`' '>' '<'; do
  mutate "mc" 05-implementation.md "  - python3 scripts/check.py
" "  - python3 scripts/check.py
  - bash scripts/test-thing.sh ${ch} x
"
  python3 - "$P/mc/05-implementation.md" "bash scripts/test-thing.sh ${ch} x" <<'PY'
import sys
p, cmd = sys.argv[1:]
t = open(p, encoding="utf-8").read()
old = "- verify: `bash scripts/test-thing.sh`\n- timeout: 30s"
assert t.count(old) == 1
open(p, "w", encoding="utf-8").write(t.replace(old, "- verify: `" + cmd + "`\n- timeout: 30s"))
PY
  expect_only "verify with metacharacter ${ch}" verify-metachar tests/fixtures/plans/mc
done

# ---- more grammar cases (each a negative test, and coverage of the checker) --
mutate m 03-research.md "## Queries sent" "## Queries"
expect_only "03 without a Queries sent section" research-grammar tests/fixtures/plans/m
mutate m 03-research.md "| web-search |" "| bing |"
expect_only "research engine off the vocabulary" research-grammar tests/fixtures/plans/m
mutate m 03-research.md "| 2026-10-02 | manual |" "| last week | manual |"
expect_only "research Checked not a date" research-grammar tests/fixtures/plans/m
mutate m 03-research.md "· live: terraform version" "· the registry page"
expect_only "research source part neither URL nor live:" research-grammar tests/fixtures/plans/m
mutate m 03-research.md "| Checked | Engine |
|---|---|---|---|---|---|---|
| A-01" "| Checked |
|---|---|---|---|---|---|
| A-01"
expect_only "research table without Engine column" research-grammar tests/fixtures/plans/m
mutate m 03-research.md "https://github.com/nodejs/node/releases" "live: node --version"
expect_only "⛔ row with no official URL" source-allowlist tests/fixtures/plans/m
mutate m 01-requirements.md "generator: delivery@v1.4.0" "generator: superclaude"
expect_only "generator not delivery@<tag>" front-matter tests/fixtures/plans/m
mutate m 01-requirements.md "date: 2026-10-01" "date: October 1"
expect_only "date not YYYY-MM-DD" front-matter tests/fixtures/plans/m
mutate m 01-requirements.md "step: 01-requirements" "step: 01-brief"
expect_only "step off the vocabulary" front-matter tests/fixtures/plans/m
mutate m 04-review.md "step: 04-review" "step: 02-design"
expect_rule "step does not match file name" front-matter tests/fixtures/plans/m
mutate m 01-requirements.md "tier: M
" ""
expect_only "01 without tier" front-matter tests/fixtures/plans/m
mutate m 01-requirements.md "## Data handled

none stated
" ""
expect_only "01 without a Data handled section" requirements-sections tests/fixtures/plans/m
mutate m 01-requirements.md "## Client constraints

none stated
" "## Client constraints
<!-- left for later -->
"
expect_only "01 with an empty Client constraints section" requirements-sections tests/fixtures/plans/m
mutate m 04-review.md "reads: 02-design.md, 03-research.md
" ""
expect_only "04 without reads" front-matter tests/fixtures/plans/m
mutate m 04-review.md "reads: 02-design.md, 03-research.md" "reads: 02-design.md, 09-missing.md"
expect_only "reads names a missing file" dangling-ref tests/fixtures/plans/m
mutate m 01-requirements.md "---
format" "format"
expect_only "file without front matter" front-matter tests/fixtures/plans/m
mutate m 05-implementation.md "verify_allowed:
  - bash scripts/test-thing.sh
  - python3 scripts/check.py" "verify_allowed:"
expect_rule "empty verify_allowed" front-matter tests/fixtures/plans/m
mutate m 05-implementation.md "manual_evidence: [T-02]   # written by hand before run-verify existed" "manual_evidence: T-02"
expect_rule "manual_evidence not a list" front-matter tests/fixtures/plans/m
mutate m 05-implementation.md "### T-05 [ ] Build" "### T-05 [?] Build"
expect_only "task state off the vocabulary" task-grammar tests/fixtures/plans/m
mutate m 05-implementation.md "### T-05 [ ] Build the last thing" "### T-05 Build the last thing"
expect_rule "task heading without a state" task-grammar tests/fixtures/plans/m
mutate m 05-implementation.md "- depends: T-04" "- depends: the third one"
expect_only "depends not T-nn" task-grammar tests/fixtures/plans/m
mutate m 05-implementation.md "- timeout: 30s" "- timeout: soon"
expect_only "timeout not <n>s|m|h" task-grammar tests/fixtures/plans/m
mutate m 05-implementation.md "- depends: T-04" "- depends: T-4"
expect_rule "depends with a one-digit ID" id-pattern tests/fixtures/plans/m
mutate m 05-implementation.md "· log evidence/T-01.log sha256" "· logfile evidence/T-01.log sha256"
expect_only "evidence not in run-verify form" evidence tests/fixtures/plans/m
mutate m 05-implementation.md "exit 0 · tests 12" "exit 1 · tests 12"
expect_only "evidence with a non-zero exit" evidence tests/fixtures/plans/m
mutate m 05-implementation.md "log evidence/T-01.log" "log evidence/T-02.log"
expect_rule "evidence log named for another task" evidence tests/fixtures/plans/m
mutate m 04-review.md "applied → C-02" "applied → C-2"
expect_rule "outcome cites a one-digit change ID" id-pattern tests/fixtures/plans/m
mutate m 04-review.md "- outcome: rejected — the diagram was already redrawn under C-03" "- outcome: needs-decision — D-7"
expect_rule "needs-decision on an undefined decision" dangling-ref tests/fixtures/plans/m
mutate m 02-design.md "| research A-02, R-01 |" "| research A-07 |"
expect_only "change-log source cites an undefined assumption" dangling-ref tests/fixtures/plans/m
mutate m 02-design.md "| C-04 | 2026-10-05 | T-01 |" "| C-04 | 2026-10-05 | T-1 |"
expect_rule "change-log source with a one-digit task ID" id-pattern tests/fixtures/plans/m
mutate m 02-design.md "| ID | Date | Source | Section | Change |" "| ID | Date | Origin | Section | Change |"
expect_only "change log without a Source column" change-source tests/fixtures/plans/m
mutate m 03-research.md "| X-01 | A runtime is deprecated" "| A-01 | A runtime is deprecated"
expect_only "same A-nn twice in one research file" duplicate-id tests/fixtures/plans/m
cp "$P/good/03-research.md" "$P/m/03-research-addendum.md"
expect_rule "same A-nn in two research files" duplicate-id tests/fixtures/plans/m
rm -rf "$P/m"; cp -R "$P/good" "$P/m"; rm "$P/m/02-design.md"
expect_rule "applied → C-nn with no 02 at all" applied-change tests/fixtures/plans/m
rm -rf "$P/m"; mkdir -p "$P/m"
expect_only "folder with no plan files" front-matter tests/fixtures/plans/m
rm -rf "$P/m"

# ---- output sanitiser (02 §1.4, R-05) -----------------------------------------
# Invalid values hold ESC, U+202E and an embedded newline. Plan lines cannot
# carry a newline (the file is read line by line), so the newline rides in the
# folder name, which every failure line prints; it also tries to forge a rule.
SAN="$(python3 - "$P" <<'PY'
import shutil, sys
plans = sys.argv[1]
name = "san\n[status] forged\x1b[31m\u202e"
dst = f"{plans}/{name}"
shutil.copytree(f"{plans}/good", dst)
for fname, old, new in [
    ("01-requirements.md", "status: approved", "status: ap\x1b[2Jpro\u202eved"),
    ("03-research.md", "| 2026-10-02 | web-search |", "| 2026-10-02 | web\x1b]0;x\x07\u202esearch |"),
]:
    p = f"{dst}/{fname}"
    t = open(p, encoding="utf-8").read()
    assert t.count(old) == 1, old
    open(p, "w", encoding="utf-8").write(t.replace(old, new))
print(name, end="")
PY
)"
check "tests/fixtures/plans/$SAN"
SAN_OUT="$OUT" python3 - <<'PY' && ok "ESC, U+202E and a newline print as ? and each failure stays on one line" || bad "sanitiser on control characters (exit $RC)" "$OUT"
import os, re, sys
out = os.environ["SAN_OUT"]
lines = out.split("\n")
line_re = re.compile(r"^tests/fixtures/plans/san\?\[status\] forged\?\[31m\?/0\d-[a-z]+\.md:\d+: \[[a-z-]+\] ")
want = [
    "[status] status `ap?[2Jpro?ved` not in",
    "[research-grammar] engine `web?]0;x??search` not in",
]
ok = (
    len(lines) == 2  # the bad status and the bad engine, nothing forged
    and all(line_re.match(l) for l in lines)
    and all(any(w in l for l in lines) for w in want)
    and not any(c in out for c in "\x1b\u202e\x07\r")
)
sys.exit(0 if ok else 1)
PY
rm -rf "${P:?}/$SAN"
# a 400-character value prints at 300 code points: 299 and an ellipsis
mutate long 01-requirements.md "status: approved" "status: $(printf 'v%.0s' $(seq 400))"
check tests/fixtures/plans/long
LONG_OUT="$OUT" python3 - <<'PY' && ok "a 400-character value is cut to 300 code points" || bad "sanitiser length cap (exit $RC)" "$OUT"
import os, sys
lines = os.environ["LONG_OUT"].split("\n")
msg = lines[0].split("] ", 1)[1] if len(lines) == 1 and "] " in lines[0] else ""
sys.exit(0 if len(msg) == 300 and msg.endswith("v…") and msg.startswith("status `vvv") else 1)
PY
rm -rf "$P/long"
# a 300-code-point message is left whole (the cap is "over 300")
SAN_PY="$(cd "$REPO/plugins/delivery/scripts" && python3 -I -c '
import importlib.util, sys
spec = importlib.util.spec_from_file_location("cp", "check-plan.py"); m = importlib.util.module_from_spec(spec); sys.modules["cp"] = m; spec.loader.exec_module(m)
ok = m.sanitise("a" * 300) == "a" * 300 and m.sanitise("a" * 301) == "a" * 299 + "…" \
     and m.sanitise("x\u2028y\u2029z\tq\u200dr") == "x?y?z?q?r" and m.sanitise("✅ 🔄 ⛔") == "✅ 🔄 ⛔"
print("ok" if ok else "no")')"
[ "$SAN_PY" = "ok" ] && ok "sanitise keeps 300, cuts 301, replaces Zl, Zp, tab and ZWJ, keeps emoji" || bad "sanitise unit cases" "$SAN_PY"

# ---- interface ---------------------------------------------------------------
check tests/fixtures/plans/does-not-exist
[ "$RC" -eq 1 ] && ok "missing folder exits 1" || bad "missing folder (exit $RC)" "$OUT"
check
[ "$RC" -eq 2 ] && ok "no arguments is a usage error" || bad "no arguments (exit $RC)" "$OUT"

# ---- --hook ------------------------------------------------------------------
mkdir -p "$R/docs/plans"
cp -R "$P/good" "$R/docs/plans/feature-a"
check --hook "$R/docs/plans/feature-a/05-implementation.md"
[ "$RC" -eq 0 ] && [ -z "$OUT" ] && ok "--hook silent on a passing plan" || bad "--hook on pass (exit $RC)" "$OUT"
check --hook "$R/README.md"
[ "$RC" -eq 0 ] && [ -z "$OUT" ] && ok "--hook silent on a path outside docs/plans/" || bad "--hook unrelated (exit $RC)" "$OUT"
check --hook "$R/docs/plans/README.md"
[ "$RC" -eq 0 ] && [ -z "$OUT" ] && ok "--hook silent on a file directly in docs/plans/" || bad "--hook plans README (exit $RC)" "$OUT"
cp -R "$P/bad-status" "$R/docs/plans/feature-b"
stdout="$(cd "$R" && "${RUN[@]}" --hook "$R/docs/plans/feature-b/04-review.md" 2>"$WORK/stderr")"; RC=$?
if [ "$RC" -eq 2 ] && [ -z "$stdout" ] && grep -q -F '[status]' "$WORK/stderr"; then ok "--hook prints the failed rule to stderr, exit 2"
else bad "--hook on failure (exit $RC)" "$stdout$(cat "$WORK/stderr")"; fi

# ---- --all -------------------------------------------------------------------
expect_only "--all fails when one folder fails" status --all
rm -rf "$R/docs/plans/feature-b"
check --all
[ "$RC" -eq 0 ] && [ "$(printf %s "$OUT" | grep -cvE '^checked [0-9]+ documents in [0-9]+ plan folder\(s\): clean$')" -eq 0 ] && printf %s "$OUT" | grep -qE '^checked [0-9]+ documents' && ok "--all passes when every folder passes" || bad "--all on pass (exit $RC)" "$OUT"
mkdir -p "$WORK/empty/.delivery"
OUT="$(cd "$WORK/empty" && "${RUN[@]}" --all 2>&1)"; RC=$?
[ "$RC" -eq 1 ] && ok "--all with no docs/plans/ exits 1" || bad "--all without docs/plans (exit $RC)" "$OUT"

# ---- exactly one T-nn commit per [x], in a real repository ----------------------
G="$WORK/gitrepo"
mkdir -p "$G/docs/plans" "$G/src"
cp -R "$P/good" "$G/docs/plans/feat"
gitc() { git -C "$G" -c user.name=fixture -c user.email=fixture@example.invalid \
             -c commit.gpgsign=false -c core.hooksPath=/dev/null "$@" >/dev/null 2>&1; }
gitc init -q
gitc add docs
gitc commit -q -m "Plan"
gcheck() { OUT="$(cd "$G" && "${RUN[@]}" "$@" 2>&1)"; RC=$?; }
gcheck docs/plans/feat
if [ "$RC" -eq 1 ] && [ "$(printf '%s\n' "$OUT" | grep -c -F '[commit]')" -eq 2 ]; then ok "[x] tasks with no T-nn commit fail"; else bad "zero commits (exit $RC)" "$OUT"; fi
gcheck --hook "$G/docs/plans/feat/05-implementation.md"
[ "$RC" -eq 0 ] && [ -z "$OUT" ] && ok "--hook skips the commit rule (the edit precedes its commit)" || bad "--hook commit rule (exit $RC)" "$OUT"
echo a >"$G/src/a.py"; gitc add src/a.py; gitc commit -q -m "T-01: Build the thing"
echo b >"$G/src/b.py"; gitc add src/b.py; gitc commit -q -m "T-02: Build the other thing"
gcheck docs/plans/feat
[ "$RC" -eq 0 ] && [ "$(printf %s "$OUT" | grep -cvE '^checked [0-9]+ documents in [0-9]+ plan folder\(s\): clean$')" -eq 0 ] && printf %s "$OUT" | grep -qE '^checked [0-9]+ documents' && ok "one T-nn commit per [x] task passes" || bad "one commit each (exit $RC)" "$OUT"
echo a2 >"$G/src/a.py"; gitc commit -q -am "T-01: Build the thing, again"
gcheck docs/plans/feat
expect_git_only() { [ "$RC" -eq 1 ] && printf '%s' "$OUT" | grep -q -F '[commit]' && [ -z "$(printf '%s\n' "$OUT" | grep -v -F '[commit]' | grep -v '^$')" ]; }
expect_git_only && ok "two T-01 commits fail" || bad "two commits (exit $RC)" "$OUT"

# A verification-only task changes none of its declared files; its commit carries
# only run-verify's evidence log. That is still its one commit.
V="$WORK/gitrepo-verify"
mkdir -p "$V/docs/plans" "$V/src"
cp -R "$P/good" "$V/docs/plans/feat"
mv "$V/docs/plans/feat/evidence/T-01.log" "$WORK/T-01.log.aside"   # T-01's own commit must introduce it
vgit() { git -C "$V" -c user.name=fixture -c user.email=fixture@example.invalid \
             -c commit.gpgsign=false -c core.hooksPath=/dev/null "$@" >/dev/null 2>&1; }
vcheck() { OUT="$(cd "$V" && "${RUN[@]}" "$@" 2>&1)"; RC=$?; }
vgit init -q; vgit add docs; vgit commit -q -m "Plan"
echo b >"$V/src/b.py"; vgit add src/b.py; vgit commit -q -m "T-02: Build the other thing"
mv "$WORK/T-01.log.aside" "$V/docs/plans/feat/evidence/T-01.log"
vgit add docs/plans/feat/evidence/T-01.log; vgit commit -q -m "T-01: Prove it on the other interpreter"
vcheck docs/plans/feat
if printf '%s\n' "$OUT" | grep -F '[commit]' | grep -qF 'T-01'; then bad "a verification-only task (commit touching only its evidence log) was rejected" "$OUT"; else ok "a verification-only task's evidence-only commit counts as its commit"; fi
printf 'more\n' >>"$V/docs/plans/feat/evidence/T-01.log"
vgit add -A; vgit commit -q -m "T-01: and again"
vcheck docs/plans/feat
printf '%s\n' "$OUT" | grep -F '[commit]' | grep -qF 'T-01' && ok "a second T-01 commit touching its evidence log still fails" || bad "second evidence-log commit not caught" "$OUT"

echo
echo "$PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
