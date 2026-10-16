#!/usr/bin/env bash
#
# Tests for the build protocol scripts (T-11): plugins/delivery/scripts/build-*.
# Every scenario runs in a throwaway git repository under /tmp, built from
# tests/fixtures/build/. Never touches this repository's own plans or branches.
#
# A `git` shim first on PATH records every git invocation the scripts make and
# refuses `push`, so "never pushes" is observed, not assumed.
#
#     bash scripts/test-build-protocol.sh      # COVER=1 to measure coverage
#
set -uo pipefail
REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
W="$(mktemp -d /tmp/devagent-build.XXXXXX)"
trap 'rm -rf "$W"' EXIT

if [ -n "${COVER:-}" ]; then
  export BP_PREFIX="uv run -q --no-project --with coverage==7.16.2 python -m coverage run --branch -p --data-file=$W/.cov"
fi

W="$W" REPO="$REPO" python3 - <<'PY'
import atexit, os, re, shutil, subprocess, sys, time
from pathlib import Path

W, REPO = Path(os.environ["W"]), Path(os.environ["REPO"])
S = REPO / "plugins" / "delivery" / "scripts"
FIX = REPO / "tests" / "fixtures" / "build"
PREFIX = os.environ.get("BP_PREFIX", "").split() or [sys.executable]
REAL_GIT = shutil.which("git")
passed = failed = 0


def check(name, ok, detail=""):
    global passed, failed
    if ok:
        passed += 1
    else:
        failed += 1
        print(f"  FAIL {name} :: {str(detail)[-600:]}")


# -- the git shim: logs every call, refuses push -----------------------------
shim = W / "shim"
shim.mkdir()
GITLOG = W / "git-calls.log"
(shim / "git").write_text(f"""#!/bin/bash
printf '%s\\n' "$*" >> "{GITLOG}"
for a in "$@"; do
  if [ "$a" = "push" ]; then echo "PUSH ATTEMPTED: $*" >> "{GITLOG}.push"; exit 99; fi
done
exec "{REAL_GIT}" "$@"
""")
(shim / "git").chmod(0o755)
ENV = dict(os.environ, PATH=f"{shim}:{os.environ['PATH']}", GIT_CONFIG_GLOBAL=os.devnull,
           GIT_CONFIG_NOSYSTEM="1", DEVAGENT_GUARD_MODE="enforce")
for k in ("GIT_DIR", "GIT_WORK_TREE", "GIT_INDEX_FILE"):
    ENV.pop(k, None)

LIVE = subprocess.Popen(["sleep", "600"], stdin=subprocess.DEVNULL,   # a live process to hold locks
                        stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
atexit.register(LIVE.kill)
dead = subprocess.Popen(["true"]); dead.wait()
DEAD_PID = dead.pid                              # a process that has exited
SESSION = "test-session"


def g(repo, *args, check=True):
    r = subprocess.run(["git", "-C", str(repo), *args], capture_output=True, text=True, env=ENV)
    if check and r.returncode != 0:
        raise RuntimeError(f"git {args}: {r.stderr}")
    return r.stdout.strip()


def run(script, *args, env=None):
    e = dict(ENV, **(env or {}))
    p = subprocess.run([*PREFIX, str(S / f"build-{script}"), *map(str, args)],
                       capture_output=True, text=True, env=e, timeout=300)
    p.out = p.stdout + p.stderr
    return p


counter = 0


def mkrepo(plan_fixture=FIX / "05-implementation.md", feature="f", gitignore=True):
    """A fresh repo: seed commit (runner, .gitignore), then the plan with base = seed."""
    global counter
    counter += 1
    repo = W / f"repo{counter}"
    repo.mkdir()
    g(repo, "init", "-q", "-b", "main")
    g(repo, "config", "user.email", "builder@test")
    g(repo, "config", "user.name", "Test Builder")
    shutil.copy(FIX / "check.py", repo / "check.py")
    (repo / "src").mkdir()
    (repo / "src" / "shared.txt").write_text("original\n")
    if gitignore:
        (repo / ".gitignore").write_text(".playwright-mcp/\n")
    g(repo, "add", "-A")
    g(repo, "commit", "-qm", "seed")
    base = g(repo, "rev-parse", "HEAD")
    fdir = repo / "docs" / "plans" / feature
    fdir.mkdir(parents=True)
    (fdir / "05-implementation.md").write_text(plan_fixture.read_text().replace("BASE_SHA", base))
    g(repo, "add", "-A")
    g(repo, "commit", "-qm", "plan")
    return repo, fdir


def plan_of(fdir):
    return (fdir / "05-implementation.md").read_text()


def state(fdir, tid):
    m = re.search(rf"^### {tid} \[(.)\]", plan_of(fdir), re.M)
    return m.group(1) if m else None


def block_of(fdir, tid):
    text = plan_of(fdir)
    m = re.search(rf"^### {tid} \[.\].*?(?=^### |\Z)", text, re.M | re.S)
    return m.group(0) if m else ""


def start(fdir, approve=True):
    """Lock held by a live process, verify set approved."""
    a = run("lock", "acquire", fdir, "--pid", LIVE.pid, "--session", SESSION)
    p = run("preflight", fdir, *(["--approve"] if approve else []))
    return a, p


def build(fdir, tid, files, retry=False, commit=True):
    """A scripted builder: claim, write files in the worktree, one WIP commit."""
    p = run("claim", fdir, tid, *(["--retry"] if retry else []))
    m = re.search(r"worktree (\S+)$", p.stdout.strip(), re.M)
    if not m:
        raise RuntimeError(f"claim {tid} failed: {p.out}")
    wt = Path(m.group(1))
    for rel, content in files.items():
        f = wt / rel
        f.parent.mkdir(parents=True, exist_ok=True)
        f.write_text(content)
    if commit:
        g(wt, "add", "-f", *files)
        g(wt, "commit", "-qm", f"WIP {tid}")
    return wt


def clean_except_plan(repo, fdir):
    rel = (fdir / "05-implementation.md").relative_to(repo).as_posix()
    raw = subprocess.run(["git", "-C", str(repo), "status", "--porcelain"],
                         capture_output=True, text=True, env=ENV).stdout
    return [l for l in raw.splitlines() if l[3:] != rel]


# ============================================================================
# 1. Lock: a second build is refused while the lock is live
repo, fdir = mkrepo()
lock = repo / ".git" / "delivery-build.lock"
p = run("lock", "status", fdir)
check("status with no lock says none", p.returncode == 0 and "lock: none" in p.stdout, p.out)
p = run("lock", "acquire", fdir, "--pid", LIVE.pid, "--session", SESSION)
check("acquire succeeds", p.returncode == 0 and lock.is_file(), p.out)
check("lock file is mode 600", lock.is_file() and (lock.stat().st_mode & 0o777) == 0o600)
check("lock records pid, session, start", all(k in lock.read_text() for k in (str(LIVE.pid), SESSION, "started")))
p = run("lock", "acquire", fdir, "--pid", os.getpid(), "--session", "second")
check("second build refused while the lock is live (exit 1)", p.returncode == 1 and "another build" in p.out, p.out)
p = run("lock", "takeover", fdir, "--pid", os.getpid(), "--session", "second")
check("takeover of a live lock refused", p.returncode == 1 and "live" in p.out, p.out)
p = run("lock", "status", fdir)
check("status names the live holder", "live" in p.stdout and SESSION in p.stdout, p.out)
p = run("lock", "release", fdir, "--pid", os.getpid(), "--session", "second")
check("another session cannot release the lock", p.returncode == 1 and lock.exists(), p.out)
p = run("lock", "release", fdir, "--pid", LIVE.pid, "--session", SESSION)
check("holder releases the lock", p.returncode == 0 and not lock.exists(), p.out)
p = run("lock", "release", fdir, "--session", SESSION)
check("release with no lock is a no-op", p.returncode == 0 and "none" in p.stdout, p.out)
p = run("claim", fdir, "T-01")
check("claim without the lock is refused", p.returncode == 2 and "lock" in p.out, p.out)

# 2. A stale lock (dead PID) needs explicit takeover
p = run("lock", "acquire", fdir, "--pid", DEAD_PID, "--session", "killed")
p = run("lock", "acquire", fdir, "--pid", LIVE.pid, "--session", SESSION)
check("stale lock refuses plain acquire", p.returncode == 1 and "stale" in p.out and "takeover" in p.out, p.out)
p = run("preflight", fdir)
check("stale lock refuses preflight", p.returncode == 2 and "stale" in p.out, p.out)
p = run("lock", "status", fdir)
check("status reports the lock stale", "stale" in p.stdout, p.out)
p = run("lock", "takeover", fdir, "--pid", LIVE.pid, "--session", SESSION)
check("explicit takeover of a stale lock succeeds", p.returncode == 0 and str(LIVE.pid) in lock.read_text(), p.out)
lock.write_text("not json")
p = run("lock", "status", fdir)
check("a corrupt lock reads as stale", "stale" in p.stdout, p.out)
lock.unlink()

# 3. Preflight: branch and base
repo, fdir = mkrepo()
run("lock", "acquire", fdir, "--pid", LIVE.pid, "--session", SESSION)
p = run("preflight", fdir)
check("first preflight asks for verify-set approval (exit 4)", p.returncode == 4 and "NOT APPROVED" in p.stdout, p.out)
check("preflight lists the distinct verify commands", "python3 check.py src/a.txt" in p.stdout and p.stdout.count("python3 check.py src/a.txt") == 1, p.out)
p = run("preflight", fdir, "--approve")
check("preflight with operator approval passes", p.returncode == 0 and "approved" in p.stdout, p.out)
p = run("preflight", fdir)
check("approved, unchanged verify set passes without asking", p.returncode == 0 and "unchanged" in p.stdout, p.out)
text = plan_of(fdir)
(fdir / "05-implementation.md").write_text(text.replace("  - python3 check.py src/p.txt\n", "  - python3 check.py src/p.txt\n  - python3 check.py src/zz.txt\n"))
p = run("preflight", fdir)
check("a changed verify_allowed needs approval again", p.returncode == 4, p.out)
(fdir / "05-implementation.md").write_text(text)
g(repo, "checkout", "-q", "-b", "side")
p = run("preflight", fdir)
check("HEAD on the wrong branch is refused", p.returncode == 2 and "branch" in p.out, p.out)
g(repo, "checkout", "-q", "main")
# diverged base: rewrite base to a commit on an unrelated side branch
g(repo, "checkout", "-q", "-b", "elsewhere", "HEAD~1")
(repo / "other.txt").write_text("x\n"); g(repo, "add", "-A"); g(repo, "commit", "-qm", "side work")
side = g(repo, "rev-parse", "HEAD")
g(repo, "checkout", "-q", "main")
(fdir / "05-implementation.md").write_text(re.sub(r"^base: \S+$", f"base: {side}", text, flags=re.M))
g(repo, "commit", "-qam", "plan: base moved")
p = run("preflight", fdir)
check("a diverged base is refused", p.returncode == 2 and "diverged" in p.out, p.out)
(fdir / "05-implementation.md").write_text(re.sub(r"^base: \S+$", "base: 0123456789abcdef", text, flags=re.M))
g(repo, "commit", "-qam", "plan: bogus base")
p = run("preflight", fdir)
check("a base that is not a commit is refused", p.returncode == 2 and "not a commit" in p.out, p.out)
(fdir / "05-implementation.md").write_text(text)
g(repo, "commit", "-qam", "plan: restored")
(repo / "check.py").write_text("# edited\n")
p = run("preflight", fdir)
check("uncommitted tracked changes are refused", p.returncode == 2 and "uncommitted" in p.out, p.out)
g(repo, "checkout", "--", "check.py")
(fdir / "05-implementation.md").write_text(text.replace("- verify: `python3 check.py src/b.txt`", "- verify: `python3 check.py src/b.txt; touch PWNED`"))
g(repo, "commit", "-qam", "plan: malformed")
p = run("preflight", fdir, "--approve")
check("a plan check-plan.py rejects is refused", p.returncode == 2 and "check-plan" in p.out, p.out)

# 4. Happy path: claim, build, integrate -> one commit with code and tick
repo, fdir = mkrepo()
start(fdir)
wt = build(fdir, "T-01", {"src/a.txt": "hello\n"})
check("claim marks [~] with owner, session, started, worktree",
      state(fdir, "T-01") == "~" and re.search(r"- owner: builder@test · session: test-session · started: \S+ · worktree: \S+", block_of(fdir, "T-01")), block_of(fdir, "T-01"))
check("claim made branch delivery/f/T-01", g(repo, "rev-parse", "--abbrev-ref", "HEAD", check=False) == "main" and g(wt, "rev-parse", "--abbrev-ref", "HEAD") == "delivery/f/T-01")
p = run("status", fdir)
check("status shows the [~] task, its worktree and the lock", "[~] in progress" in p.stdout and "delivery/f/T-01" in p.stdout and "live" in p.stdout, p.out)
before = g(repo, "rev-parse", "HEAD")
p = run("integrate", fdir, "T-01")
check("integrate passes (exit 0)", p.returncode == 0, p.out)
check("exactly one new commit on main", g(repo, "rev-list", "--count", f"{before}..HEAD") == "1")
msg = g(repo, "log", "-1", "--format=%B")
check("commit message is `T-01: <title>`", msg.splitlines()[0] == "T-01: Happy path", msg)
check("commit carries the Assisted-by trailer", "Assisted-by:" in g(repo, "log", "-1", "--format=%(trailers)"), msg)
names = g(repo, "show", "--name-only", "--format=", "HEAD").splitlines()
check("commit holds code, the tick and the evidence log",
      set(names) == {"src/a.txt", "docs/plans/f/05-implementation.md", "docs/plans/f/evidence/T-01.log"}, names)
committed = g(repo, "show", "HEAD:docs/plans/f/05-implementation.md")
check("committed plan has T-01 [x] with run-verify evidence and no owner",
      re.search(r"### T-01 \[x\] Happy path\n(?:(?!### ).)*- evidence: run-verify · exit 0 · tests 1 ", committed, re.S)
      and "owner" not in re.search(r"### T-01.*?(?=### T-02)", committed, re.S).group(0), committed[:1500])
check("worktree removed", not wt.exists() and "delivery/f/T-01" not in g(repo, "worktree", "list"))
check("task branch deleted after integration", g(repo, "branch", "--list", "delivery/f/T-01") == "")
check("main tree clean after integration", clean_except_plan(repo, fdir) == [] and g(repo, "status", "--porcelain") == "", g(repo, "status", "--porcelain"))
c = subprocess.run([sys.executable, str(S / "check-plan.py"), str(fdir)], capture_output=True, text=True, env=ENV)
check("check-plan.py accepts the integrated plan (evidence hash, one T-01 commit)", c.returncode == 0, c.stdout)
p = run("integrate", fdir, "T-01")
check("integrating an [x] task again is refused", p.returncode == 2 and "already" in p.out, p.out)
p = run("status", fdir)
check("status shows the done task and last integrated commit", "[x] done" in p.stdout and "last integrated:" in p.stdout and "T-01: Happy path" in p.stdout, p.out)

# 5. Scope: a path outside `files` -> [!] scope, main untouched
wt = build(fdir, "T-02", {"src/b.txt": "b\n", "src/sneaky.txt": "x\n"})
before = g(repo, "rev-parse", "HEAD")
p = run("integrate", fdir, "T-02")
check("out-of-files path -> [!] scope (exit 3)", p.returncode == 3 and state(fdir, "T-02") == "!" and "src/sneaky.txt is outside" in block_of(fdir, "T-02"), p.out + block_of(fdir, "T-02"))
check("scope [!] keeps the branch and names it", g(repo, "branch", "--list", "delivery/f/T-02") != "" and "branch delivery/f/T-02 kept" in block_of(fdir, "T-02"))
check("scope [!] proposes a tier escalation", "moving up a tier" in block_of(fdir, "T-02"))
check("scope failure leaves HEAD unchanged", g(repo, "rev-parse", "HEAD") == before)
p = run("ready", fdir)
check("stop rule: build-ready dispatches nothing after a [!] (exit 3)", p.returncode == 3 and "dispatch nothing" in p.out, p.out)
p = run("claim", fdir, "T-03")
check("stop rule: build-claim refuses a new task after a [!]", p.returncode == 3 and "stop rule" in p.out, p.out)
c = subprocess.run([sys.executable, str(S / "check-plan.py"), str(fdir)], capture_output=True, text=True, env=ENV)
check("the [!] the scripts write passes check-plan (has a reason)", c.returncode == 0, c.stdout)

# 6. .github/ needs the operator even when listed in files; approval lets it in
repo, fdir = mkrepo()
start(fdir)
build(fdir, "T-03", {"src/c.txt": "c\n", ".github/workflows/ci.yml": "on: push\n"})
before = g(repo, "rev-parse", "HEAD")
p = run("integrate", fdir, "T-03")
check(".github/ change needs approval (exit 3)", p.returncode == 3 and "needs operator approval" in block_of(fdir, "T-03"), p.out)
check(".github/ refusal leaves HEAD unchanged", g(repo, "rev-parse", "HEAD") == before)
p = run("integrate", fdir, "T-03", "--approve-path", ".github/workflows/ci.yml")
check("with the operator's --approve-path it integrates", p.returncode == 0 and state(fdir, "T-03") == "x", p.out)
for path in ("pkg/.claude/settings.json", ".mcp.json", "sub/CLAUDE.md", ".husky/pre-commit", "infra/main.tf", "package.json", "uv.lock", "requirements-dev.txt", "app.csproj"):
    lib_check = subprocess.run([sys.executable, "-c", "import importlib.util,sys;s=importlib.util.spec_from_file_location('b',sys.argv[1]);m=sys.modules['b']=importlib.util.module_from_spec(s);s.loader.exec_module(m);print(m.needs_approval(sys.argv[2]) or 'none')", str(S / "build-lib.py"), path], capture_output=True, text=True)
    check(f"always-approval path {path}", lib_check.stdout.strip() != "none", lib_check.stdout)

# 7. Rebase conflict aborts, keeps the branch
repo, fdir = mkrepo()
start(fdir)
wt4 = build(fdir, "T-04", {"src/d.txt": "d\n", "src/shared.txt": "from T-04\n"})
wt5 = build(fdir, "T-05", {"src/e.txt": "e\n", "src/shared.txt": "from T-05\n"})
p = run("integrate", fdir, "T-04")
check("first of two conflicting tasks integrates", p.returncode == 0, p.out)
before = g(repo, "rev-parse", "HEAD")
tip = g(repo, "rev-parse", "delivery/f/T-05")
p = run("integrate", fdir, "T-05")
check("rebase conflict -> [!] conflict with T-04 (exit 3)", p.returncode == 3 and "conflict with T-04" in block_of(fdir, "T-05"), p.out + block_of(fdir, "T-05"))
check("conflict leaves HEAD unchanged", g(repo, "rev-parse", "HEAD") == before)
check("conflict keeps the branch at its original commit", g(repo, "rev-parse", "delivery/f/T-05") == tip)
check("conflict aborted the rebase (no rebase in progress)", "rebase in progress" not in g(wt5, "status") and g(wt5, "rev-parse", "HEAD") == tip)
check("main tree clean after the conflict", clean_except_plan(repo, fdir) == [], clean_except_plan(repo, fdir))

# 8. Failing verify leaves main untouched; two failures leave [!]
repo, fdir = mkrepo()
start(fdir)
build(fdir, "T-06", {"src/f.txt": "BAD\n"})
before = g(repo, "rev-parse", "HEAD")
p = run("integrate", fdir, "T-06")
check("failing verify exits 1", p.returncode == 1, p.out)
check("failing verify leaves HEAD unchanged", g(repo, "rev-parse", "HEAD") == before)
check("failing verify leaves the tree clean (nothing staged or written)", clean_except_plan(repo, fdir) == [] and g(repo, "diff", "--cached", "--name-only") == "" and not (repo / "src" / "f.txt").exists(), g(repo, "status", "--porcelain"))
b = block_of(fdir, "T-06")
check("first failure: [!] with reason, attempt 1 of 2 and the branch", state(fdir, "T-06") == "!" and "attempt 1 of 2" in b and "branch delivery/f/T-06 kept" in b and "- attempts: 1" in b, b)
p = run("claim", fdir, "T-06")
check("re-dispatch of a [!] task without --retry is refused", p.returncode == 2 and "--retry" in p.out, p.out)
build(fdir, "T-06", {"src/f.txt": "still BAD\n"}, retry=True)
check("retry kept the failed attempt's branch", g(repo, "branch", "--list", "delivery/f/T-06-attempt-1") != "")
p = run("integrate", fdir, "T-06")
b = block_of(fdir, "T-06")
check("second failure: still [!], attempts spent", p.returncode == 1 and state(fdir, "T-06") == "!" and "- attempts: 2" in b and "attempts spent" in b, p.out + b)
check("second failure leaves HEAD unchanged", g(repo, "rev-parse", "HEAD") == before)
p = run("claim", fdir, "T-06", "--retry")
check("after two failed attempts a third dispatch is refused (exit 3)", p.returncode == 3 and "stays [!]" in p.out, p.out)
p = run("integrate", fdir, "T-06")
check("after two failed attempts integrate is refused (exit 3)", p.returncode == 3, p.out)

# 9. Reconcile [~] left by a killed run
repo, fdir = mkrepo()
start(fdir)
wt7 = build(fdir, "T-07", {"src/g.txt": "half-written\n"}, commit=False)   # killed before its commit
wt8 = build(fdir, "T-08", {"src/h.txt": "h\n"})                            # killed after its commit
lock = repo / ".git" / "delivery-build.lock"
lock.write_text(lock.read_text().replace(str(LIVE.pid), str(DEAD_PID)))     # the session died
p = run("preflight", fdir)
check("restart: preflight refuses until the stale lock is taken over", p.returncode == 2 and "stale" in p.out, p.out)
run("lock", "takeover", fdir, "--pid", LIVE.pid, "--session", "new-session")
p = run("preflight", fdir)
check("reconcile passes (exit 0)", p.returncode == 0, p.out)
check("[~] with no commit is reset to [ ]", state(fdir, "T-07") == " " and "owner" not in block_of(fdir, "T-07"), block_of(fdir, "T-07"))
check("its worktree is removed and branch deleted", not wt7.exists() and g(repo, "branch", "--list", "delivery/f/T-07") == "")
check("[~] with a passing commit is integrated", state(fdir, "T-08") == "x" and g(repo, "log", "-1", "--format=%s") == "T-08: Killed after committing", p.out)
check("reconcile reports what it did", "reset to [ ]" in p.stdout and "T-08 integrated" in p.stdout, p.out)
wt = build(fdir, "T-07", {"src/g.txt": "g\n"})
check("a reset task can be claimed again", wt.exists() and state(fdir, "T-07") == "~")

# 10. Playwright output is never committed
repo, fdir = mkrepo(gitignore=False)
start(fdir)
check("preflight adds .playwright-mcp/ to .gitignore when missing", ".playwright-mcp/" in (repo / ".gitignore").read_text() and g(repo, "log", "-1", "--format=%s").startswith("delivery: ignore .playwright-mcp/"))
build(fdir, "T-01", {"src/a.txt": "a\n"})
shot = repo / ".playwright-mcp" / "page.png"
shot.parent.mkdir()
shot.write_bytes(b"\x89PNG fake")
g(repo, "add", "-f", ".playwright-mcp/page.png")
before = g(repo, "rev-parse", "HEAD")
p = run("integrate", fdir, "T-01")
check("a staged .playwright-mcp/ file is refused", p.returncode == 2 and "Playwright" in p.out, p.out)
check("refusal commits nothing", g(repo, "rev-parse", "HEAD") == before and ".playwright-mcp/page.png" not in g(repo, "ls-tree", "-r", "--name-only", "HEAD"))
g(repo, "rm", "-q", "--cached", ".playwright-mcp/page.png")
p = run("integrate", fdir, "T-01")
check("once unstaged, the task integrates", p.returncode == 0 and ".playwright-mcp" not in g(repo, "show", "--name-only", "--format=", "HEAD"), p.out)
build(fdir, "T-09", {"src/p.txt": "p\n", ".playwright-mcp/x.png": "png"})
p = run("integrate", fdir, "T-09", "--approve-path", ".playwright-mcp/x.png")
check("a branch carrying Playwright output is refused even if listed and approved", p.returncode == 3 and "Playwright output is never committed" in block_of(fdir, "T-09"), p.out)

# 11. build-ready: non-overlapping groups of at most 3; one task unless enforce
rrepo, rdir = mkrepo(FIX / "ready" / "05-implementation.md", feature="r")
p = run("ready", rdir)
picked = re.findall(r"^(T-\d+)\t", p.stdout, re.M)
check("enforce: at most 3 ready, non-overlapping tasks in ID order", picked == ["T-01", "T-05", "T-06"], p.out)
check("overlapping and later tasks are deferred, unmet depends excluded", "deferred: T-02, T-03, T-07" in p.stdout and "T-04" not in p.stdout, p.out)
p = run("ready", rdir, "--max", "2")
check("--max limits the group", re.findall(r"^(T-\d+)\t", p.stdout, re.M) == ["T-01", "T-05"], p.out)
p = run("ready", rdir, env={"DEVAGENT_GUARD_MODE": "warn"})
check("warn mode: attended, one task at a time", re.findall(r"^(T-\d+)\t", p.stdout, re.M) == ["T-01"] and "attended" in p.stdout, p.out)
p = run("ready", rdir, env={"DEVAGENT_GUARD_MODE": ""})
shipped = re.search(r'^MODE = "(\w+)"', (REPO / "plugins/devagent-standards/hooks/guard.py").read_text(), re.M).group(1)
check(f"no env: mode read from guard.py (shipped {shipped}) -> {'up to 3 tasks' if shipped == 'enforce' else 'one task'}",
      re.findall(r"^(T-\d+)\t", p.stdout, re.M) == (["T-01", "T-05", "T-06"] if shipped == "enforce" else ["T-01"]), p.out)
t = plan_of(rdir).replace("### T-01 [ ]", "### T-01 [x]").replace("### T-02 [ ]", "### T-02 [x]").replace("### T-03 [ ]", "### T-03 [x]").replace("### T-05 [ ]", "### T-05 [x]").replace("### T-06 [ ]", "### T-06 [x]").replace("### T-07 [ ]", "### T-07 [x]").replace("### T-04 [ ]", "### T-04 [x]")
(rdir / "05-implementation.md").write_text(t)
p = run("ready", rdir)
check("nothing ready says so", "no ready tasks" in p.stdout and p.returncode == 0, p.out)

# 12. Repo commit convention from docs/knowledge/conventions.md
repo, fdir = mkrepo()
(repo / "docs" / "knowledge").mkdir(parents=True)
(repo / "docs" / "knowledge" / "conventions.md").write_text("# Conventions\n\ncommit-format: `{id} - {title}`\n")
g(repo, "add", "-A"); g(repo, "commit", "-qm", "conventions")
start(fdir)
build(fdir, "T-01", {"src/a.txt": "a\n"})
p = run("integrate", fdir, "T-01")
check("repo commit convention is followed and noted", p.returncode == 0 and g(repo, "log", "-1", "--format=%s") == "T-01 - Happy path" and "conventions.md" in p.stdout, p.out)
(repo / "docs" / "knowledge" / "conventions.md").write_text("commit-format: feat: {title}\n")
g(repo, "add", "-A"); g(repo, "commit", "-qm", "conventions 2")
build(fdir, "T-02", {"src/b.txt": "b\n"})
p = run("integrate", fdir, "T-02")
check("a convention without a leading {id} is ignored with a note", p.returncode == 0 and g(repo, "log", "-1", "--format=%s") == "T-02: Strays outside its files" and "ignored" in p.stdout, p.out)

# 13. Usage and refusal edges
p = run("integrate", fdir, "T-10", "delivery/f/T-10")
check("integrate of a missing branch is refused", p.returncode == 2 and "no branch" in p.out, p.out)
p = run("integrate", fdir, "T-10", "--evil")
check("unknown option refused", p.returncode == 2, p.out)
p = run("integrate", fdir, "T-10", "-x;rm")
check("a non-plain branch name is refused", p.returncode == 2 and "plain branch" in p.out, p.out)
p = run("claim", fdir, "T-99")
check("unknown task refused", p.returncode == 2 and "not found" in p.out, p.out)
p = run("claim", fdir, "T-01")
check("claiming a done task refused", p.returncode == 2, p.out)
p = run("lock", "bogus", fdir)
check("lock usage error", p.returncode == 2 and "usage" in p.out, p.out)
p = run("status", W / "nope")
check("missing plan refused", p.returncode == 2 and "no 05" in p.out, p.out)
p = run("ready")
check("ready usage error", p.returncode == 2, p.out)
p = run("preflight")
check("preflight usage error", p.returncode == 2, p.out)
p = run("status")
check("status usage error", p.returncode == 2, p.out)
p = run("lock", "acquire", fdir, "--pid")
check("option without value refused", p.returncode == 2, p.out)

# 14. Never pushes
check("the shim saw the scripts call git", GITLOG.is_file() and "worktree add" in GITLOG.read_text())
check("no `git push` was ever issued", not Path(f"{GITLOG}.push").exists(),
      Path(f"{GITLOG}.push").read_text() if Path(f"{GITLOG}.push").exists() else "")
calls = GITLOG.read_text().splitlines()
check("no push subcommand in any recorded git call", not any(re.search(r"(^|\s)push(\s|$)", c) for c in calls))
src = "".join((S / n).read_text() for n in os.listdir(S) if n.startswith("build-"))
check("the build scripts contain no push or PR call", not re.search(r"""["']push["']|\bgh\s+pr\b|["']pr["']""", src))

LIVE.kill()
print(f"{passed} passed, {failed} failed")
sys.exit(1 if failed else 0)
PY
rc=$?
if [ -n "${COVER:-}" ]; then
  (cd "$W" && uv run -q --no-project --with coverage==7.16.2 python -m coverage combine -q --data-file="$W/.cov" "$W"/.cov.* >/dev/null 2>&1
   uv run -q --no-project --with coverage==7.16.2 python -m coverage report --data-file="$W/.cov" --include='*build-*' 2>&1 | tail -9)
fi
exit $rc
