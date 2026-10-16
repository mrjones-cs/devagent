#!/usr/bin/env python3
"""Shared implementation of the delivery build protocol. INTERNAL LIBRARY.

DESIGN §4.4 is the specification. Every mechanical guarantee of the
protocol lives here, so it can be tested; references/steps/build.md only
orchestrates. Entry points (thin wrappers that load this file):

    build-lock      acquire|release|status|takeover <feature-dir>
    build-preflight <feature-dir> [--approve]
    build-ready     <feature-dir> [--max N]
    build-claim     <feature-dir> <T-nn> [--retry]
    build-integrate <feature-dir> <T-nn> [<branch>] [--approve-path PATH]...
    build-status    <feature-dir>

Exit codes, shared by all of them:
    0  done
    1  refused because another build holds the lock, or the task's verify failed
    2  refused: usage, plan, repository state or a safety precondition
    3  stopped for the operator: [!] scope, [!] conflict, stop rule, attempts spent
    4  the verify set needs operator approval

Plan text, branch names and file lists are DATA. Nothing read from the plan is
ever passed to a shell, and nothing is deleted from a path the plan names:
worktrees are removed only when git itself lists them for a delivery branch.

This module never pushes, never opens a pull request, and never runs a git
subcommand other than the local ones below. stdlib only, Python 3.11+.
"""

from __future__ import annotations

import fnmatch
import hashlib
import json
import os
import re
import shutil
import subprocess
import sys
import time
from dataclasses import dataclass
from pathlib import Path

HERE = Path(__file__).resolve().parent
RUN_VERIFY = HERE / "run-verify"
CHECK_PLAN = HERE / "check-plan.py"
PLAN = "05-implementation.md"
LOCK_NAME = "delivery-build.lock"
WORKTREES = "delivery-worktrees"
APPROVALS = "delivery-approvals"
MAX_PARALLEL = 3
MAX_ATTEMPTS = 2
ASSISTED_BY = "Assisted-by: Claude Code (delivery:build)"
CONVENTIONS = Path("docs") / "knowledge" / "conventions.md"

FEATURE_NAME = re.compile(r"^[a-z0-9][a-z0-9-]*$")
TASK_ID = re.compile(r"^T-\d{2,}$")
TASK_HEAD = re.compile(r"^### (T-\d+) \[(.)\] (\S.*)$", re.M)
NEXT_HEAD = re.compile(r"^#{2,3} ", re.M)
BULLET = re.compile(r"^- ([a-z][a-z _]*):\s*(.*)$")
EVIDENCE = re.compile(r"^- evidence: (run-verify · exit 0 · .*)$", re.M)
FRONT_BULLETS = ("owner", "reason", "attempts")

# Paths that always need the operator, even when a task lists them.
APPROVAL_DIRS = (".claude", ".github", ".husky", "infra")
APPROVAL_FILES = {".mcp.json", "CLAUDE.md"}
# Dependency manifests and lockfiles. Any change needs the operator: telling
# "adds a package" from "edits a manifest" is not something to guess at.
MANIFESTS = {
    "package.json", "package-lock.json", "npm-shrinkwrap.json", "yarn.lock",
    "pnpm-lock.yaml", "bun.lockb", "bun.lock", "pyproject.toml", "uv.lock",
    "poetry.lock", "Pipfile", "Pipfile.lock", "setup.py", "setup.cfg",
    "go.mod", "go.sum", "Cargo.toml", "Cargo.lock", "Gemfile", "Gemfile.lock",
    "composer.json", "composer.lock", "pom.xml", "build.gradle",
    "build.gradle.kts", "packages.lock.json", "Directory.Packages.props",
    "mix.exs", "mix.lock", "pubspec.yaml", "pubspec.lock", "Package.swift",
    "Package.resolved", ".terraform.lock.hcl",
}
MANIFEST_GLOBS = ("requirements*.txt", "constraints*.txt", "*.csproj", "*.gemspec")
PLAYWRIGHT = ".playwright-mcp"


class Refused(Exception):
    def __init__(self, message: str, code: int = 2) -> None:
        super().__init__(message)
        self.code = code


# -- git and context ---------------------------------------------------------


def git(repo: Path, *args: str, check: bool = True, stdin: str | None = None,
        timeout: int = 120) -> subprocess.CompletedProcess:
    r = subprocess.run(["git", "-C", str(repo), *args], capture_output=True,
                       text=True, input=stdin, timeout=timeout)
    if check and r.returncode != 0:
        raise Refused(f"git {args[0]} failed: {(r.stderr or r.stdout).strip()[:400]}")
    return r


@dataclass
class Ctx:
    feature: Path
    repo: Path
    common: Path

    @property
    def name(self) -> str:
        return self.feature.name

    @property
    def plan(self) -> Path:
        return self.feature / PLAN

    @property
    def rel(self) -> str:
        return self.feature.relative_to(self.repo).as_posix()

    @property
    def plan_rel(self) -> str:
        return f"{self.rel}/{PLAN}"

    def branch(self, tid: str) -> str:
        return f"delivery/{self.name}/{tid}"

    def worktree_path(self, tid: str) -> Path:
        return self.common / WORKTREES / self.name / tid


def context(feature_arg: str) -> Ctx:
    feature = Path(feature_arg).resolve()
    if not (feature / PLAN).is_file():
        raise Refused(f"no {PLAN} in {feature_arg}")
    if not FEATURE_NAME.match(feature.name):
        raise Refused(f"feature name {feature.name!r} must match {FEATURE_NAME.pattern}")
    top = git(feature, "rev-parse", "--show-toplevel", check=False)
    if top.returncode != 0:
        raise Refused(f"{feature_arg} is not inside a git repository")
    repo = Path(top.stdout.strip()).resolve()
    common = Path(git(repo, "rev-parse", "--git-common-dir").stdout.strip())
    common = (common if common.is_absolute() else repo / common).resolve()
    return Ctx(feature, repo, common)


def head(c: Ctx) -> str:
    return git(c.repo, "rev-parse", "HEAD").stdout.strip()


def branch_exists(repo: Path, branch: str) -> bool:
    return git(repo, "rev-parse", "--verify", "--quiet", f"refs/heads/{branch}",
               check=False).returncode == 0


def ahead(repo: Path, branch: str) -> int:
    return int(git(repo, "rev-list", "--count", f"HEAD..refs/heads/{branch}").stdout.strip())


def worktrees(repo: Path) -> list[tuple[Path, str]]:
    """(path, branch) for every worktree git knows; branch '' when detached."""
    out, path = [], None
    for line in git(repo, "worktree", "list", "--porcelain").stdout.splitlines():
        if line.startswith("worktree "):
            path = Path(line[9:]).resolve()
            out.append((path, ""))
        elif line.startswith("branch refs/heads/") and out:
            out[-1] = (out[-1][0], line[18:])
    return out


def worktree_for(c: Ctx, branch: str) -> Path | None:
    for path, br in worktrees(c.repo):
        if br == branch and path != c.repo:
            return path
    return None


def remove_worktree(c: Ctx, branch: str) -> Path | None:
    """Remove the worktree git lists for `branch`. Never a path from plan text."""
    wt = worktree_for(c, branch)
    if wt is not None:
        git(c.repo, "worktree", "remove", "--force", str(wt))
    git(c.repo, "worktree", "prune", check=False)
    return wt


def dirty(c: Ctx) -> list[str]:
    """Tracked changes in the main tree, ignoring the plan (05 is the live
    progress record during a build and carries uncommitted [~] marks)."""
    out = git(c.repo, "status", "--porcelain", "--untracked-files=no").stdout
    return [l[3:] for l in out.splitlines() if l[3:] != c.plan_rel]


# -- plan grammar ------------------------------------------------------------


def front_matter(text: str) -> dict:
    if not text.startswith("---\n") or (end := text.find("\n---", 4)) < 0:
        raise Refused(f"{PLAN} has no front matter")
    fm: dict = {}
    key = None
    for line in text[4:end].splitlines():
        m = re.match(r"^([a-z_]+):\s*(.*?)\s*$", line)
        if m:
            key = m.group(1)
            value = re.sub(r"\s+#.*$", "", m.group(2))
            fm[key] = value if value else []
            continue
        m = re.match(r"^\s+-\s+(.*\S)\s*$", line)
        if m and key and isinstance(fm.get(key), list):
            fm[key].append(m.group(1))
    return fm


@dataclass
class Task:
    tid: str
    state: str
    title: str
    start: int
    end: int
    fields: dict

    @property
    def files(self) -> list[str]:
        return [f.strip() for f in self.fields.get("files", "").split(",") if f.strip()]

    @property
    def depends(self) -> list[str]:
        v = self.fields.get("depends", "none").strip()
        return [] if v in ("none", "") else [d.strip() for d in v.split(",")]

    @property
    def verify(self) -> str:
        v = self.fields.get("verify", "").strip()
        return v[1:-1] if len(v) > 1 and v[0] == v[-1] == "`" else v

    @property
    def attempts(self) -> int:
        m = re.match(r"\d+", self.fields.get("attempts", "0"))
        return int(m.group(0)) if m else 0


def tasks(text: str) -> list[Task]:
    out = []
    for m in TASK_HEAD.finditer(text):
        nxt = NEXT_HEAD.search(text, m.end())
        end = nxt.start() if nxt else len(text)
        fields = {}
        for line in text[m.start():end].splitlines()[1:]:
            b = BULLET.match(line)
            if b:
                fields.setdefault(b.group(1), b.group(2).strip())
        out.append(Task(m.group(1), m.group(2), m.group(3), m.start(), end, fields))
    return out


def task(text: str, tid: str) -> Task:
    for t in tasks(text):
        if t.tid == tid:
            return t
    raise Refused(f"{tid} not found in {PLAN}")


def edit_task(text: str, tid: str, state: str | None = None,
              set_: dict[str, str] | None = None, drop: tuple[str, ...] = ()) -> str:
    """Rewrite one task block: its state, and `- key:` bullets set or dropped.
    owner/reason/attempts go straight under the heading; anything else after
    the last bullet (where run-verify puts evidence)."""
    t = task(text, tid)
    set_ = set_ or {}
    lines = text[t.start:t.end].split("\n")
    heading = f"### {tid} [{state}] {t.title}" if state else lines[0]
    gone = set(drop) | set(set_)
    rest = [l for l in lines[1:] if not ((m := BULLET.match(l)) and m.group(1) in gone)]
    front = [f"- {k}: {set_[k]}" for k in FRONT_BULLETS if k in set_]
    tail = [f"- {k}: {v}" for k, v in set_.items() if k not in FRONT_BULLETS]
    last = max((i for i, l in enumerate(rest) if l.startswith("- ")), default=-1)
    rest = rest[:last + 1] + tail + rest[last + 1:]
    return text[:t.start] + "\n".join([heading, *front, *rest]) + text[t.end:]


def write_plan(c: Ctx, text: str) -> None:
    c.plan.write_text(text)


# -- scope -------------------------------------------------------------------


def in_files(path: str, entries: list[str]) -> bool:
    for e in entries:
        if e.endswith("/"):
            if path.startswith(e) or fnmatch.fnmatchcase(path, e + "*"):
                return True
        elif path == e or (any(ch in e for ch in "*?[") and fnmatch.fnmatchcase(path, e)):
            return True
    return False


def is_playwright(path: str) -> bool:
    return PLAYWRIGHT in path.split("/")[:-1]


def needs_approval(path: str) -> str | None:
    parts = path.split("/")
    if is_playwright(path):
        return "Playwright output is never committed"
    if any(p in APPROVAL_DIRS for p in parts[:-1]) or path.startswith(".git/hooks/"):
        return "agent, CI, hook or infrastructure configuration"
    if parts[-1] in APPROVAL_FILES:
        return "agent configuration"
    if parts[-1] in MANIFESTS or any(fnmatch.fnmatchcase(parts[-1], g) for g in MANIFEST_GLOBS):
        return "dependency manifest or lockfile"
    return None


def scope_problems(changed: list[str], files: list[str], approved: list[str]) -> list[str]:
    problems = []
    for p in changed:
        why = needs_approval(p)
        if why and (p not in approved or is_playwright(p)):
            problems.append(f"{p} needs operator approval ({why})")
        elif not why and not in_files(p, files) and p not in approved:
            problems.append(f"{p} is outside the task's files")
    return problems


def overlaps(a: list[str], b: list[str]) -> bool:
    def stem(e: str) -> str:
        return re.split(r"[*?\[]", e, maxsplit=1)[0]

    for x in a:
        for y in b:
            if x == y:
                return True
            if x.endswith("/") or y.endswith("/") or stem(x) != x or stem(y) != y:
                sx, sy = stem(x), stem(y)
                if sx.startswith(sy) or sy.startswith(sx):
                    return True
    return False


# -- lock --------------------------------------------------------------------


def pid_alive(pid: int) -> bool:
    if pid <= 0:
        return False
    try:
        os.kill(pid, 0)
    except ProcessLookupError:
        return False
    except PermissionError:
        return True
    return True


def default_pid() -> int:
    """The long-lived process: our parent is a one-shot shell, so take its parent."""
    r = subprocess.run(["ps", "-o", "ppid=", "-p", str(os.getppid())],
                       capture_output=True, text=True)
    return int(r.stdout.strip()) if r.stdout.strip().isdigit() else os.getppid()


def lock_path(c: Ctx) -> Path:
    return c.common / LOCK_NAME


def read_lock(c: Ctx) -> dict | None:
    p = lock_path(c)
    if not p.exists():
        return None
    try:
        data = json.loads(p.read_text())
        data["pid"] = int(data.get("pid", 0))
    except (ValueError, TypeError, AttributeError):
        data = {"pid": 0, "session": "?", "started": "?", "feature": "?"}
    data["live"] = pid_alive(data["pid"])
    return data


def describe(holder: dict) -> str:
    return (f"{'live' if holder['live'] else 'stale'} · pid {holder['pid']} · "
            f"session {holder.get('session')} · feature {holder.get('feature')} · "
            f"since {holder.get('started')}")


def lock_record(c: Ctx, pid: int, session: str) -> str:
    return json.dumps({"pid": pid, "session": session, "feature": c.name,
                       "started": time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime())})


def require_lock(c: Ctx) -> dict:
    holder = read_lock(c)
    if holder is None:
        raise Refused("no build lock is held: run build-lock acquire first")
    if not holder["live"]:
        raise Refused(f"the build lock is stale ({describe(holder)}): run build-lock takeover")
    return holder


def cmd_lock(argv: list[str]) -> int:
    args, opts = split_opts(argv, ("--pid", "--session"))
    if len(args) != 2 or args[0] not in ("acquire", "release", "status", "takeover"):
        raise Refused("usage: build-lock acquire|release|status|takeover <feature-dir> "
                      "[--pid PID] [--session ID]")
    action, c = args[0], context(args[1])
    pid = int(opts["--pid"]) if "--pid" in opts else default_pid()
    session = opts.get("--session") or os.environ.get("CLAUDE_SESSION_ID", "unknown")
    holder = read_lock(c)
    p = lock_path(c)
    if action == "status":
        print(f"lock: {describe(holder)}" if holder else "lock: none")
        return 0
    if action == "acquire":
        try:
            fd = os.open(p, os.O_CREAT | os.O_EXCL | os.O_WRONLY, 0o600)
        except FileExistsError:
            holder = read_lock(c) or holder
            if holder and holder["live"]:
                raise Refused(f"another build holds the lock ({describe(holder)})", 1)
            raise Refused(f"the build lock is stale ({describe(holder)}); its process is "
                          "gone. Take it over explicitly: build-lock takeover", 1)
        with os.fdopen(fd, "w") as f:
            f.write(lock_record(c, pid, session))
        print(f"lock: acquired · pid {pid} · session {session}")
        return 0
    if action == "takeover":
        if holder and holder["live"]:
            raise Refused(f"the lock is live ({describe(holder)}); takeover is for a stale lock only", 1)
        tmp = p.with_suffix(".tmp")
        tmp.write_text(lock_record(c, pid, session))
        os.chmod(tmp, 0o600)
        os.replace(tmp, p)
        print(f"lock: taken over from {describe(holder) if holder else 'nobody'} · pid {pid}")
        return 0
    # release
    if holder is None:
        print("lock: none held")
        return 0
    if holder.get("session") != session and holder["pid"] != pid:
        raise Refused(f"the lock belongs to another build ({describe(holder)}); not released", 1)
    p.unlink()
    print("lock: released")
    return 0


# -- the guard mode decides parallelism -------------------------------


def guard_mode() -> str:
    env = os.environ.get("DEVAGENT_GUARD_MODE", "").strip().lower()
    if env:
        return env if env in ("warn", "enforce") else "warn"
    for cand in (HERE.parent.parent / "devagent-standards" / "hooks" / "guard.py",):
        if cand.is_file():
            m = re.search(r'^MODE = "(\w+)"', cand.read_text(), re.M)
            if m and m.group(1) == "enforce":
                return "enforce"
    return "warn"


# -- preflight ---------------------------------------------------------------


def verify_digest(text: str) -> tuple[list[str], str]:
    fm = front_matter(text)
    allowed = fm.get("verify_allowed") if isinstance(fm.get("verify_allowed"), list) else []
    cmds = sorted({t.verify for t in tasks(text) if t.state != "x" and t.verify})
    blob = json.dumps({"allowed": sorted(allowed), "commands": cmds}, sort_keys=True)
    return cmds, hashlib.sha256(blob.encode()).hexdigest()


def ensure_playwright_ignored(c: Ctx) -> bool:
    """Make sure .playwright-mcp/ is gitignored; commit only .gitignore if not."""
    if git(c.repo, "check-ignore", "-q", f"{PLAYWRIGHT}/probe.png", check=False).returncode == 0:
        return False
    gi = c.repo / ".gitignore"
    existing = gi.read_text() if gi.exists() else ""
    gi.write_text(existing + ("" if existing.endswith("\n") or not existing else "\n")
                  + "# Playwright MCP output: never committed\n.playwright-mcp/\n")
    git(c.repo, "add", ".gitignore")
    git(c.repo, "commit", "-q", "-m", "delivery: ignore .playwright-mcp/",
        "-m", ASSISTED_BY, "--", ".gitignore")
    print("note: .playwright-mcp/ was not gitignored; added and committed .gitignore")
    return True


def cmd_preflight(argv: list[str]) -> int:
    args, opts = split_opts(argv, (), flags=("--approve",))
    if len(args) != 1:
        raise Refused("usage: build-preflight <feature-dir> [--approve]")
    c = context(args[0])
    require_lock(c)
    text = c.plan.read_text()
    fm = front_matter(text)
    branch, base = fm.get("branch"), fm.get("base")
    if not branch or not base or isinstance(branch, list) or isinstance(base, list):
        raise Refused(f"{PLAN} front matter needs `branch` and `base`")
    current = git(c.repo, "rev-parse", "--abbrev-ref", "HEAD").stdout.strip()
    if current != branch:
        raise Refused(f"HEAD is on {current!r}; 05 records branch {branch!r}")
    if git(c.repo, "rev-parse", "--verify", "--quiet", f"{base}^{{commit}}", check=False).returncode:
        raise Refused(f"base {base} is not a commit in this repository")
    if git(c.repo, "merge-base", "--is-ancestor", base, "HEAD", check=False).returncode:
        raise Refused(f"diverged: HEAD does not descend from 05's base {base}")
    if d := dirty(c):
        raise Refused("the working tree has uncommitted changes: " + ", ".join(d[:10]))
    ensure_playwright_ignored(c)
    r = subprocess.run([sys.executable, str(CHECK_PLAN), str(c.feature)],
                       capture_output=True, text=True, timeout=300)
    if r.returncode != 0:
        sys.stdout.write(r.stdout + r.stderr)
        raise Refused("check-plan.py rejects the plan; fix it before building")
    print(f"preflight: branch {branch} · base {base} · plan valid")

    cmds, digest = verify_digest(text)
    print("verify commands this build will run:")
    for cmd in cmds:
        print(f"  {cmd}")
    record = c.common / APPROVALS / c.name
    if "--approve" in opts:
        record.parent.mkdir(parents=True, exist_ok=True)
        record.write_text(digest + "\n")
        print("verify set: approved by the operator and recorded")
    elif not record.is_file() or record.read_text().strip() != digest:
        print("verify set: NOT APPROVED - first run, or the commands or verify_allowed "
              "changed. Show the operator the list above; rerun with --approve only on "
              "their explicit yes.")
        return 4
    else:
        print("verify set: unchanged since the operator approved it")

    blocked = reconcile(c)
    return 3 if blocked else 0


def reconcile(c: Ctx) -> bool:
    """Every [~] left by a killed run: integrate its commit, or reset it."""
    blocked = False
    for t in [t for t in tasks(c.plan.read_text()) if t.state == "~"]:
        br = c.branch(t.tid)
        if branch_exists(c.repo, br) and ahead(c.repo, br) > 0:
            print(f"reconcile: {t.tid} has a commit on {br}; integrating it")
            code = integrate(c, t.tid, br, [])
            blocked |= code != 0
            print(f"reconcile: {t.tid} {'integrated' if code == 0 else 'blocked [!]'}")
        else:
            wt = remove_worktree(c, br)
            if branch_exists(c.repo, br):
                git(c.repo, "branch", "-D", br)
            write_plan(c, edit_task(c.plan.read_text(), t.tid, " ", drop=("owner",)))
            print(f"reconcile: {t.tid} had no commit; reset to [ ]"
                  + (f", removed worktree {wt}" if wt else ""))
    return blocked


# -- ready -------------------------------------------------------------------


def cmd_ready(argv: list[str]) -> int:
    args, opts = split_opts(argv, ("--max",))
    if len(args) != 1:
        raise Refused("usage: build-ready <feature-dir> [--max N]")
    c = context(args[0])
    text = c.plan.read_text()
    ts = tasks(text)
    blocked = [t.tid for t in ts if t.state == "!"]
    if blocked:
        print(f"stop: {', '.join(blocked)} [!] - dispatch nothing new (DESIGN §4.4 Stop)")
        return 3
    mode = guard_mode()
    want = int(opts.get("--max", MAX_PARALLEL))
    limit = max(1, want) if mode == "enforce" else 1
    done = {t.tid for t in ts if t.state == "x"}
    ready = [t for t in ts if t.state == " " and all(d in done for d in t.depends)]
    picked: list[Task] = []
    for t in sorted(ready, key=lambda t: int(t.tid[2:])):
        if len(picked) < limit and not any(overlaps(t.files, p.files) for p in picked):
            picked.append(t)
    print(f"guard mode {mode}: up to {limit} builder(s)"
          + ("" if mode == "enforce" else " - attended, one task at a time"))
    for t in picked:
        print(f"{t.tid}\t{t.title}\t{', '.join(t.files)}")
    deferred = [t.tid for t in ready if t not in picked]
    if deferred:
        print(f"ready but deferred: {', '.join(deferred)}")
    if not picked:
        print("no ready tasks")
    return 0


# -- claim -------------------------------------------------------------------


def cmd_claim(argv: list[str]) -> int:
    args, opts = split_opts(argv, ("--owner", "--session"), flags=("--retry",))
    if len(args) != 2 or not TASK_ID.match(args[1]):
        raise Refused("usage: build-claim <feature-dir> <T-nn> [--retry] [--owner O] [--session S]")
    c, tid = context(args[0]), args[1]
    require_lock(c)
    text = c.plan.read_text()
    ts = tasks(text)
    t = task(text, tid)
    retry = "--retry" in opts
    if t.state == "!":
        if not retry:
            raise Refused(f"{tid} is [!]; re-dispatch only on the operator's say-so, with --retry")
        if t.attempts >= MAX_ATTEMPTS:
            raise Refused(f"{tid} failed {t.attempts} attempts; it stays [!] until the operator "
                          "re-plans it", 3)
    elif t.state != " ":
        raise Refused(f"{tid} is [{t.state}], not ready")
    others = [o.tid for o in ts if o.state == "!" and o.tid != tid]
    if others:
        raise Refused(f"stop rule: {', '.join(others)} [!]; dispatch nothing new", 3)
    done = {o.tid for o in ts if o.state == "x"}
    missing = [d for d in t.depends if d not in done]
    if missing:
        raise Refused(f"{tid} depends on {', '.join(missing)}, not done")

    br, wt = c.branch(tid), c.worktree_path(tid)
    if branch_exists(c.repo, br):
        remove_worktree(c, br)
        if ahead(c.repo, br) > 0:
            if not retry:
                raise Refused(f"{br} holds unintegrated work; run build-preflight to reconcile it")
            keep = f"{br}-attempt-{max(t.attempts, 1)}"
            n = 1
            while branch_exists(c.repo, keep):
                n += 1
                keep = f"{br}-attempt-{max(t.attempts, 1)}-{n}"
            git(c.repo, "branch", "-m", br, keep)
            print(f"kept the failed attempt as {keep}")
        else:
            git(c.repo, "branch", "-D", br)
    git(c.repo, "worktree", "prune", check=False)
    if wt.exists():
        raise Refused(f"{wt} exists but is not a registered worktree; inspect it by hand")
    wt.parent.mkdir(parents=True, exist_ok=True)
    git(c.repo, "worktree", "add", "-q", "-b", br, str(wt), "HEAD")
    owner = opts.get("--owner") or git(c.repo, "config", "user.email", check=False).stdout.strip() \
        or os.environ.get("USER", "unknown")
    session = opts.get("--session") or (read_lock(c) or {}).get("session", "unknown")
    started = time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime())
    write_plan(c, edit_task(c.plan.read_text(), tid, "~", drop=("reason",), set_={
        "owner": f"{owner} · session: {session} · started: {started} · worktree: {wt}"}))
    print(f"{tid} [~] · branch {br} · worktree {wt}")
    return 0


# -- integrate ---------------------------------------------------------------


def changed_paths(repo: Path, spec: str) -> list[str]:
    out = git(repo, "diff", "--name-only", "--no-renames", spec).stdout
    return [l for l in out.splitlines() if l]


def commit_subject(c: Ctx, tid: str, title: str) -> str:
    conv = c.repo / CONVENTIONS
    if conv.is_file():
        m = re.search(r"^commit-format:\s*`?([^`\n]+?)`?\s*$", conv.read_text(), re.M)
        if m:
            fmt = m.group(1)
            if fmt.startswith("{id}") and "{title}" in fmt:
                print(f"note: commit message follows {CONVENTIONS}: {fmt}")
                return fmt.replace("{id}", tid).replace("{title}", title)
            print(f"note: ignored {CONVENTIONS} commit-format {fmt!r}: it must start with "
                  "{id} and contain {title} (the plan checker finds a task's commit by its ID)")
    return f"{tid}: {title}"


def conflicting_task(c: Ctx, at: str, paths: list[str]) -> str:
    if paths:
        s = git(c.repo, "log", "-1", "--format=%s", at, "--", *paths, check=False).stdout.strip()
        m = re.match(r"^(T-\d+)", s)
        if m:
            return m.group(1)
    return f"main at {at[:10]}"


def block(c: Ctx, tid: str, reason: str, code: int, attempts: int | None = None) -> int:
    set_ = {"reason": reason}
    if attempts is not None:
        set_["attempts"] = str(attempts)
    write_plan(c, edit_task(c.plan.read_text(), tid, "!", set_=set_, drop=("owner",)))
    print(f"[!] {tid} {reason}")
    return code


def tick(text: str, tid: str, evidence: str) -> str:
    return edit_task(text, tid, "x", set_={"evidence": evidence},
                     drop=("owner", "reason", "attempts"))


def staged_playwright(c: Ctx) -> list[str]:
    return [p for p in git(c.repo, "diff", "--cached", "--name-only").stdout.splitlines()
            if is_playwright(p)]


def integrate(c: Ctx, tid: str, br: str, approved: list[str]) -> int:
    require_lock(c)
    if bad := staged_playwright(c):
        ensure_playwright_ignored(c)
        raise Refused(f"refused: staged Playwright output {', '.join(bad)} is never committed "
                      "; unstage it (git rm --cached) and keep it out of the repo")
    text = c.plan.read_text()
    fm = front_matter(text)
    t = task(text, tid)
    if t.state == "x":
        raise Refused(f"{tid} is already [x]")
    if t.state == "!" and t.attempts >= MAX_ATTEMPTS:
        raise Refused(f"{tid} failed {t.attempts} attempts; it stays [!] until the operator re-plans it", 3)
    current = git(c.repo, "rev-parse", "--abbrev-ref", "HEAD").stdout.strip()
    if current != fm.get("branch"):
        raise Refused(f"HEAD is on {current!r}; 05 records branch {fm.get('branch')!r}")
    if not branch_exists(c.repo, br):
        raise Refused(f"no branch {br}")
    if d := dirty(c):
        raise Refused("the working tree has uncommitted changes: " + ", ".join(d[:10]))
    base = head(c)
    if ahead(c.repo, br) == 0:
        raise Refused(f"{br} has no commit beyond HEAD; nothing to integrate")

    # 1. scope, before anything from the branch is executed
    problems = scope_problems(changed_paths(c.repo, f"{base}...refs/heads/{br}"), t.files, approved)
    if problems:
        return block(c, tid, "scope: " + "; ".join(problems) + f" · branch {br} kept · if the "
                     "task genuinely needs this, stop and propose moving up a tier (DESIGN §3.2)", 3)

    # 2. rebase onto HEAD inside the task's worktree
    wt = worktree_for(c, br)
    if wt is None:
        wt = c.worktree_path(tid)
        git(c.repo, "worktree", "prune", check=False)
        if wt.exists():
            raise Refused(f"{wt} exists but is not a registered worktree; inspect it by hand")
        wt.parent.mkdir(parents=True, exist_ok=True)
        git(c.repo, "worktree", "add", "-q", str(wt), br)
    git(wt, "reset", "-q", "--hard")
    git(wt, "clean", "-q", "-fd")
    r = git(wt, "rebase", "-q", base, check=False)
    if r.returncode != 0:
        conflicts = [l for l in git(wt, "diff", "--name-only", "--diff-filter=U",
                                    check=False).stdout.splitlines() if l]
        git(wt, "rebase", "--abort", check=False)
        who = conflicting_task(c, base, conflicts)
        return block(c, tid, f"conflict with {who} ({', '.join(conflicts) or 'rebase failed'})"
                     f" · branch {br} kept", 3)
    changed = changed_paths(c.repo, f"{base}..refs/heads/{br}")
    problems = scope_problems(changed, t.files, approved)
    if problems:
        return block(c, tid, "scope after rebase: " + "; ".join(problems) + f" · branch {br} kept", 3)

    # 3. verify in the worktree, against the authoritative plan from main
    wt_plan = wt / c.plan_rel
    wt_plan.parent.mkdir(parents=True, exist_ok=True)
    wt_plan.write_text(text)
    timeout = parse_timeout(t.fields.get("timeout", "")) + 120
    try:
        p = subprocess.run([sys.executable, str(RUN_VERIFY), str(wt / c.rel), tid],
                           capture_output=True, text=True, timeout=timeout)
        rc, out = p.returncode, p.stdout + p.stderr
    except subprocess.TimeoutExpired:
        rc, out = 124, "run-verify itself exceeded the task timeout\n"
    git(wt, "checkout", "-q", "--", c.plan_rel, check=False)
    sys.stdout.write("".join(out.splitlines(keepends=True)[-15:]))
    m = EVIDENCE.search(out)
    if rc != 0 or not m:
        n = t.attempts + 1
        reason = (f"verify failed (exit {rc}, attempt {n} of {MAX_ATTEMPTS}) · branch {br} kept"
                  f" · worktree {wt}")
        if n >= MAX_ATTEMPTS:
            reason += " · attempts spent: stays [!] until the operator re-plans it"
        return block(c, tid, reason, 1, attempts=n)

    # 4. squash onto main: code and the tick in one commit
    working = c.plan.read_text()
    log_src = wt / c.rel / "evidence" / f"{tid}.log"
    log_dst = c.feature / "evidence" / f"{tid}.log"
    log_rel = f"{c.rel}/evidence/{tid}.log"
    had_log = log_dst.exists()

    def rollback() -> None:
        git(c.repo, "reset", "-q", "--hard", base, check=False)
        if log_dst.exists() and not had_log:
            log_dst.unlink()
        write_plan(c, working)

    try:
        git(c.repo, "merge", "--squash", "-q", f"refs/heads/{br}")
        log_dst.parent.mkdir(parents=True, exist_ok=True)
        shutil.copyfile(log_src, log_dst)
        git(c.repo, "add", "-f", "--", log_rel)
        committed = git(c.repo, "show", f"HEAD:{c.plan_rel}", check=False)
        ticked = tick(committed.stdout if committed.returncode == 0 else working, tid, m.group(1))
        blob = git(c.repo, "hash-object", "-w", "--stdin", stdin=ticked).stdout.strip()
        git(c.repo, "update-index", "--add", "--cacheinfo", f"100644,{blob},{c.plan_rel}")
        staged = git(c.repo, "diff", "--cached", "--name-only").stdout.splitlines()
        if bad := [s for s in staged if is_playwright(s)]:
            raise Refused(f"refused: Playwright output staged for commit: {', '.join(bad)}")
        extra = [s for s in staged if s not in set(changed) | {c.plan_rel, log_rel}]
        if extra:
            raise Refused(f"refused: unexpected staged paths {', '.join(extra)}")
        git(c.repo, "commit", "-q", "-m", commit_subject(c, tid, t.title), "-m", ASSISTED_BY)
    except Refused:
        rollback()
        ensure_playwright_ignored(c)
        raise
    write_plan(c, tick(working, tid, m.group(1)))
    remove_worktree(c, br)
    git(c.repo, "branch", "-D", br, check=False)
    print(f"integrated {tid} as {head(c)[:12]} · worktree removed")
    return 0


def parse_timeout(text: str) -> int:
    m = re.fullmatch(r"(\d+)\s*([smh]?)", (text or "").strip())
    if not m:
        return 600
    return int(m.group(1)) * {"s": 1, "m": 60, "h": 3600}[m.group(2) or "s"]


def cmd_integrate(argv: list[str]) -> int:
    args, opts = split_opts(argv, ("--approve-path",), multi=("--approve-path",))
    if len(args) not in (2, 3) or not TASK_ID.match(args[1]):
        raise Refused("usage: build-integrate <feature-dir> <T-nn> [<branch>] [--approve-path P]...")
    c, tid = context(args[0]), args[1]
    br = args[2] if len(args) == 3 else c.branch(tid)
    if br.startswith("-") or not re.fullmatch(r"[A-Za-z0-9._/-]+", br):
        raise Refused(f"refused: {br!r} is not a plain branch name")
    return integrate(c, tid, br, opts.get("--approve-path", []))


# -- status (read-only) ------------------------------------------------------


def age(started: str) -> str:
    try:
        t = time.mktime(time.strptime(started, "%Y-%m-%dT%H:%M:%SZ")) - time.timezone
    except ValueError:
        return "?"
    s = max(0, int(time.time() - t))
    return f"{s // 86400}d" if s >= 86400 else f"{s // 3600}h" if s >= 3600 else f"{s // 60}m"


def cmd_status(argv: list[str]) -> int:
    if len(argv) != 1:
        raise Refused("usage: build-status <feature-dir>")
    c = context(argv[0])
    holder = read_lock(c)
    print(f"lock: {describe(holder)}" if holder else "lock: none")
    names = {" ": "todo", "~": "in progress", "x": "done", "!": "blocked"}
    print("| Task | State | Age | Title | Note |")
    print("|---|---|---|---|---|")
    for t in tasks(c.plan.read_text()):
        note, when = "", ""
        if t.state == "~":
            m = re.search(r"started: (\S+)", t.fields.get("owner", ""))
            when = age(m.group(1)) if m else "?"
            note = t.fields.get("owner", "")
        elif t.state == "!":
            note = t.fields.get("reason", "")
        elif t.state == "x":
            ts = git(c.repo, "log", "-1", "--format=%ct", "-E", f"--grep=^{t.tid}\\b",
                     check=False).stdout.strip()
            when = age(time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime(int(ts)))) if ts else ""
        print(f"| {t.tid} | [{t.state}] {names.get(t.state, '?')} | {when} | {t.title} | {note} |")
    mine = [(p, b) for p, b in worktrees(c.repo) if b.startswith(f"delivery/{c.name}/")]
    print("delivery worktrees: " + (", ".join(f"{b} at {p}" for p, b in mine) or "none"))
    last = git(c.repo, "log", "-1", "-E", "--grep=^T-[0-9]+", "--format=%h %s (%cr)",
               check=False).stdout.strip()
    print(f"last integrated: {last or 'none'}")
    return 0


# -- plumbing ----------------------------------------------------------------


def split_opts(argv: list[str], valued: tuple[str, ...], flags: tuple[str, ...] = (),
               multi: tuple[str, ...] = ()) -> tuple[list[str], dict]:
    args, opts, i = [], {}, 0
    while i < len(argv):
        a = argv[i]
        if a in valued:
            if i + 1 >= len(argv):
                raise Refused(f"{a} needs a value")
            if a in multi:
                opts.setdefault(a, []).append(argv[i + 1])
            else:
                opts[a] = argv[i + 1]
            i += 2
        elif a in flags:
            opts[a] = True
            i += 1
        elif a.startswith("--"):
            raise Refused(f"unknown option {a}")
        else:
            args.append(a)
            i += 1
    return args, opts


COMMANDS = {"lock": cmd_lock, "preflight": cmd_preflight, "ready": cmd_ready,
            "claim": cmd_claim, "integrate": cmd_integrate, "status": cmd_status}


def main(command: str, argv: list[str]) -> int:
    try:
        return COMMANDS[command](argv)
    except Refused as e:
        print(f"build-{command}: {e}", file=sys.stderr)
        return e.code
    except (ValueError, OSError, subprocess.TimeoutExpired) as e:
        print(f"build-{command}: {e}", file=sys.stderr)
        return 2
