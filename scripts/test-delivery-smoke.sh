#!/usr/bin/env bash
#
# Install smoke test for the delivery plugin, in REAL new sessions.
#
#     bash scripts/test-delivery-smoke.sh --record   # run live headless sessions (needs AWS sign-in; ~$0.20)
#     bash scripts/test-delivery-smoke.sh            # assert (what run-verify runs)
#
# Two modes because run-verify strips AWS credentials by design, so a verify
# command can never start a Bedrock session. --record starts four headless
# `claude -p` sessions and keeps a TRIMMED summary of what each one saw
# (skill names, hook output, tool results - never the raw transcript) in
# .smoke/sessions.json (gitignored: it records this machine's paths). An agent's `tools:` line
# cannot pre-approve a command (found by this test); web-search runs unprompted
# only through the exact-path allow rule install.sh writes (DESIGN §6.2), so
# --record needs ./install.sh to have run. The default mode re-checks
# the installed plugin and asserts against that recording, and refuses a
# recording made on a different Claude Code version than the one installed.
#
set -uo pipefail
REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
REC="$REPO/.smoke/sessions.json"
SCRIPTS="$REPO/plugins/delivery/scripts"

if [ "${1:-}" = "--record" ]; then
  T="$(mktemp -d /tmp/devagent-smoke.XXXXXX)"; trap 'rm -rf "$T"' EXIT
  # The sessions run in a throwaway project shaped like a real one: a git repo
  # with one plan in docs/plans/, so the SessionStart briefing has something
  # to describe. (A fresh clone of DevAgent itself has no plans, and the
  # briefing is correctly silent there.)
  PROJ="$T/project"; mkdir -p "$PROJ/docs/plans"
  cp -R "$REPO/examples/guard-report" "$PROJ/docs/plans/guard-report"
  git -C "$PROJ" init -q && git -C "$PROJ" add -A \
    && git -C "$PROJ" -c user.name=smoke -c user.email=smoke@example.invalid commit -qm fixture
  cd "$PROJ" || exit 2
  run() {  # name, prompt, extra args...
    local name="$1" prompt="$2"; shift 2
    claude -p "$prompt" --model haiku --max-budget-usd 0.15 --permission-mode default \
      --output-format stream-json --verbose --include-hook-events "$@" > "$T/$name.jsonl" 2>"$T/$name.err"
    echo "  $name: exit $?"
  }
  echo "recording four headless sessions in a fixture project ($PROJ)"
  run startup "Reply with the single word OK."
  run invoke  "Call the Skill tool with skill \"delivery:load\". Do nothing else, then reply DONE."
  run allowed "Use the Bash tool to run exactly this command and nothing else: $SCRIPTS/web-search --help ; then reply DONE." --agent delivery:researcher
  run denied  "Use the Bash tool to run exactly this command and nothing else: /bin/date +%Y ; then reply DONE." --agent delivery:researcher
  T="$T" REC="$REC" python3 - <<'PY'
import json, os
from pathlib import Path
T = Path(os.environ["T"])
def events(n):
    return [json.loads(l) for l in (T / f"{n}.jsonl").read_text().splitlines() if l.strip()]
def tool_calls(ev):
    """(tool name, input, result text, is_error) for every tool use, joined by id."""
    uses, out = {}, []
    for e in ev:
        msg = e.get("message")
        for c in (msg.get("content") if isinstance(msg, dict) else None) or []:
            if not isinstance(c, dict): continue
            if c.get("type") == "tool_use": uses[c["id"]] = (c["name"], c.get("input"))
            if c.get("type") == "tool_result" and c.get("tool_use_id") in uses:
                body = c.get("content")
                text = body if isinstance(body, str) else " ".join(x.get("text", "") for x in body or [] if isinstance(x, dict))
                n, i = uses[c["tool_use_id"]]
                out.append({"tool": n, "input": i, "result": text[:600], "is_error": bool(c.get("is_error"))})
    return out
rec = {}
for n in ("startup", "invoke", "allowed", "denied"):
    ev = events(n)
    init = next(e for e in ev if e.get("type") == "system" and e.get("subtype") == "init")
    res = next((e for e in ev if e.get("type") == "result"), {})
    rec[n] = {
        "claude_code_version": init.get("claude_code_version"),
        "tools": sorted(init.get("tools", [])),
        "skills": sorted(s for s in init.get("skills", []) if s.startswith("delivery:")),
        "slash_commands": sorted(s for s in init.get("slash_commands", []) if s.startswith("delivery:")),
        "agents": sorted(a for a in init.get("agents", []) if a.startswith("delivery:")),
        "hook_context": [((e.get("output") or "") if isinstance(e.get("output"), str) else json.dumps(e.get("output")))[:2000]
                         for e in ev if e.get("subtype") == "hook_response"],
        "tool_calls": tool_calls(ev),
        "cost_usd": res.get("total_cost_usd"),
    }
Path(os.environ["REC"]).parent.mkdir(exist_ok=True)
Path(os.environ["REC"]).write_text(json.dumps(rec, indent=1) + "\n")
print("recorded", os.environ["REC"], "total $%.4f" % sum((r["cost_usd"] or 0) for r in rec.values()))
PY
  exit $?
fi

REPO="$REPO" REC="$REC" SCRIPTS="$SCRIPTS" python3 - <<'PY'
import json, os, re, subprocess
from pathlib import Path
REPO, REC = Path(os.environ["REPO"]), Path(os.environ["REC"])
passed = failed = 0
def check(name, ok, detail=""):
    global passed, failed
    if ok: passed += 1
    else: failed += 1; print(f"  FAIL {name} {str(detail)[:300]}")

STEPS = sorted(["load", "brainstorm", "design", "research", "spec-panel", "workflow", "build", "plan", "save"])
WANT = [f"delivery:{s}" for s in STEPS]

# 1. Installed plugin, as the CLI reports it (no model call).
d = subprocess.run(["claude", "plugin", "details", "delivery@devagent"], capture_output=True, text=True)
m = re.search(r"Skills \((\d+)\)\s+(.+)", d.stdout)
check("CLI: plugin installed", d.returncode == 0, d.stderr)
check("CLI: nine skills", bool(m) and m.group(1) == "9" and sorted(m.group(2).split(", ")) == STEPS, m.group(0) if m else d.stdout[:300])
check("CLI: four agents", "Agents (4)" in d.stdout, d.stdout[:400])
check("CLI: SessionStart and PostToolUse hooks", re.search(r"Hooks \(2\)\s+SessionStart, PostToolUse", d.stdout) is not None)

# 2. Every skill is user-invoked only, in the files that ship.
for s in STEPS:
    fm = (REPO / "plugins/delivery/skills" / s / "SKILL.md").read_text().split("---")[1]
    check(f"{s}: disable-model-invocation: true", re.search(r"^disable-model-invocation:\s*true\s*$", fm, re.M) is not None)

# 3. The allow rule the researcher depends on is installed, exact path only.
cfg = json.loads((Path.home() / ".claude" / "settings.json").read_text())
allow = (cfg.get("permissions") or {}).get("allow") or []
rule = f"Bash({REPO}/plugins/delivery/scripts/web-search:*)"
check("settings.json carries the exact-path web-search rule", rule in allow, [a for a in allow if "web-search" in a])
check("no wildcard web-search rule", not [a for a in allow if "web-search" in a and "*" in a.split(":*)")[0]])

# 4. The recorded new sessions.
check("recording exists (run with --record)", REC.is_file())
rec = json.loads(REC.read_text()) if REC.is_file() else {}
v = subprocess.run(["claude", "--version"], capture_output=True, text=True).stdout.split()[0:1]
installed = v[0] if v else "?"
pins = (REPO / "plugins/delivery/PINS.md").read_text()
for n, r in rec.items():
    check(f"{n}: recorded on the installed Claude Code ({installed})", r.get("claude_code_version") == installed, r.get("claude_code_version"))
check("PINS.md claude-code is the version tested", re.search(rf"^\| claude-code \| {re.escape(installed)} \|", pins, re.M) is not None, installed)

s = rec.get("startup", {})
check("new session: all nine /delivery:* commands, prefixed", s.get("slash_commands") == WANT, s.get("slash_commands"))
check("new session: four delivery agents", s.get("agents") == sorted(f"delivery:{a}" for a in ("builder", "requirements-analyst", "researcher", "reviewer")), s.get("agents"))
brief = next((h for h in s.get("hook_context", []) if "[delivery] session briefing" in h), "")
check("new session: SessionStart briefing injected", bool(brief), s.get("hook_context"))
ctx = json.loads(brief).get("hookSpecificOutput", {}).get("additionalContext", "") if brief.startswith("{") else brief
lines = ctx.splitlines()
check("briefing: <= 25 lines", 0 < len(lines) <= 25, len(lines))
STRUCT = re.compile(r"^(\[delivery\] session briefing - structure only, run /delivery:load for the full DATA briefing"
                    r"|- plan [A-Za-z0-9._-]+: steps [0-9 ]+( · tasks \[ \] \d+ \[~\] \d+ \[x\] \d+ \[!\] \d+ · next ready (T-\d+|none))?"
                    r"|- build lock: .*|- uncommitted files: (\d+|n/a)|- NOTES.md: (present|absent)|- plans: none|\+\d+ more — run /delivery:load)$")
check("briefing: every line is structure only", all(STRUCT.match(l) for l in lines), [l for l in lines if not STRUCT.match(l)])

inv = rec.get("invoke", {}).get("tool_calls", [])
skill_ok = [c for c in inv if c["tool"] == "Skill" and not c["is_error"]]
check("model cannot invoke a delivery skill", not skill_ok, inv)

a = rec.get("allowed", {})
check("researcher session ran as the researcher agent (its tools only)", a.get("tools") == ["Bash", "Read", "WebFetch"], a.get("tools"))
web = [c for c in a.get("tool_calls", []) if c["tool"] == "Bash" and "web-search" in str(c["input"])]
check("researcher: the install.sh allow rule permits web-search, no prompt",
      bool(web) and not web[0]["is_error"] and "usage: web-search" in web[0]["result"], web or a.get("tool_calls"))
dn = rec.get("denied", {})
date = [c for c in dn.get("tool_calls", []) if c["tool"] == "Bash"]
check("researcher: any other Bash command is refused", bool(date) and all(c["is_error"] for c in date)
      and not any(re.fullmatch(r"\s*20\d\d\s*", c["result"]) for c in date), date or dn.get("tool_calls"))

print(f"{passed} passed, {failed} failed")
raise SystemExit(1 if failed else 0)
PY
