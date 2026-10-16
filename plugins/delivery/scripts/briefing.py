#!/usr/bin/env python3
"""Delivery hooks: the SessionStart briefing and the PostToolUse plan check.

    briefing.py           SessionStart: print a structure-only briefing as
                          hookSpecificOutput.additionalContext
    briefing.py --post    PostToolUse (Write|Edit|MultiEdit): read the hook
                          JSON on stdin and run `check-plan.py --hook <path>`

The briefing carries STRUCTURE ONLY (DESIGN §8):
feature folder names, which step files exist, task counts by status, the next
ready task ID, the build lock holder's PID, the count of uncommitted files and
whether NOTES.md exists. No free text from a plan body, knowledge file or
NOTES.md is ever emitted - every value is a count, a fixed word, or a string
that matched a strict ID/name pattern. The full briefing is /delivery:load.

It prints nothing when the project has neither docs/plans/ nor NOTES.md, stays
within MAX_LINES, and keeps an internal time budget well under the hook
timeout. It fails open, but never silently: an internal error becomes
one line of context naming the exception type.

Python 3.11+ standard library only.
"""

from __future__ import annotations

import json
import os
import re
import subprocess
import sys
import time
from pathlib import Path

MAX_LINES = 25
BUDGET_S = float(os.environ.get("DELIVERY_BRIEFING_BUDGET_S", "4"))  # hook timeout is 10
POST_BUDGET_S = 4  # hook timeout is 5
LOAD = "run /delivery:load"
SAFE_NAME = re.compile(r"[A-Za-z0-9][A-Za-z0-9._-]{0,63}")
TASK_HEAD = re.compile(r"### (T-\d{2,4}) \[([ ~x!])\] ")
DEPENDS = re.compile(r"- depends: (none|T-\d{2,4}(?:, T-\d{2,4})*)\s*$")
STATUSES = (" ", "~", "x", "!")


def emit_context(text: str) -> None:
    print(json.dumps({"hookSpecificOutput": {"hookEventName": "SessionStart",
                                             "additionalContext": text}}))


def find_root(start: Path) -> Path:
    for d in (start, *start.parents):
        if (d / ".git").exists() or (d / "docs" / "plans").is_dir():
            return d
    return start


def tasks(impl: Path) -> tuple[dict[str, int], str | None]:
    """Counts by status and the next ready task ID - IDs and markers only."""
    counts = dict.fromkeys(STATUSES, 0)
    status: dict[str, str] = {}
    deps: dict[str, list[str]] = {}
    current = None
    for line in impl.read_text(encoding="utf-8", errors="replace").splitlines():
        m = TASK_HEAD.match(line)
        if m:
            current = m.group(1)
            status[current] = m.group(2)
            counts[m.group(2)] += 1
            deps[current] = []
            continue
        d = DEPENDS.match(line)
        if current and d and d.group(1) != "none":
            deps[current] = d.group(1).split(", ")
    ready = [t for t, s in status.items()
             if s == " " and all(status.get(dep) == "x" for dep in deps[t])]
    return counts, (min(ready, key=lambda t: int(t[2:])) if ready else None)


def plan_line(folder: Path) -> str:
    name = folder.name if SAFE_NAME.fullmatch(folder.name) else "(unsafe folder name)"
    steps = [n for n in "12345" if any(folder.glob(f"0{n}-*.md"))]
    line = f"- plan {name}: steps {' '.join('0' + n for n in steps) or 'none'}"
    impl = next(iter(sorted(folder.glob("05-*.md"))), None)
    if impl is not None:
        counts, nxt = tasks(impl)
        line += (f" · tasks [ ] {counts[' ']} [~] {counts['~']} [x] {counts['x']}"
                 f" [!] {counts['!']} · next ready {nxt or 'none'}")
    return line


def git(root: Path, *args: str) -> str | None:
    try:
        r = subprocess.run(["git", "-C", str(root), *args], capture_output=True,
                           text=True, timeout=2)
    except (OSError, subprocess.TimeoutExpired):
        return None
    return r.stdout if r.returncode == 0 else None


def lock_line(root: Path) -> str:
    common = git(root, "rev-parse", "--git-common-dir")
    if common is None:
        return "- build lock: n/a (not a git repository)"
    lock = (root / common.strip()) / "delivery-build.lock"
    if not lock.is_file():
        return "- build lock: none"
    text = lock.read_text(errors="replace")[:200]
    m = re.search(r"pid\W{0,3}(\d{1,10})\b", text, re.I) or re.match(r"\s*(\d{1,10})\b", text)
    if not m:
        return "- build lock: held (holder unreadable)"
    pid = int(m.group(1))
    try:
        os.kill(pid, 0)
        state = "live"
    except ProcessLookupError:
        state = "stale"
    except OSError:
        state = "live"  # exists, owned by another user
    return f"- build lock: held by pid {pid} ({state})"


def briefing(data: dict) -> str:
    if data.get("agent_id"):  # main session only; SessionStart in subagents is undocumented, so not relied on
        return ""
    root = find_root(Path(data.get("cwd") or os.getcwd()).resolve())
    plans = root / "docs" / "plans"
    notes = (root / "NOTES.md").is_file()
    if not plans.is_dir() and not notes:
        return ""
    started = time.monotonic()
    head = [f"[delivery] session briefing - structure only, {LOAD} for the full DATA briefing"]
    folders = sorted(p for p in plans.iterdir()
                     if p.is_dir() and not p.name.startswith(".")) if plans.is_dir() else []
    tail = []
    body: list[str] = []
    over_budget = False
    for folder in folders:
        if time.monotonic() - started > BUDGET_S:
            over_budget = True
            break
        body.append(plan_line(folder))
    if not folders:
        body.append("- plans: none")
    if not over_budget and time.monotonic() - started <= BUDGET_S:
        tail.append(lock_line(root))
        status = git(root, "status", "--porcelain")
        tail.append(f"- uncommitted files: {'n/a' if status is None else len(status.splitlines())}")
    else:
        over_budget = True
    tail.append(f"- NOTES.md: {'present' if notes else 'absent'}")
    if over_budget:
        tail.append(f"briefing truncated (budget) — {LOAD}")
    room = MAX_LINES - len(head) - len(tail)
    if len(body) > room:
        hidden = len(body) - (room - 1)
        body = body[: room - 1] + [f"+{hidden} more — {LOAD}"]
    return "\n".join(head + body + tail)


def post(data: dict) -> int:
    path = (data.get("tool_input") or {}).get("file_path")
    if not isinstance(path, str) or not path:
        return 0
    checker = Path(__file__).with_name("check-plan.py")
    cwd = data.get("cwd") or None
    try:
        r = subprocess.run([sys.executable, str(checker), f"--hook={path}"], cwd=cwd,
                           capture_output=True, text=True, timeout=POST_BUDGET_S)
    except subprocess.TimeoutExpired:
        print(json.dumps({"systemMessage": f"[delivery] plan check skipped (budget) - "
                                           f"run check-plan.py on {path}"}))
        return 0
    if r.returncode == 2:
        sys.stderr.write(r.stderr)
        return 2
    if r.returncode != 0:  # usage error or crash in the checker: fail open, visibly
        print(json.dumps({"systemMessage": f"[delivery] plan check error (exit {r.returncode})"}))
    return 0


def main(argv: list[str]) -> int:
    is_post = argv[1:] == ["--post"]
    try:
        raw = sys.stdin.read()
        data = json.loads(raw) if raw.strip() else {}
        if not isinstance(data, dict):
            raise TypeError("hook input is not a JSON object")
        if is_post:
            return post(data)
        text = briefing(data)
        if text:
            emit_context(text)
    except Exception as e:  # fail open, never silently
        msg = f"[delivery] {'plan check' if is_post else 'briefing'} skipped: internal error ({type(e).__name__}) — {LOAD}"
        if is_post:
            print(json.dumps({"systemMessage": msg}))
        else:
            emit_context(msg)
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
