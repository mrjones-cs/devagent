#!/usr/bin/env bash
#
# The whole-repository gate: every offline check, in sequence.
#
#     bash scripts/check-all.sh
#
# Runs check-skills.py, check-plan.py against examples/guard-report, and every
# scripts/test-*.sh except test-delivery-smoke.sh (which needs a signed-in
# Claude Code and costs money). Prints one line per suite with its exit code
# and seconds, then exactly:
#
#     total: <n> passed, <m> failed, <s>s
#
# where <n> and <m> count suites. run-verify takes the FIRST "<n> passed" in
# the output as the test count, so suite output is captured, never echoed
# before the total line; a failing suite's output is printed after it.
# Exits 1 if any suite fails, 2 on any argument.

set -uo pipefail

if [ "$#" -ne 0 ]; then
  echo "usage: bash scripts/check-all.sh   (takes no arguments)" >&2
  exit 2
fi

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$REPO" || exit 1

logdir="$(mktemp -d "${TMPDIR:-/tmp}/devagent-check-all.XXXXXX")"
trap 'rm -rf "$logdir"' EXIT

passed=0
failed=0
failures=()
start_all=$(date +%s)

run_suite() {
  local name="$1"; shift
  local log="$logdir/$((passed + failed)).log"
  local t0 t1 rc status
  t0=$(date +%s)
  "$@" </dev/null >"$log" 2>&1
  rc=$?
  t1=$(date +%s)
  if [ "$rc" -eq 0 ]; then
    status="ok  "
    passed=$((passed + 1))
  else
    status="FAIL"
    failed=$((failed + 1))
    failures+=("$name|$log")
  fi
  printf '%s %-38s exit %-3s %ss\n' "$status" "$name" "$rc" "$((t1 - t0))"
}

run_suite "check-skills.py" python3 scripts/check-skills.py
run_suite "check-plan.py examples/guard-report" \
  python3 plugins/delivery/scripts/check-plan.py examples/guard-report

for t in scripts/test-*.sh; do
  [ -e "$t" ] || continue
  [ "$(basename "$t")" = "test-delivery-smoke.sh" ] && continue
  run_suite "$(basename "$t")" bash "$t"
done

echo "total: ${passed} passed, ${failed} failed, $(( $(date +%s) - start_all ))s"

if [ "$failed" -ne 0 ]; then
  for f in "${failures[@]}"; do
    name="${f%%|*}"; log="${f#*|}"
    echo
    echo "--- ${name}: last 40 lines ---"
    tail -n 40 "$log"
  done
  exit 1
fi
exit 0
