#!/usr/bin/env bash
#
# Tests for plugins/delivery/scripts/run-verify (T-04), against a throwaway git
# repo with a plan and fake runners. Never touches the real plan.
#
#     bash scripts/test-run-verify.sh          # COVER=1 to measure coverage
#
set -uo pipefail
REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
RV="$REPO/plugins/delivery/scripts/run-verify"
CP="$REPO/plugins/delivery/scripts/check-plan.py"
W="$(mktemp -d /tmp/devagent-rv.XXXXXX)"
trap 'rm -rf "$W"' EXIT

if [ -n "${COVER:-}" ]; then
  export RV_PREFIX="uv run -q --no-project --with coverage==7.16.2 python -m coverage run --branch -p --data-file=$W/.cov"
fi

W="$W" RV="$RV" CP="$CP" python3 - <<'PY'
import hashlib, json, os, re, subprocess, sys, time
from pathlib import Path
W, RV, CP = Path(os.environ["W"]), os.environ["RV"], os.environ["CP"]
PREFIX = os.environ.get("RV_PREFIX", "").split() or [sys.executable]
passed = failed = 0
def check(name, ok, detail=""):
    global passed, failed
    if ok: passed += 1
    else:
        failed += 1; print(f"  FAIL {name} {str(detail)[:300]}")

repo = W / "repo"; plan_dir = repo / "docs" / "plans" / "f"
plan_dir.mkdir(parents=True)
subprocess.run(["git", "init", "-q", str(repo)], check=True)
(repo / "tool.py").write_text('''import os, sys, time
m = sys.argv[1]
if m == "pass": print("12 passed, 0 failed")
elif m == "fail": print("3 passed, 1 failed"); sys.exit(1)
elif m == "zero": print("0 passed, 0 failed")
elif m == "nocount": print("all good")
elif m == "hang": time.sleep(30)
elif m == "env":
    leaked = sorted(k for k in os.environ if k.startswith("AWS_") and k not in ("AWS_CONFIG_FILE", "AWS_SHARED_CREDENTIALS_FILE"))
    leaked += [k for k in ("GH_TOKEN", "GITHUB_TOKEN") if k in os.environ]
    print("LEAKED=" + ",".join(leaked)); print("CFG=" + os.environ.get("AWS_CONFIG_FILE", "")); print("5 passed")
elif m == "sentinel": open("SENTINEL", "w").write("ran"); print("1 passed")
elif m == "paths": print("at " + os.getcwd() + "/tool.py and " + os.path.expanduser("~") + "/.cache/x"); print("2 passed")
''')
TASKS = {
    "T-01": ("python3 tool.py pass", "5m"), "T-02": ("python3 tool.py fail", "5m"),
    "T-03": ("python3 tool.py zero", "5m"), "T-04": ("python3 tool.py nocount", "5m"),
    "T-05": ("python3 tool.py sentinel", "5m"), "T-06": ("python3 tool.py pass ; touch PWNED", "5m"),
    "T-07": ("python3 tool.py hang", "1s"), "T-08": ("python3 tool.py env", "5m"),
    "T-09": ("python3 tool.py paths", "5m"),
}
allowed = [c for t, (c, _) in TASKS.items() if t not in ("T-05", "T-06")]
fm = "---\nformat: delivery-plan/1\nfeature: f\nstep: 05-implementation\nstatus: approved\ndate: 2026-10-14\nreads: none\ngenerator: delivery@test\nbranch: main\nbase: 0000000\nverify_allowed:\n" + "".join(f"  - {c}\n" for c in allowed) + "---\n\n# Plan\n\n"
body = "".join(f"### {t} [ ] Task {t}\n- depends: none\n- files: tool.py\n- acceptance: x\n- test acceptance: y\n- verify: `{c}`\n- timeout: {to}\n\n" for t, (c, to) in TASKS.items())
plan = plan_dir / "05-implementation.md"; plan.write_text(fm + body)
original = plan.read_text()

def rv(tid, *extra, env=None):
    e = dict(os.environ, **(env or {}))
    return subprocess.run([*PREFIX, RV, str(plan_dir), tid, *extra], capture_output=True, text=True, env=e, timeout=60)

RUN_VERIFY = re.compile(r"^- evidence: (run-verify · exit 0 · tests (\d+) · \S+ · log (evidence/T-\d+\.log) sha256:([0-9a-f]{64}) · \d{4}-\d{2}-\d{2})$", re.M)

# 1. pass -> evidence line in the checker's exact format, log hash matches, --write records it
p = rv("T-01", "--write")
m = RUN_VERIFY.search(p.stdout)
check("pass exits 0", p.returncode == 0, p.stderr)
check("evidence line in check-plan's format", bool(m), p.stdout[-300:])
if m:
    log = plan_dir / m.group(3)
    check("tests counted", m.group(2) == "12", m.group(2))
    check("log exists and matches its sha256", log.is_file() and hashlib.sha256(log.read_bytes()).hexdigest() == m.group(4))
    check("--write recorded the line in the task block", m.group(1) in plan.read_text())
    # Tick it and the real checker must accept the evidence (commit rule needs a repo commit).
    t = plan.read_text().replace("### T-01 [ ] Task T-01", "### T-01 [x] Task T-01")
    plan.write_text(t)
    subprocess.run(["git", "-C", str(repo), "add", "-A"], check=True)
    subprocess.run(["git", "-C", str(repo), "-c", "user.email=t@t", "-c", "user.name=t", "commit", "-qm", "T-01: Task T-01"], check=True)
    c = subprocess.run([sys.executable, CP, str(plan_dir)], capture_output=True, text=True)
    ev_fail = [l for l in c.stdout.splitlines() if "T-01" in l and ("evidence" in l)]
    check("check-plan accepts run-verify's evidence", not ev_fail, c.stdout[-400:])
    plan.write_text(t.replace("### T-01 [x]", "### T-01 [ ]"))
before = plan.read_text()

# 2. failing command -> its exit code, no evidence written
p = rv("T-02", "--write")
check("failing command returns its exit code", p.returncode == 1, p.returncode)
check("failing command writes no evidence", plan.read_text() == before and "- evidence:" not in p.stdout)
# 3. zero tests -> exit 3
p = rv("T-03", "--write")
check("zero tests is a failure (exit 3)", p.returncode == 3 and "zero tests" in p.stderr, (p.returncode, p.stderr))
check("zero tests writes no evidence", plan.read_text() == before)
# 4. no count -> exit 3
p = rv("T-04")
check("no test count is a failure (exit 3)", p.returncode == 3 and "no test count" in p.stderr, (p.returncode, p.stderr))
# 5. off the allowlist -> refused before running
s = repo / "SENTINEL"
p = rv("T-05")
check("off-allowlist command refused (exit 2)", p.returncode == 2 and "verify_allowed" in p.stderr, p.stderr)
check("off-allowlist command never ran", not s.exists())
# 6. shell operator -> refused, nothing ran
p = rv("T-06")
check("shell operator refused (exit 2)", p.returncode == 2 and "shell operator" in p.stderr, p.stderr)
check("operator payload never ran", not (repo / "PWNED").exists())
# 7. hang -> killed at the timeout
t0 = time.monotonic(); p = rv("T-07"); dt = time.monotonic() - t0
check("hang killed at timeout (exit 124)", p.returncode == 124, p.returncode)
check("kill happened near the 1s timeout", dt < 15, dt)
# 8. credentials stripped in the child
p = rv("T-08", env={"AWS_PROFILE": "admin-profile", "AWS_ACCESS_KEY_ID": "AKIAFAKEFAKEFAKEFAKE", "AWS_SESSION_TOKEN": "x", "GH_TOKEN": "ghp_fake", "GITHUB_TOKEN": "y"})
check("no AWS_* or GitHub token reaches the command", "LEAKED=\n" in p.stdout or re.search(r"^LEAKED=$", p.stdout, re.M), p.stdout)
check("AWS config pointed at /dev/null", "CFG=/dev/null" in p.stdout, p.stdout)
# 8b. evidence carries no username or machine path
p = rv("T-09")
log = (plan_dir / "evidence" / "T-09.log").read_text()
home = os.path.expanduser("~")
check("paths: run passes", p.returncode == 0, p.stderr)
check("paths: repo root written as <repo>", "at <repo>/tool.py" in log, log)
check("paths: home written as ~", "~/.cache/x" in log, log)
check("paths: no home directory or repo path left", home not in log and str(repo) not in log, log)
m9 = RUN_VERIFY.search(p.stdout)
check("paths: the sha256 is of the scrubbed log", bool(m9) and hashlib.sha256((plan_dir / m9.group(3)).read_bytes()).hexdigest() == m9.group(4))
# 9. usage errors
p = subprocess.run([*PREFIX, RV, str(plan_dir)], capture_output=True, text=True)
check("missing task id -> exit 2", p.returncode == 2)
p = rv("T-99")
check("unknown task -> exit 2", p.returncode == 2 and "not found" in p.stderr, p.stderr)
p = subprocess.run([*PREFIX, RV, str(W / "nope"), "T-01"], capture_output=True, text=True)
check("missing plan -> exit 2", p.returncode == 2)

print(f"{passed} passed, {failed} failed")
sys.exit(1 if failed else 0)
PY
rc=$?
if [ -n "${COVER:-}" ]; then
  (cd "$W" && uv run -q --no-project --with coverage==7.16.2 python -m coverage combine -q --data-file="$W/.cov" "$W"/.cov.* >/dev/null 2>&1
   uv run -q --no-project --with coverage==7.16.2 python -m coverage report --data-file="$W/.cov" --include='*run-verify' 2>&1 | tail -2)
fi
exit $rc
