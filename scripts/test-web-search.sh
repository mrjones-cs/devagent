#!/usr/bin/env bash
#
# Offline tests for plugins/delivery/scripts/web-search.
#
#     bash scripts/test-web-search.sh             # tests only
#     COVERAGE=1 bash scripts/test-web-search.sh  # plus line+branch coverage
#
# Nothing here touches AWS. HOME is a temp dir, `aws` is a fake on PATH that
# prints fake credentials, and the gateway is a local fake MCP endpoint on
# 127.0.0.1 (plain http is allowed only because the test sets
# DEVAGENT_WEBSEARCH_TEST_ALLOW_HTTP=1; the script requires https otherwise).
#
# Coverage uses coverage.py pinned to 7.16.2 through `uv run --with`, so it is
# fetched into uv's cache and never installed into the repo or the system.

set -uo pipefail

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SUBJECT="$REPO/plugins/delivery/scripts/web-search"
WORK="$(mktemp -d /tmp/devagent-websearch-test.XXXXXX)"
trap 'rm -rf "$WORK"' EXIT

cat >"$WORK/driver.py" <<'PY'
import datetime, http.server, importlib.machinery, importlib.util, json, os
import subprocess, sys, threading, stat
from pathlib import Path

SUBJECT = os.environ["SUBJECT"]
WORK = Path(os.environ["WORK"])
COVER = os.environ.get("COVERAGE") == "1"
PASSED, FAILED = 0, 0

FAKE_KEY = "AKIAFAKEKEY00TEST"
FAKE_SECRET = "fakeSECRETvalue/never+printed0123456789"
FAKE_TOKEN = "fakeSESSIONtokenNeverPrinted=="


def check(name, cond, detail=""):
    global PASSED, FAILED
    if cond:
        PASSED += 1
        print(f"  PASS  {name}")
    else:
        FAILED += 1
        print(f"  FAIL  {name}  {detail}")


# ---------------------------------------------------------------- module load
loader = importlib.machinery.SourceFileLoader("websearch", SUBJECT)
spec = importlib.util.spec_from_loader("websearch", loader)
ws = importlib.util.module_from_spec(spec)
loader.exec_module(ws)

# ---------------------------------------------------------------- fake server
TOOL_FULL = {
    "name": "web-search___WebSearch",
    "description": "search",
    "inputSchema": {
        "type": "object",
        "properties": {
            "query": {"type": "string"},
            "maxResults": {"type": "integer"},
            "includeDomains": {"type": "array", "items": {"type": "string"}},
            "excludeDomains": {"type": "array", "items": {"type": "string"}},
            "startPublishedDate": {"type": "string", "format": "date"},
        },
    },
}
TOOL_OLD = {"name": "web-search___WebSearch", "inputSchema": {"type": "object", "properties": {
    "query": {"type": "string"}, "maxResults": {"type": "integer"}}}}
RESULTS = {"results": [
    {"title": "One", "url": "https://a.example/1", "publishedDate": "2026-01-02", "text": "alpha"},
    {"title": "Two", "url": "https://b.example/2", "publishedDate": "", "text": "beta"},
]}

STATE = {}


def reset(**kw):
    STATE.clear()
    STATE.update({"requests": [], "tool": TOOL_FULL, "status": {}, "call_body": None,
                  "sse": False, "error": None, "list_raw": None})
    STATE.update(kw)


class H(http.server.BaseHTTPRequestHandler):
    def log_message(self, *a):
        pass

    def do_POST(self):
        body = self.rfile.read(int(self.headers.get("content-length", 0)))
        msg = json.loads(body)
        STATE["requests"].append({"headers": dict(self.headers), "msg": msg})
        method = msg["method"]
        status = STATE["status"].get(method)
        if isinstance(status, list):
            status = status.pop(0) if status else None
        if status:
            text = STATE.get("error_body") or "error"
            if text == "ECHO":
                text = json.dumps(dict(self.headers))
            self.send_response(status)
            self.end_headers()
            self.wfile.write(text.encode())
            return
        if method == "tools/list":
            if STATE["list_raw"] is not None:
                out = STATE["list_raw"]
            else:
                out = json.dumps({"jsonrpc": "2.0", "id": msg["id"], "result": {"tools": [STATE["tool"]]}})
        elif STATE["error"]:
            out = json.dumps({"jsonrpc": "2.0", "id": msg["id"], "error": STATE["error"]})
        else:
            res = STATE["call_body"] if STATE["call_body"] is not None else {
                "content": [{"type": "text", "text": json.dumps(RESULTS)}]}
            out = json.dumps({"jsonrpc": "2.0", "id": msg["id"], "result": res})
        if STATE["sse"]:
            out = f"event: message\ndata: {out}\n\n"
        self.send_response(200)
        self.send_header("content-type", "text/event-stream" if STATE["sse"] else "application/json")
        self.end_headers()
        self.wfile.write(out.encode())


srv = http.server.ThreadingHTTPServer(("127.0.0.1", 0), H)
threading.Thread(target=srv.serve_forever, daemon=True).start()
URL = f"http://127.0.0.1:{srv.server_address[1]}/mcp"

# ---------------------------------------------------------------- environment
HOME = WORK / "home"
HOME.mkdir()
BIN = WORK / "bin"
BIN.mkdir()
(BIN / "aws").write_text(
    "#!/bin/sh\n"
    'if [ "$FAKE_AWS_FAIL" = 1 ]; then echo "boom ' + FAKE_SECRET + '" >&2; exit 255; fi\n'
    f"printf '%s' '{json.dumps({'Version': 1, 'AccessKeyId': FAKE_KEY, 'SecretAccessKey': FAKE_SECRET, 'SessionToken': FAKE_TOKEN})}'\n"
)
(BIN / "aws").chmod(0o755)
ENG = WORK / "engagement"
ENG.mkdir()
subprocess.run(["git", "init", "-q", str(ENG)], check=True)
(ENG / ".delivery").mkdir()
(ENG / ".delivery" / "deny-list").write_text("# client terms\n\n  AcmeWidgetCo  \nproject-zebra\n")
NOGIT = WORK / "nogit"
NOGIT.mkdir()

BASE_ENV = {
    "PATH": f"{BIN}:{os.environ['PATH']}",
    "HOME": str(HOME),
    "DEVAGENT_WEBSEARCH_URL": URL,
    "DEVAGENT_WEBSEARCH_TEST_ALLOW_HTTP": "1",
    "DEVAGENT_WEBSEARCH_BACKOFF": "0.01",
    "GIT_CEILING_DIRECTORIES": str(WORK),
}
if "COVERAGE_RCFILE" in os.environ:
    BASE_ENV["COVERAGE_RCFILE"] = os.environ["COVERAGE_RCFILE"]
    BASE_ENV["COVERAGE_FILE"] = os.environ["COVERAGE_FILE"]

ALL_OUT = []


def run(args, env=None, cwd=ENG, drop=()):
    e = dict(BASE_ENV)
    e.update(env or {})
    for k in drop:
        e.pop(k, None)
    cmd = [sys.executable, "-m", "coverage", "run", "-p", SUBJECT] if COVER else [sys.executable, SUBJECT]
    p = subprocess.run(cmd + args, env=e, cwd=cwd, capture_output=True, text=True, timeout=60)
    ALL_OUT.append(p.stdout + p.stderr)
    return p


AUDIT = HOME / ".claude" / "devagent-audit" / "search.jsonl"

print("web-search offline tests")

# ---- SigV4 against published AWS test vectors -----------------------------
# Source: the AWS Signature Version 4 test suite (aws-sig-v4-test-suite), as
# vendored in boto/botocore tests/unit/auth/aws4_testsuite/: cases
# post-vanilla and post-x-www-form-urlencoded. Credentials AKIDEXAMPLE /
# wJalrXUtnFEMI/K7MDENG+bPxRfiCYEXAMPLEKEY, us-east-1, service "service",
# 20150830T123600Z.
V_CREDS = {"key": "AKIDEXAMPLE", "secret": "wJalrXUtnFEMI/K7MDENG+bPxRfiCYEXAMPLEKEY", "token": ""}
V_NOW = datetime.datetime(2015, 8, 30, 12, 36, 0, tzinfo=datetime.UTC)
a = ws.sigv4_authorization("POST", "https://example.amazonaws.com/",
                           {"Host": "example.amazonaws.com", "X-Amz-Date": "20150830T123600Z"},
                           b"", V_CREDS, V_NOW, "us-east-1", "service")
check("SigV4 matches AWS test-suite vector post-vanilla",
      a == "AWS4-HMAC-SHA256 Credential=AKIDEXAMPLE/20150830/us-east-1/service/aws4_request, "
           "SignedHeaders=host;x-amz-date, Signature=5da7c1a2acd57cee7505fc6676e4e544621c30862966e37dddb68e92efbe5d6b", a)
a = ws.sigv4_authorization("POST", "https://example.amazonaws.com/",
                           {"Content-Type": "application/x-www-form-urlencoded", "Host": "example.amazonaws.com",
                            "X-Amz-Date": "20150830T123600Z"},
                           b"Param1=value1", V_CREDS, V_NOW, "us-east-1", "service")
check("SigV4 matches AWS test-suite vector post-x-www-form-urlencoded (body + content-type)",
      a.endswith("SignedHeaders=content-type;host;x-amz-date, "
                 "Signature=ff11897932ad3f4e8b18135d722051e5ac45fc38421b1da7b9d196a0fe09473a"), a)
# AWS docs "Examples of how to derive a signing key for Signature Version 4".
k = ws.signing_key("wJalrXUtnFEMI/K7MDENG+bPxRfiCYEXAMPLEKEY", "20120215", "us-east-1", "iam").hex()
check("SigV4 signing key matches the AWS documentation example",
      k == "f4780e2d9f65fa895f9c67b32ce1baf0b0d8a43505a000a1a9e090d414db404d", k)
h = ws.sign("https://x.example/mcp", b"{}", {"key": "AK", "secret": "S", "token": "T"}, V_NOW)
check("gateway signing covers the token header and uses bedrock-agentcore/us-east-1",
      "x-amz-security-token" in h["authorization"] and "/us-east-1/bedrock-agentcore/" in h["authorization"])
try:
    ws.sigv4_authorization("POST", "https://x.example/?a=b", {"host": "x"}, b"", V_CREDS, V_NOW)
    check("query strings are refused by the signer", False)
except ValueError:
    check("query strings are refused by the signer", True)

# ---- happy path ------------------------------------------------------------
reset()
p = run(["test query", "--include", "docs.aws.amazon.com", "--exclude", "spam.example",
         "--since", "2026-01-01", "--max", "3", "--json"])
check("happy path exits 0", p.returncode == 0, p.stderr)
try:
    out = json.loads(p.stdout)
except ValueError:
    out = {}
check("JSON output shape", out.get("engine") == "web-search" and out.get("query") == "test query"
      and out.get("results", [{}])[0] == {"title": "One", "url": "https://a.example/1",
                                          "published": "2026-01-02", "excerpt": "alpha"}, p.stdout)
check("untrusted-content warning on stderr in --json mode", ws.WARNING in p.stderr)
reqs = STATE["requests"]
check("tools/list then one tools/call", [r["msg"]["method"] for r in reqs] == ["tools/list", "tools/call"])
args = reqs[-1]["msg"]["params"]["arguments"] if len(reqs) == 2 else {}
check("filters mapped onto discovered schema names",
      args == {"query": "test query", "maxResults": 3, "includeDomains": ["docs.aws.amazon.com"],
               "excludeDomains": ["spam.example"], "startPublishedDate": "2026-01-01"}, args)
check("requests are SigV4 signed for bedrock-agentcore",
      all(r["headers"].get("Authorization", "").startswith(f"AWS4-HMAC-SHA256 Credential={FAKE_KEY}/")
          and "/us-east-1/bedrock-agentcore/aws4_request" in r["headers"]["Authorization"] for r in reqs))
lines = AUDIT.read_text().splitlines() if AUDIT.exists() else []
rec = json.loads(lines[-1]) if lines else {}
check("audit line written with query, urls, sha256",
      rec.get("query") == "test query" and rec.get("urls") == ["https://a.example/1", "https://b.example/2"]
      and rec.get("sha256") == ws.result_hash(out.get("results", [])), rec)
check("audit records which version signal was used", str(rec.get("version_signal", "")).startswith("schema-filters:"))
check("audit dir is 700 and file 600",
      AUDIT.exists() and stat.S_IMODE(AUDIT.parent.stat().st_mode) == 0o700
      and stat.S_IMODE(AUDIT.stat().st_mode) == 0o600)

reset(sse=True)
p = run(["text mode"])
check("text mode over an SSE response prints the warning first and results",
      p.returncode == 0 and p.stdout.startswith(ws.WARNING) and "https://b.example/2" in p.stdout, p.stderr)

# ---- deny-list -------------------------------------------------------------
reset()
p = run(["pricing for acmewidgetco widgets"])
check("deny-listed query exits 2", p.returncode == 2, p.stderr)
check("deny-listed query: fake server received zero requests", STATE["requests"] == [])
check("deny-list message names the term but not the query",
      "AcmeWidgetCo" in p.stderr and "pricing" not in p.stderr, p.stderr)
n_before = len(AUDIT.read_text().splitlines())
p = run(["x PROJECT-ZEBRA y"], drop=("DEVAGENT_WEBSEARCH_URL",))
check("deny-list beats missing config (still exit 2, no audit line)",
      p.returncode == 2 and len(AUDIT.read_text().splitlines()) == n_before)
reset()
p = run(["acmewidgetco outside a repo"], cwd=NOGIT)
check("outside a git repo there is no deny-list to apply", p.returncode == 0, p.stderr)
(ENG / ".delivery" / "deny-list").chmod(0o000)
reset()
p = run(["anything"])
(ENG / ".delivery" / "deny-list").chmod(0o600)
check("unreadable deny-list fails closed with exit 2 and no request",
      (p.returncode == 2 and STATE["requests"] == []) or os.geteuid() == 0, p.stderr)

# ---- connector version -----------------------------------------------------
reset(tool=TOOL_OLD)
p = run(["q"])
check("filters absent from schema (1.1.0 shape) -> exit 6", p.returncode == 6, p.stderr)
check("... and no tools/call was sent", [r["msg"]["method"] for r in STATE["requests"]] == ["tools/list"])
reset(tool=dict(TOOL_FULL, annotations={"connectorVersion": "1.1.0"}))
p = run(["q"])
check("explicit connector version 1.1.0 -> exit 6", p.returncode == 6 and "1.1.0" in p.stderr, p.stderr)
reset(tool=dict(TOOL_OLD, _meta={"target": {"version": "1.2.0"}}))
p = run(["q"])
check("explicit version 1.2.0 accepted even without filters", p.returncode == 0, p.stderr)
reset(tool=dict(TOOL_OLD, _meta={"version": "1.2.0"}))
p = run(["q", "--include", "a.example"])
check("explicit 1.2.0 but no include argument -> exit 6", p.returncode == 6, p.stderr)
nested = {"name": "web-search___WebSearch", "inputSchema": {"type": "object", "properties": {
    "query": {"type": "string"}, "filters": {"type": "object", "properties": {
        "include_domains": {"type": "string"}, "exclude_domains": {"type": "string"},
        "published_after_date": {"type": "string", "format": "date-time"}}}}}}
reset(tool=nested)
p = run(["q", "--include", "a.example", "--include", "b.example", "--since", "2026-02-03"])
args = STATE["requests"][-1]["msg"]["params"]["arguments"] if STATE["requests"] else {}
check("nested filter object, string-typed domains, date-time format",
      p.returncode == 0 and args.get("filters") == {"include_domains": "a.example,b.example",
                                                     "published_after_date": "2026-02-03T00:00:00Z"}, args)
# The LIVE 1.2.0 schema, captured from tools/list on 2026-10-14. The
# original fixtures used flat names and missed it: leaf names "include" and
# "from" carry no domain/date context, only their parents do.
live = {"name": "web-search___WebSearch", "inputSchema": {"type": "object", "properties": {
    "maxResults": {"type": "integer"}, "query": {"type": "string"},
    "filters": {"type": "object", "properties": {
        "domainFilter": {"type": "object", "properties": {
            "include": {"type": "array", "items": {"type": "string"}},
            "exclude": {"type": "array", "items": {"type": "string"}}}},
        "publishedDateFilter": {"type": "object", "properties": {
            "from": {"type": "string"}, "to": {"type": "string"}}}}}}}}
reset(tool=live)
p = run(["q", "--include", "docs.aws.amazon.com", "--exclude", "spam.example", "--since", "2026-01-01"])
args = (STATE["requests"][-1]["msg"].get("params") or {}).get("arguments", {}) if STATE["requests"] else {}
check("live 1.2.0 schema: nested domainFilter and publishedDateFilter mapped",
      p.returncode == 0 and args.get("filters") == {
          "domainFilter": {"include": ["docs.aws.amazon.com"], "exclude": ["spam.example"]},
          "publishedDateFilter": {"from": "2026-01-01"}}, (p.returncode, p.stderr, args))
amb = {"name": "web-search___WebSearch", "inputSchema": {"type": "object", "properties": {
    "includeDomains": {"type": "array"}, "includeSites": {"type": "array"},
    "excludeDomains": {"type": "array"}, "startDate": {"type": "string"}}}}
reset(tool=amb)
p = run(["q"])
check("ambiguous filter names -> exit 6", p.returncode == 6 and "ambiguous" in p.stderr, p.stderr)
reset(tool={"name": "other___Thing", "inputSchema": {}})
p = run(["q"])
check("no web-search tool listed -> exit 6", p.returncode == 6, p.stderr)
reset(tool={"name": "gw___websearch"})
p = run(["q"])
check("tool without inputSchema -> exit 6", p.returncode == 6, p.stderr)
reset(list_raw="not json at all")
p = run(["q"])
check("non-JSON body -> exit 6", p.returncode == 6, p.stderr)
reset(list_raw='{"jsonrpc":"2.0","id":1}')
p = run(["q"])
check("JSON-RPC without result -> exit 6", p.returncode == 6, p.stderr)
reset(list_raw='[1]')
p = run(["q"])
check("JSON-RPC non-object -> exit 6", p.returncode == 6, p.stderr)
reset(list_raw='{"jsonrpc":"2.0","id":1,"result":{"tools":"x"}}')
p = run(["q"])
check("tools not an array -> exit 6", p.returncode == 6, p.stderr)

# ---- HTTP status mapping ---------------------------------------------------
reset(status={"tools/list": 401})
p = run(["q"])
check("401 -> exit 3 with the sso login instruction",
      p.returncode == 3 and "sign in for that profile" in p.stderr, p.stderr)
reset(status={"tools/list": 403}, error_body="ExpiredTokenException: The security token included in the request is expired")
p = run(["q"])
check("403 expired token -> exit 3", p.returncode == 3, p.stderr)
reset(status={"tools/list": 403}, error_body='{"message":"User: arn:aws:sts::123456789012:assumed-role/X/y is not '
      'authorized to perform: bedrock-agentcore:InvokeGateway on resource: '
      'arn:aws:bedrock-agentcore:us-east-1:123456789012:gateway/devagent-search"}')
p = run(["q"])
check("403 -> exit 4 naming the action and an ARN",
      p.returncode == 4 and "bedrock-agentcore:InvokeGateway" in p.stderr and "arn:aws:" in p.stderr, p.stderr)
reset(status={"tools/list": 403}, error_body="nope")
p = run(["q"])
check("403 without detail -> exit 4", p.returncode == 4, p.stderr)
reset(status={"tools/list": 429})
p = run(["q"])
check("429 persistent -> exit 5 after backoff", p.returncode == 5, p.stderr)
check("... 1 attempt + 2 retries", len(STATE["requests"]) == 3, len(STATE["requests"]))
reset(status={"tools/call": [429, 429]})
p = run(["q"])
check("429 twice then success -> exit 0", p.returncode == 0, p.stderr)
reset(status={"tools/list": 500}, error_body="ECHO")
p = run(["q"])
check("500 -> exit 6", p.returncode == 6, p.stderr)
check("500 body echoing request headers is redacted",
      FAKE_SECRET not in p.stderr and FAKE_TOKEN not in p.stderr and "Signature=[REDACTED]" in p.stderr, p.stderr)
reset(error={"code": -32000, "message": "ThrottlingException: Rate exceeded"})
p = run(["q"])
check("JSON-RPC throttling error -> exit 5", p.returncode == 5, p.stderr)
reset(error={"code": -32000, "message": "AccessDeniedException"})
p = run(["q"])
check("JSON-RPC access denied -> exit 4", p.returncode == 4, p.stderr)
reset(error={"code": -32600, "message": "bad"})
p = run(["q"])
check("JSON-RPC other error -> exit 6", p.returncode == 6, p.stderr)
reset(call_body={"isError": True, "content": [{"type": "text", "text": "upstream broke"}]})
p = run(["q"])
check("tools/call isError -> exit 6", p.returncode == 6, p.stderr)
reset(call_body={"content": [{"type": "text", "text": "[]"}]})
p = run(["q"])
check("results not an array -> exit 6", p.returncode == 6, p.stderr)
reset(call_body={"content": []})
p = run(["q"])
check("no text content -> exit 6", p.returncode == 6, p.stderr)
reset(call_body={"content": [{"type": "text", "text": json.dumps({"results": ["junk", {"url": "u"}]})}]})
p = run(["q", "--json"])
check("non-object result rows skipped", p.returncode == 0 and len(json.loads(p.stdout)["results"]) == 1, p.stdout)
reset()
p = run(["q"], env={"DEVAGENT_WEBSEARCH_URL": "http://127.0.0.1:1/mcp"})
check("unreachable endpoint -> exit 6", p.returncode == 6, p.stderr)
rec = json.loads(AUDIT.read_text().splitlines()[-1])
check("failed call is audited with its exit code and no urls", rec.get("exit") == 6 and rec.get("urls") == [], rec)

# ---- endpoint configuration ------------------------------------------------
cfg = HOME / ".config" / "devagent" / "web-search.json"
p = run(["q"], drop=("DEVAGENT_WEBSEARCH_URL",))
check("missing config -> exit 7 (not configured), with setup instructions",
      p.returncode == 7 and "not configured" in p.stderr and "terraform output" in p.stderr
      and "search_gateway_url" in p.stderr and STATE["requests"] == [], p.stderr)
cfg.parent.mkdir(parents=True)
cfg.write_text(json.dumps({"url": URL}))
cfg.chmod(0o644)
reset()
p = run(["q"], drop=("DEVAGENT_WEBSEARCH_URL",))
check("config with mode 644 refused (exit 3, no request)",
      p.returncode == 3 and "refusing" in p.stderr and STATE["requests"] == [], p.stderr)
cfg.chmod(0o600)
reset()
p = run(["q"], drop=("DEVAGENT_WEBSEARCH_URL",))
check("config with mode 600 accepted", p.returncode == 0, p.stderr)
cfg.write_text("{not json")
p = run(["q"], drop=("DEVAGENT_WEBSEARCH_URL",))
check("malformed config -> exit 3", p.returncode == 3, p.stderr)
cfg.unlink()
reset()
p = run(["q"], drop=("DEVAGENT_WEBSEARCH_TEST_ALLOW_HTTP",))
check("plain http refused without the explicit test flag", p.returncode == 3 and "https" in p.stderr
      and STATE["requests"] == [], p.stderr)
p = run(["q"], env={"DEVAGENT_WEBSEARCH_URL": "http://example.com/mcp"})
check("plain http to a non-loopback host refused even with the test flag", p.returncode == 3, p.stderr)
try:
    os.environ["DEVAGENT_WEBSEARCH_URL"] = "https://gw.example/mcp"
    check("https endpoint accepted by the URL check", ws.endpoint(HOME) == "https://gw.example/mcp")
finally:
    del os.environ["DEVAGENT_WEBSEARCH_URL"]
check("TLS context verifies certificates", ws._context().verify_mode == 2)

# ---- credentials -----------------------------------------------------------
reset()
p = run(["q"], env={"FAKE_AWS_FAIL": "1"})
check("credential export failure -> exit 3 with the sso login instruction",
      p.returncode == 3 and "sign in for that profile" in p.stderr and STATE["requests"] == [], p.stderr)
p = run(["q"], env={"PATH": "/nonexistent-bin:/usr/bin:/bin"})
check("AWS CLI missing -> exit 3", p.returncode == 3, p.stderr)

# ---- budget ----------------------------------------------------------------
bfile = WORK / "budget"
benv = {"DEVAGENT_SEARCH_BUDGET_FILE": str(bfile), "DEVAGENT_SEARCH_BUDGET": "2"}
reset()
codes = [run(["q"], env=benv).returncode for _ in range(3)]
check("budget of 2: third query exits 2", codes == [0, 0, 2], codes)
check("... and the third sent no request", len(STATE["requests"]) == 4)
p = run(["q"], env={"DEVAGENT_SEARCH_BUDGET_FILE": str(bfile), "DEVAGENT_SEARCH_BUDGET": "many"})
check("budget file without an integer limit -> exit 2", p.returncode == 2, p.stderr)
bfile.write_text("garbage")
p = run(["q"], env=benv)
check("corrupt budget file -> exit 2", p.returncode == 2, p.stderr)
p = run(["q"], env={"DEVAGENT_SEARCH_BUDGET_FILE": str(WORK / "no" / "dir" / "b"), "DEVAGENT_SEARCH_BUDGET": "3"})
check("unopenable budget file -> exit 2", p.returncode == 2, p.stderr)

# ---- usage -----------------------------------------------------------------
for argv, name in [(["q", "--max", "0"], "--max 0"), (["q", "--since", "2026-13-01"], "impossible date"),
                   (["q", "--since", "01/02/2026"], "wrong date format"),
                   (["q", "--include", "https://x.example/"], "domain with scheme"),
                   (["   "], "empty query"), (["x" * 201], "query over 200 chars"), ([], "no query")]:
    reset()
    p = run(argv)
    check(f"usage: {name} -> exit 2 with no request", p.returncode == 2 and STATE["requests"] == [], p.stderr)

# ---- credentials never leak ------------------------------------------------
blob = "\n".join(ALL_OUT) + (AUDIT.read_text() if AUDIT.exists() else "")
check("fake secret, session token and access key id never in stdout/stderr/audit",
      FAKE_SECRET not in blob and FAKE_TOKEN not in blob and FAKE_KEY not in blob)

srv.shutdown()
print(f"\n{PASSED} passed, {FAILED} failed")
sys.exit(1 if FAILED else 0)
PY

export SUBJECT WORK
if [ "${COVERAGE:-0}" = "1" ]; then
  cat >"$WORK/.coveragerc" <<EOF
[run]
branch = True
parallel = True
include = $SUBJECT
data_file = $WORK/.coverage
EOF
  export COVERAGE_RCFILE="$WORK/.coveragerc" COVERAGE_FILE="$WORK/.coverage"
  uv run --no-project --with 'coverage==7.16.2' python -m coverage run -p "$WORK/driver.py"
  rc=$?
  uv run --no-project --with 'coverage==7.16.2' python -m coverage combine -q
  uv run --no-project --with 'coverage==7.16.2' python -m coverage report -m
  exit $rc
fi
python3 "$WORK/driver.py"
