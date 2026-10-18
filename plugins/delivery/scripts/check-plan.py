#!/usr/bin/env python3
"""Check a `delivery` plan folder against the `delivery-plan/1` grammar.

    check-plan.py <feature-dir>          check one folder (docs/plans/<feature>)
    check-plan.py --all                  check every folder under docs/plans/
    check-plan.py --hook PATH            PostToolUse mode: silent unless PATH is
                                         inside docs/plans/<feature>/ and that
                                         folder fails
    check-plan.py --flags <feature-dir> | --flags --all [--today YYYY-MM-DD]
                                         report each feature flag (read-only)

The grammar and the rule list are normative in docs/plans/delivery/02-design.md
section 5 (sections 5.1 to 5.6), plus rule `flag-plan` from
docs/plans/feature-flags/02-design.md section 1.2. One extension comes from 05-implementation.md:
tasks named in its front-matter `manual_evidence: [...]` may carry evidence that
begins `manual` (written by hand before run-verify existed).

Output: one line per failure, `file:line: [rule] message`. Exit 0 when clean,
1 on any failure. In --hook mode a failure prints the same lines to stderr and
exits 2, which is how a Claude Code PostToolUse hook hands text back to the
model; a pass, or a path outside docs/plans/, prints nothing and exits 0.

--flags (feature-flags 02 section 1.3) runs every check on each folder first.
A failing folder prints `<feature>: plan fails check-plan.py; flags not
reported`; a passing one prints one line per flag,
`<feature>: flag <name> · added <state> · owner <role> · remove by <date> ·
<status>[ · beyond a year]`, or `<feature>: no flags`. <status> is the first of
removed · inconsistent · overdue · live that applies; `--today` fixes the report
date (default: the local date). Exit 0 when every folder reported, 1 when any
failed its checks, 2 on a usage error (bad --today, unknown option, --flags with
--hook).

Plan files are untrusted data. Nothing read from them is executed: the only
subprocess is `git log`, with task file paths passed as pathspecs after `--`.
Every printed line passes `sanitise` (02 section 1.4 of the feature-flags plan):
control, format and line/paragraph-separator characters become `?`, and a
message is capped at 300 code points, so plan text cannot forge a second
`file:line: [rule]` line or reach the terminal as an escape sequence.

Python 3.11+ standard library only.
"""

from __future__ import annotations

import argparse
import hashlib
import re
import subprocess
import sys
import unicodedata
from dataclasses import dataclass, field
from datetime import date
from pathlib import Path
from urllib.parse import urlsplit

FORMAT = "delivery-plan/1"
STATUSES = frozenset({"draft", "approved", "reviewed", "complete", "as-built", "superseded"})
STEPS = ("01-requirements", "02-design", "03-research", "04-review", "05-implementation")
COMMON_KEYS = ("format", "feature", "step", "status", "date", "generator")
STEP_KEYS = {
    "01-requirements": ("tier", "ai_use"),
    "02-design": ("tier", "personal_data", "calls_model", "has_ui"),
    "04-review": ("classification",),
    "05-implementation": ("branch", "base", "verify_allowed"),
}
REQUIREMENTS_SECTIONS = ("Data handled", "Client constraints")

# Hosts accepted as the source of a 🔄 (changed) or ⛔ (wrong) research row
# (DESIGN §5.3). A host matches itself and its subdomains. A non-None value
# further restricts the URL path (github.com: releases and changelogs only).
OFFICIAL_DOMAINS: dict[str, re.Pattern[str] | None] = {
    "docs.aws.amazon.com": None,
    "aws.amazon.com": None,
    "code.claude.com": None,
    "docs.anthropic.com": None,
    "anthropic.com": None,
    "registry.terraform.io": None,
    "developer.hashicorp.com": None,
    "releases.hashicorp.com": None,
    "nodejs.org": None,
    "python.org": None,
    "docs.python.org": None,
    "github.com": re.compile(r"/releases(/|$)|changelog", re.IGNORECASE),
    "pypi.org": None,
    "npmjs.com": None,
}

SHELL_METACHARS = frozenset(";|&$`><")
RESEARCH_STATUS = frozenset({"✅", "🔄", "⛔", "✨", "❓"})
RESEARCH_COLUMNS = ("#", "Status", "Official source", "Checked", "Engine")
ENGINES = frozenset({"web-search", "official-page", "manual"})
TASK_FIELDS = ("depends", "files", "acceptance", "verify", "timeout")
IN_PROGRESS_FIELDS = ("owner", "session", "started", "worktree")
DENY_LIST = Path(".delivery") / "deny-list"
UNSAFE_CATEGORIES = frozenset({"Cc", "Cf", "Zl", "Zp"})
MESSAGE_LIMIT = 300  # code points
FIELD_LIMIT = 80  # code points, for each owner and date in the --flags report
# Feature flags (feature-flags 02 §1.1, §1.2): keys read from raw task lines.
FLAG_KEYS = ("flag", "flag_owner", "remove_by", "flag on", "flag off")
FLAG_VERBS = ("add", "remove")
FLAG_NAME = re.compile(r"^[a-z0-9][a-z0-9._-]{0,62}$")

ANY_ID = re.compile(r"\b([AXRCTD])-(\d+)\b")
DATE = re.compile(r"^\d{4}-\d{2}-\d{2}$")
GENERATOR = re.compile(r"^delivery@\S+$")
FENCE = re.compile(r"^\s*(```|~~~)")
HEADING = re.compile(r"^(#{1,6})\s+(.*?)\s*$")
BULLET = re.compile(r"^- ([a-z][a-z _]*):\s*(.*)$")
SEPARATOR_CELL = re.compile(r"^:?-{3,}:?$")
TASK_HEAD = re.compile(r"^### (T-\d+) \[(.)\] (\S.*)$")
REVIEW_HEAD = re.compile(r"^### (R-\d+) · (critical|high|medium|low)\b.* · \d+/\d+")
CHANGE_SOURCE = re.compile(r"^(operator|render check|research [AX]-\d+|R-\d+|T-\d+)$")
RUN_VERIFY = re.compile(
    r"^run-verify · exit (\d+) · tests (\d+) · (\S+) · "
    r"log (evidence/\S+) sha256:([0-9a-f]{64}) · (\d{4}-\d{2}-\d{2})$"
)
OUTCOME_APPLIED = re.compile(r"^applied → (C-\d+)\b")
OUTCOME_REJECTED = re.compile(r"^rejected — \S")
OUTCOME_ACCEPTED = re.compile(r"^accepted risk — owner [^,]+, \S")
OUTCOME_DECISION = re.compile(r"^needs-decision — (D-\d+)\b")


@dataclass(frozen=True)
class Failure:
    rule: str
    path: Path
    line: int
    message: str

    def render(self) -> str:
        return f"{sanitise(display(self.path))}:{self.line}: [{self.rule}] {sanitise(self.message)}"


def sanitise(text: str, limit: int = MESSAGE_LIMIT) -> str:
    """Make untrusted text safe to print as part of one output line.

    Unicode Cc, Cf, Zl and Zp characters (newline, ESC, U+202E and the like)
    become `?`; text over `limit` code points is cut to one fewer plus `…`.
    """
    clean = "".join("?" if unicodedata.category(ch) in UNSAFE_CATEGORIES else ch for ch in text)
    if len(clean) > limit:
        clean = clean[: limit - 1] + "…"
    return clean


def display(path: Path) -> str:
    try:
        return str(path.resolve().relative_to(Path.cwd().resolve()))
    except ValueError:
        return str(path)


@dataclass
class Table:
    heading: str
    line: int
    header: list[str]
    rows: list[tuple[int, list[str]]]


@dataclass
class Doc:
    path: Path
    lines: list[str]
    fm: dict[str, str | list[str]] | None
    fm_line: dict[str, int]
    body: list[tuple[int, str]]  # (1-based line number, text), outside code fences
    tables: list[Table] = field(default_factory=list)

    @property
    def step(self) -> str:
        value = (self.fm or {}).get("step", "")
        return value if isinstance(value, str) else ""


# --------------------------------------------------------------------------
# Parsing
# --------------------------------------------------------------------------


def strip_comment(value: str) -> str:
    return re.sub(r"\s+#.*$", "", value).strip()


def parse_front_matter(lines: list[str]) -> tuple[dict, dict, int]:
    """Return (keys, key line numbers, index of the first body line)."""
    if not lines or lines[0].strip() != "---":
        return {}, {}, -1
    try:
        end = next(i for i in range(1, len(lines)) if lines[i].strip() == "---")
    except StopIteration:
        return {}, {}, -1
    fm: dict[str, str | list[str]] = {}
    where: dict[str, int] = {}
    key = None
    for i in range(1, end):
        line = lines[i]
        m = re.match(r"^([A-Za-z_][\w-]*):\s*(.*)$", line)
        if m:
            key, value = m.group(1), strip_comment(m.group(2))
            where[key] = i + 1
            if value.startswith("[") and value.endswith("]"):
                fm[key] = [v.strip() for v in value[1:-1].split(",") if v.strip()]
            elif value == "":
                fm[key] = []
            else:
                fm[key] = value
            continue
        item = re.match(r"^\s+-\s+(.*)$", line)
        if item and key is not None and isinstance(fm.get(key), list):
            fm[key].append(strip_comment(item.group(1)))
    return fm, where, end + 1


def split_cells(row: str) -> list[str]:
    row = row.strip()
    if row.startswith("|"):
        row = row[1:]
    if row.endswith("|") and not row.endswith("\\|"):
        row = row[:-1]
    return [c.strip().replace("\\|", "|") for c in re.split(r"(?<!\\)\|", row)]


def load(path: Path) -> Doc:
    lines = path.read_text(encoding="utf-8").splitlines()
    fm, where, start = parse_front_matter(lines)
    body: list[tuple[int, str]] = []
    fenced = False
    for i in range(max(start, 0), len(lines)):
        if FENCE.match(lines[i]):
            fenced = not fenced
            continue
        if not fenced:
            body.append((i + 1, lines[i]))
    doc = Doc(path, lines, fm if start >= 0 else None, where, body)
    doc.tables = parse_tables(doc.body)
    return doc


def parse_tables(body: list[tuple[int, str]]) -> list[Table]:
    tables: list[Table] = []
    heading = ""
    block: list[tuple[int, str]] = []
    prev = None

    def close() -> None:
        if not block:
            return
        rows = [(n, split_cells(t)) for n, t in block]
        sep = len(rows) > 1 and all(SEPARATOR_CELL.match(c) for c in rows[1][1])
        tables.append(Table(heading, block[0][0], rows[0][1], rows[2:] if sep else []))
        if not sep:
            tables[-1].header = []  # marks a table without its separator row
        block.clear()

    for n, text in body:
        if text.lstrip().startswith("|") and (prev is None or prev == n - 1):
            block.append((n, text))
            prev = n
            continue
        close()
        prev = None
        if text.lstrip().startswith("|"):
            block.append((n, text))
            prev = n
            continue
        h = HEADING.match(text)
        if h:
            heading = h.group(2)
    close()
    return tables


def sections(doc: Doc, pattern: re.Pattern[str]) -> list[tuple[int, re.Match, list[tuple[int, str]]]]:
    """Blocks that start at a heading matching `pattern` and run to the next heading."""
    out = []
    current = None
    for n, text in doc.body:
        if HEADING.match(text):
            m = pattern.match(text)
            current = (n, m, []) if m else None
            if current:
                out.append(current)
            continue
        if current:
            current[2].append((n, text))
    return out


def bullets(block: list[tuple[int, str]]) -> dict[str, tuple[int, str]]:
    """`- key: value` bullets; `owner` lines may carry `k: v · k: v` sub-fields."""
    found: dict[str, tuple[int, str]] = {}
    for n, text in block:
        m = BULLET.match(text)
        if not m:
            continue
        key, value = m.group(1), m.group(2).strip()
        found.setdefault(key, (n, value))
        if key == "owner":
            parts = value.split(" · ")
            found["owner"] = (n, parts[0].strip())
            for part in parts[1:]:
                sub = re.match(r"^([a-z_]+):\s*(.*)$", part.strip())
                if sub:
                    found.setdefault(sub.group(1), (n, sub.group(2).strip()))
    return found


def find_root(start: Path) -> Path | None:
    for d in [start, *start.parents]:
        if (d / ".git").exists() or (d / ".delivery").is_dir():
            return d
    return None


def load_deny_list(root: Path | None) -> list[str] | None:
    if root is None or not (root / DENY_LIST).is_file():
        return None
    terms = []
    for raw in (root / DENY_LIST).read_text(encoding="utf-8").splitlines():
        term = raw.strip()
        if term and not term.startswith("#"):
            terms.append(term.lower())
    return terms


# --------------------------------------------------------------------------
# Rules
# --------------------------------------------------------------------------


class Checker:
    def __init__(self, folder: Path, hook: bool = False) -> None:
        self.folder = folder
        self.hook = hook
        self.failures: list[Failure] = []
        self.root = find_root(folder.resolve())
        self.docs = [load(p) for p in sorted(folder.glob("0[1-5]-*.md"))]
        self.graphs: dict[Path, dict[str, list[str]]] = {}

    def fail(self, rule: str, path: Path, line: int, message: str) -> None:
        self.failures.append(Failure(rule, path, line, message))

    def by_step(self, step: str) -> list[Doc]:
        return [d for d in self.docs if d.step == step]

    def run(self) -> list[Failure]:
        if not self.docs:
            self.fail("front-matter", self.folder, 0, "no plan files (01-*.md to 05-*.md) in folder")
            return self.failures
        for doc in self.docs:
            self.front_matter(doc)
            self.table_separators(doc)
        self.ids()
        self.requirements()
        self.change_log()
        self.research()
        self.review()
        self.tasks()
        self.flag_plan()
        return self.failures

    # -- grammar ------------------------------------------------------------

    def front_matter(self, doc: Doc) -> None:
        p = doc.path
        if doc.fm is None:
            self.fail("front-matter", p, 1, "no front matter (--- ... ---) at top of file")
            return
        fm, at = doc.fm, doc.fm_line
        for key in COMMON_KEYS:
            if key not in fm:
                self.fail("front-matter", p, 1, f"missing front-matter key `{key}`")
        if "format" in fm and fm["format"] != FORMAT:
            self.fail("format", p, at["format"], f"format is `{fm['format']}`, expected `{FORMAT}`")
        if "status" in fm and fm["status"] not in STATUSES:
            self.fail("status", p, at["status"],
                      f"status `{fm['status']}` not in {' · '.join(sorted(STATUSES))}")
        if "date" in fm and not (isinstance(fm["date"], str) and DATE.match(fm["date"])):
            self.fail("front-matter", p, at["date"], "date is not YYYY-MM-DD")
        if "generator" in fm and not (isinstance(fm["generator"], str) and GENERATOR.match(fm["generator"])):
            self.fail("front-matter", p, at["generator"], "generator is not `delivery@<release-tag>`")
        step = doc.step
        if "step" in fm and step not in STEPS:
            self.fail("front-matter", p, at["step"], f"step `{fm['step']}` not in {', '.join(STEPS)}")
            return
        if not step:
            return
        if not p.name.startswith(step[:3]):
            self.fail("front-matter", p, at["step"], f"step `{step}` does not match file name")
        if step != "01-requirements":
            if "reads" not in fm:
                self.fail("front-matter", p, 1, "missing front-matter key `reads`")
            else:
                reads = fm["reads"]
                names = reads if isinstance(reads, list) else [r.strip() for r in reads.split(",")]
                for name in filter(None, names):
                    if not (self.folder / name).is_file():
                        self.fail("dangling-ref", p, at["reads"], f"reads `{name}`, which is not in this folder")
        for key in STEP_KEYS.get(step, ()):
            if key not in fm:
                self.fail("front-matter", p, 1, f"missing front-matter key `{key}` (required for {step})")
        if step == "05-implementation":
            allowed = fm.get("verify_allowed")
            if "verify_allowed" in fm and not (isinstance(allowed, list) and allowed):
                self.fail("front-matter", p, at["verify_allowed"], "verify_allowed must be a non-empty list")
            manual = fm.get("manual_evidence", [])
            if not isinstance(manual, list):
                self.fail("front-matter", p, at["manual_evidence"], "manual_evidence must be a list of T-nn")

    def table_separators(self, doc: Doc) -> None:
        for t in doc.tables:
            if not t.header:
                self.fail("table-separator", doc.path, t.line, "table has no |---| separator row after its header")

    def id_pattern(self, path: Path, line: int, ident: str) -> None:
        # Grammar DESIGN §5.2: T, R and C use two or more digits; A, X and D
        # may use one (assumptions and decisions were numbered before the
        # grammar existed, and renumbering them would break references).
        kind, digits = ident.split("-")
        if kind in ("T", "R", "C") and len(digits) < 2:
            self.fail("id-pattern", path, line, f"`{ident}` does not match `{kind}-nn` (two or more digits)")

    # -- IDs and references ------------------------------------------------

    def ids(self) -> None:
        self.defined: dict[str, set[str]] = {k: set() for k in "AXRCTD"}
        research_seen: dict[str, tuple[Path, int]] = {}
        for doc in self.docs:
            seen: dict[str, int] = {}

            def define(ident: str, n: int) -> None:
                self.id_pattern(doc.path, n, ident)
                if ident in seen:
                    self.fail("duplicate-id", doc.path, n, f"`{ident}` already defined at line {seen[ident]}")
                seen[ident] = n
                if doc.step == "03-research" and ident[0] in "AX":
                    other = research_seen.get(ident)
                    if other and other[0] != doc.path:
                        self.fail("duplicate-id", doc.path, n,
                                  f"`{ident}` already defined in {other[0].name}:{other[1]}")
                    research_seen.setdefault(ident, (doc.path, n))
                self.defined[ident[0]].add(ident)

            for t in doc.tables:
                for n, cells in t.rows:
                    if cells and re.fullmatch(r"[AXRCTD]-\d+", cells[0]):
                        define(cells[0], n)
            head = {"04-review": "R", "05-implementation": "T"}.get(doc.step)
            if head:
                for n, text in doc.body:
                    m = re.match(rf"^### ({head}-\d+)\b", text)
                    if m:
                        define(m.group(1), n)
        self.research_ids = {c[0] for d in self.by_step("03-research") for t in d.tables
                             for _, c in t.rows if c and re.fullmatch(r"[AX]-\d+", c[0])}
        self.change_ids = {c[0] for d in self.by_step("02-design") for t in d.tables
                           if t.heading.lower().startswith("change log") for _, c in t.rows
                           if c and re.fullmatch(r"C-\d+", c[0])}

    def change_log(self) -> None:
        for doc in self.by_step("02-design"):
            for t in doc.tables:
                if not t.heading.lower().startswith("change log"):
                    continue
                if "Source" not in t.header:
                    self.fail("change-source", doc.path, t.line, "change log has no `Source` column")
                    continue
                col = t.header.index("Source")
                for n, cells in t.rows:
                    source = cells[col] if col < len(cells) else ""
                    for item in [s.strip() for s in source.split(",")]:
                        if not CHANGE_SOURCE.match(item):
                            self.fail("change-source", doc.path, n,
                                      f"source `{item}` not in operator · research A-nn · research X-nn · "
                                      "R-nn · render check · T-nn")
                            continue
                        m = ANY_ID.search(item)
                        if not m:
                            continue
                        ident = m.group(0)
                        self.id_pattern(doc.path, n, ident)
                        pool = self.research_ids if ident[0] in "AX" else self.defined[ident[0]]
                        if ident not in pool:
                            where = {"A": "03", "X": "03", "R": "04", "T": "05"}[ident[0]]
                            self.fail("dangling-ref", doc.path, n, f"source `{ident}` is not defined in {where}")

    # -- 01 requirements ----------------------------------------------------

    def requirements(self) -> None:
        # brainstorm must answer both before design starts; `none stated` is an
        # answer, a missing or empty section is the silent gap it forbids.
        for doc in self.by_step("01-requirements"):
            for title in REQUIREMENTS_SECTIONS:
                found = sections(doc, re.compile(rf"^## {re.escape(title)}\s*$"))
                if not found:
                    self.fail("requirements-sections", doc.path, 1,
                              f"no `## {title}` section - answer it, or write `none stated`")
                    continue
                n, _, block = found[0]
                text = re.sub(r"<!--.*?-->", "", "\n".join(t for _, t in block), flags=re.S)
                if not text.strip():
                    self.fail("requirements-sections", doc.path, n,
                              f"`## {title}` is empty - answer it, or write `none stated`")

    # -- 03 research --------------------------------------------------------

    def research(self) -> None:
        deny = load_deny_list(self.root)
        for doc in self.by_step("03-research"):
            for t in doc.tables:
                if not any(c and re.fullmatch(r"[AX]-\d+", c[0]) for _, c in t.rows):
                    continue
                missing = [c for c in RESEARCH_COLUMNS if c not in t.header]
                if missing:
                    self.fail("research-grammar", doc.path, t.line,
                              f"research table lacks column(s): {', '.join(missing)}")
                col = {name: t.header.index(name) for name in RESEARCH_COLUMNS if name in t.header}

                def cell(cells: list[str], name: str) -> str | None:
                    i = col.get(name)
                    return cells[i] if i is not None and i < len(cells) else None

                for n, cells in t.rows:
                    status = (cell(cells, "Status") or "").replace("\ufe0f", "").strip()
                    if "Status" in col and status not in RESEARCH_STATUS:
                        self.fail("research-grammar", doc.path, n,
                                  f"status `{status}` not one of {' '.join(sorted(RESEARCH_STATUS))}")
                    engine = cell(cells, "Engine")
                    if engine is not None and engine not in ENGINES:
                        self.fail("research-grammar", doc.path, n,
                                  f"engine `{engine}` not in {' · '.join(sorted(ENGINES))}")
                    checked = cell(cells, "Checked")
                    if checked is not None and not DATE.match(checked):
                        self.fail("research-grammar", doc.path, n, "Checked is not YYYY-MM-DD")
                    source = cell(cells, "Official source")
                    if source is not None:
                        self.sources(doc.path, n, status, source)
            self.queries(doc, deny)

    def sources(self, path: Path, n: int, status: str, source: str) -> None:
        urls = []
        for part in [p.strip() for p in source.split(" · ")]:
            if part.startswith("https://") and " " not in part:
                urls.append(part)
            elif not part.startswith("live: "):
                self.fail("research-grammar", path, n,
                          f"source part `{part[:60]}` is neither an https:// URL nor `live: <command>`")
        if not ("🔄" in status or "⛔" in status):
            return
        if not urls:
            self.fail("source-allowlist", path, n, "🔄/⛔ row cites no official https:// URL")
        for url in urls:
            if not on_allowlist(url):
                self.fail("source-allowlist", path, n, f"🔄/⛔ source `{url}` is not on the official-domain allowlist")

    def queries(self, doc: Doc, deny: list[str] | None) -> None:
        blocks = sections(doc, re.compile(r"^## Queries sent\s*$"))
        if not blocks:
            self.fail("research-grammar", doc.path, 1, "no `## Queries sent` section")
            return
        if deny is None:
            return
        for _, _, block in blocks:
            for n, text in block:
                m = re.match(r"^\s*(?:[-*]|\d+\.)\s+(.*)$", text)
                if not m:
                    continue
                query = m.group(1).lower()
                for k, term in enumerate(deny, 1):
                    if term in query:
                        # Name the term by its position, never echo it: the
                        # deny-list is itself engagement-confidential.
                        self.fail("deny-list", doc.path, n, f"recorded query matches deny-list term #{k}")

    # -- 04 review ----------------------------------------------------------

    def review(self) -> None:
        has_05 = bool(self.by_step("05-implementation"))
        for doc in self.by_step("04-review"):
            for n, text in doc.body:
                if text.startswith("### R-") and not REVIEW_HEAD.match(text):
                    self.fail("review-grammar", doc.path, n,
                              "finding heading is not `### R-nn · <severity> · k/n (lenses)`")
            for n, m, block in sections(doc, re.compile(r"^### (R-\d+)\b")):
                rid = m.group(1)
                found = bullets(block)
                if "outcome" not in found or not found["outcome"][1]:
                    self.fail("review-outcome", doc.path, n, f"{rid} has no `- outcome:`")
                    continue
                line, outcome = found["outcome"]
                if (a := OUTCOME_APPLIED.match(outcome)):
                    cid = a.group(1)
                    self.id_pattern(doc.path, line, cid)
                    if cid not in self.change_ids:
                        self.fail("applied-change", doc.path, line, f"{rid} applied → {cid}, not in the 02 change log")
                elif (d := OUTCOME_DECISION.match(outcome)):
                    if d.group(1) not in self.defined["D"]:
                        self.fail("dangling-ref", doc.path, line, f"{rid} needs {d.group(1)}, which is not defined")
                    if has_05:
                        self.fail("needs-decision", doc.path, line,
                                  f"{rid} is still needs-decision but 05-implementation exists")
                elif not (OUTCOME_REJECTED.match(outcome) or OUTCOME_ACCEPTED.match(outcome)):
                    self.fail("review-outcome", doc.path, line,
                              f"{rid} outcome is not `applied → C-nn` · `rejected — <reason>` · "
                              "`accepted risk — owner <role>, <rationale>` · `needs-decision — D-n`")

    # -- 05 tasks -----------------------------------------------------------

    def tasks(self) -> None:
        for doc in self.by_step("05-implementation"):
            fm = doc.fm or {}
            allowed = fm.get("verify_allowed") if isinstance(fm.get("verify_allowed"), list) else []
            manual = fm.get("manual_evidence") if isinstance(fm.get("manual_evidence"), list) else []
            for n, text in doc.body:
                if text.startswith("### T-") and not TASK_HEAD.match(text):
                    self.fail("task-grammar", doc.path, n, "task heading is not `### T-nn [ |~|x|!] <title>`")
            graph: dict[str, list[str]] = {}
            heads: dict[str, int] = {}
            for n, m, block in sections(doc, TASK_HEAD):
                tid, state = m.group(1), m.group(2)
                heads.setdefault(tid, n)
                if state not in " ~x!":
                    self.fail("task-grammar", doc.path, n, f"{tid} state `[{state}]` not one of [ ] [~] [x] [!]")
                found = bullets(block)
                for key in TASK_FIELDS:
                    if key not in found:
                        self.fail("task-grammar", doc.path, n, f"{tid} has no `- {key}:`")
                graph[tid] = self.depends(doc, tid, found)
                if "timeout" in found and not re.fullmatch(r"\d+[smh]", found["timeout"][1]):
                    self.fail("task-grammar", doc.path, found["timeout"][0], f"{tid} timeout is not <n>s|m|h")
                if "verify" in found:
                    self.verify(doc, tid, found["verify"], allowed)
                if state == "x":
                    self.evidence(doc, tid, n, found, manual)
                elif state == "~":
                    missing = [k for k in IN_PROGRESS_FIELDS if not found.get(k, (0, ""))[1]]
                    if missing:
                        self.fail("in-progress-owner", doc.path, n, f"{tid} is [~] without {', '.join(missing)}")
                elif state == "!" and not found.get("reason", (0, ""))[1]:
                    self.fail("blocked-reason", doc.path, n, f"{tid} is [!] without a `- reason:`")
            self.graphs[doc.path] = graph
            for tid, deps in graph.items():
                for dep in deps:
                    if dep not in graph:
                        self.fail("dangling-ref", doc.path, heads[tid], f"{tid} depends on {dep}, which is not a task")
            for cycle in find_cycles(graph):
                self.fail("depends-cycle", doc.path, heads[cycle[0]], "depends cycle: " + " → ".join(cycle))

    def depends(self, doc: Doc, tid: str, found: dict) -> list[str]:
        if "depends" not in found:
            return []
        line, value = found["depends"]
        if value == "none":
            return []
        deps = [d.strip() for d in value.split(",")]
        bad = [d for d in deps if not re.fullmatch(r"T-\d+", d)]
        if bad:
            self.fail("task-grammar", doc.path, line, f"{tid} depends is not `none` or T-nn, T-nn")
        for d in deps:
            if d not in bad:
                self.id_pattern(doc.path, line, d)
        return [d for d in deps if d not in bad]

    def verify(self, doc: Doc, tid: str, found: tuple[int, str], allowed: list[str]) -> None:
        line, value = found
        command = value[1:-1] if len(value) > 1 and value.startswith("`") and value.endswith("`") else value
        if command not in allowed:
            self.fail("verify-allowlist", doc.path, line, f"{tid} verify `{command}` is not on verify_allowed")
        bad = sorted(SHELL_METACHARS & set(command))
        if bad:
            self.fail("verify-metachar", doc.path, line,
                      f"{tid} verify contains shell metacharacter(s) {' '.join(bad)}")

    def evidence(self, doc: Doc, tid: str, n: int, found: dict, manual: list[str]) -> None:
        if not found.get("evidence", (0, ""))[1]:
            self.fail("evidence", doc.path, n, f"{tid} is [x] without `- evidence:`")
            return
        line, value = found["evidence"]
        if value.startswith("manual") and tid in manual:
            pass
        elif value.startswith("manual"):
            self.fail("evidence", doc.path, line, f"{tid} has manual evidence but is not in manual_evidence")
        elif not (m := RUN_VERIFY.match(value)):
            self.fail("evidence", doc.path, line,
                      f"{tid} evidence is not `run-verify · exit 0 · tests N · <time> · "
                      "log evidence/T-nn.log sha256:<hex> · <date>`")
        else:
            exit_code, tests, _, log, digest, _ = m.groups()
            if exit_code != "0":
                self.fail("evidence", doc.path, line, f"{tid} evidence records exit {exit_code}")
            if int(tests) == 0:
                self.fail("evidence", doc.path, line, f"{tid} evidence records zero tests")
            if log != f"evidence/{tid}.log":
                self.fail("evidence", doc.path, line, f"{tid} evidence log is `{log}`, expected evidence/{tid}.log")
            path = self.folder / log
            if not path.is_file():
                self.fail("evidence-hash", doc.path, line, f"{tid} evidence log {log} does not exist")
            elif hashlib.sha256(path.read_bytes()).hexdigest() != digest:
                self.fail("evidence-hash", doc.path, line, f"{tid} evidence log {log} does not match its sha256")
        if not self.hook:  # the [x] edit precedes its commit, so the hook cannot see it yet
            self.commit(doc, tid, n, found)

    def commit(self, doc: Doc, tid: str, n: int, found: dict) -> None:
        files = [f.strip() for f in found.get("files", (0, ""))[1].split(",") if f.strip()]
        try:
            top = subprocess.run(["git", "-C", str(self.folder), "rev-parse", "--show-toplevel"],
                                 capture_output=True, text=True, timeout=20)
            if top.returncode != 0:
                return  # not in a repository: the rule applies "in a repo" only
            repo = Path(top.stdout.strip()).resolve()
            if self.folder.resolve().parent != repo / "docs" / "plans":
                return  # a plan folder copied elsewhere (a fixture): its task paths are not this repo's
            # A task's commit is the one that touches its declared files OR its own
            # evidence log. The log matters for a verification-only task (say, "run
            # the suite on another interpreter"): it changes none of its files, but
            # its commit always carries run-verify's evidence.
            evidence = (self.folder.resolve() / "evidence" / f"{tid}.log").relative_to(repo)
            log = subprocess.run(["git", "-C", str(repo), "log", "--format=%s", "--", *files, str(evidence)],
                                 capture_output=True, text=True, timeout=20)
        except (OSError, subprocess.TimeoutExpired):
            return
        count = sum(1 for s in log.stdout.splitlines() if re.match(rf"^{re.escape(tid)}(?!\d)\b", s))
        if count != 1:
            self.fail("commit", doc.path, n, f"{tid} is [x] with {count} `{tid}` commits touching its files or its evidence log, expected 1")

    # -- feature flags (feature-flags 02 §1.2) -----------------------------

    def flagged_value(self, doc: Doc) -> bool | None:
        """The doc's `flagged` front-matter value: True, False, or None when absent."""
        fm = doc.fm or {}
        if "flagged" not in fm:
            return None
        value = fm["flagged"]
        if value in ("true", "false"):
            return value == "true"
        self.fail("flag-plan", doc.path, doc.fm_line["flagged"],
                  f"flagged is `{value if isinstance(value, str) else '[]'}`, expected `true` or `false`")
        return None

    def flag_plan(self) -> None:
        design = [v for v in map(self.flagged_value, self.by_step("02-design")) if v is not None]
        for doc in self.by_step("05-implementation"):
            own = self.flagged_value(doc)
            # Condition 6: 02 and 05 disagreeing on `flagged`.
            if own is not None and design and design[0] != own:
                self.fail("flag-plan", doc.path, doc.fm_line["flagged"],
                          f"flagged is `{str(own).lower()}` in 05 but `{str(design[0]).lower()}` in 02")
            flagged = own if own is not None else bool(design and design[0])
            self.flag_tasks(doc, flagged)

    def flag_tasks(self, doc: Doc, flagged: bool) -> None:
        p = doc.path
        heads: dict[str, int] = {}
        keys: dict[str, dict[str, tuple[int, str]]] = {}
        for n, m, block in sections(doc, TASK_HEAD):
            tid = m.group(1)
            if tid in heads:
                continue  # duplicate-id already names it
            heads[tid] = n
            keys[tid] = found = {}
            # Condition 1: a raw-line scan, because bullets() keeps only the first
            # occurrence of a key and folds `owner` sub-fields into the same map.
            for line, text in block:
                b = BULLET.match(text)
                if not b:
                    continue
                key, value = b.group(1), b.group(2).strip()
                if key == "owner":
                    for part in value.split(" · ")[1:]:
                        sub = re.match(r"^([a-z][a-z _]*):", part.strip())
                        if sub and sub.group(1) in FLAG_KEYS:
                            self.fail("flag-plan", p, line,
                                      f"{tid} carries `{sub.group(1)}` as an `owner` sub-field; "
                                      f"write it as its own `- {sub.group(1)}:` bullet")
                    continue
                if key not in FLAG_KEYS:
                    continue
                if key in found:
                    self.fail("flag-plan", p, line,
                              f"{tid} repeats `- {key}:` (first at line {found[key][0]})")
                    continue
                found[key] = (line, value)
        carriers = [tid for tid, found in keys.items() if found]
        if not flagged:
            # Condition 6: a flag bullet in an unflagged plan.
            for tid in carriers:
                first = min(line for line, _ in keys[tid].values())
                self.fail("flag-plan", p, first,
                          f"{tid} carries flag bullets but the plan is not `flagged: true`")
            return

        adds: dict[str, list[str]] = {}
        removes: dict[str, list[str]] = {}
        verbs: dict[str, tuple[str, str]] = {}  # tid -> (verb, name) for valid flag bullets
        for tid, found in keys.items():
            if "flag" not in found:
                continue
            line, value = found["flag"]
            verb, _, name = value.partition(" ")
            name = name.strip()
            if verb not in FLAG_VERBS:
                self.fail("flag-plan", p, line, f"{tid} flag verb `{verb}` is not `add` or `remove`")
            elif not FLAG_NAME.match(name):
                self.fail("flag-plan", p, line,
                          f"{tid} flag name `{name}` does not match {FLAG_NAME.pattern}")
            else:
                verbs[tid] = (verb, name)
                (adds if verb == "add" else removes).setdefault(name, []).append(tid)

        # Condition 2: pairing.
        if not any("flag" in found for found in keys.values()):
            self.fail("flag-plan", p, doc.fm_line.get("flagged", 1),
                      "the plan is flagged but no task carries `- flag: add|remove <name>`")
        for name in sorted(set(adds) | set(removes)):
            for kind, pool in (("add", adds), ("remove", removes)):
                tids = pool.get(name, [])
                if len(tids) != 1:
                    where = heads[tids[1]] if tids else heads[(adds.get(name) or removes[name])[0]]
                    have = f"{len(tids)} ({', '.join(tids)})" if tids else "none"
                    self.fail("flag-plan", p, where, f"flag `{name}` needs exactly one {kind} task, has {have}")
        for tid, found in keys.items():
            is_remove = verbs.get(tid, ("", ""))[0] == "remove"
            for key in ("flag_owner", "remove_by"):
                if key in found and not is_remove:
                    self.fail("flag-plan", p, found[key][0], f"{tid} has `- {key}:` but is not a remove task")
            if not is_remove:
                continue
            # Condition 3: remove task fields.
            if not found.get("flag_owner", (0, ""))[1]:
                self.fail("flag-plan", p, heads[tid], f"{tid} removes a flag without a `- flag_owner:` role")
            if "remove_by" not in found:
                self.fail("flag-plan", p, heads[tid], f"{tid} removes a flag without a `- remove_by:` date")
            elif not valid_date(found["remove_by"][1]):
                self.fail("flag-plan", p, found["remove_by"][0],
                          f"{tid} remove_by `{found['remove_by'][1]}` is not a real YYYY-MM-DD date")

        # Conditions 4 and 5: ordering and guarded tasks, per well-paired flag.
        graph = self.graphs.get(p, {})
        ancestors = {tid: reachable(graph, tid) for tid in heads}
        in_a = {t for tids in adds.values() for t in tids}
        in_r = {t for tids in removes.values() for t in tids}
        guarded: dict[str, list[str]] = {}
        for name in sorted(set(adds) & set(removes)):
            if len(adds[name]) != 1 or len(removes[name]) != 1:
                continue
            a_f, r_f = adds[name][0], removes[name][0]
            for tid in heads:
                if tid in in_a or tid in in_r:
                    continue
                if tid not in ancestors[a_f] and a_f not in ancestors[tid]:
                    self.fail("flag-plan", p, heads[tid],
                              f"{tid} is unordered against {a_f}, which adds flag `{name}`: "
                              f"make it a prerequisite of {a_f} or depend on it")
            for tid in heads:
                if tid not in in_r and tid not in ancestors[r_f]:
                    self.fail("flag-plan", p, heads[r_f],
                              f"{r_f} removes flag `{name}` but does not depend on {tid}")
            for tid in heads:
                if tid not in in_r and a_f in ancestors[tid]:
                    guarded.setdefault(tid, []).append(name)
        for tid, names in guarded.items():
            for key in ("flag on", "flag off"):
                if not keys[tid].get(key, (0, ""))[1]:
                    self.fail("flag-plan", p, heads[tid],
                              f"{tid} is guarded by flag {', '.join(f'`{n}`' for n in names)} "
                              f"but has no `- {key}:` check")


def valid_date(value: str) -> bool:
    """`YYYY-MM-DD` that is a real calendar date (fromisoformat alone also takes 20270131)."""
    if not DATE.match(value):
        return False
    try:
        date.fromisoformat(value)
    except ValueError:
        return False
    return True


def reachable(graph: dict[str, list[str]], start: str) -> set[str]:
    """Every task `start` depends on, transitively (cycle-safe)."""
    seen: set[str] = set()
    stack = list(graph.get(start, []))
    while stack:
        node = stack.pop()
        if node not in seen:
            seen.add(node)
            stack.extend(graph.get(node, []))
    return seen


def on_allowlist(url: str) -> bool:
    parts = urlsplit(url)
    host = (parts.hostname or "").lower()
    for domain, path_rule in OFFICIAL_DOMAINS.items():
        if host == domain or host.endswith("." + domain):
            return path_rule is None or bool(path_rule.search(parts.path))
    return False


def find_cycles(graph: dict[str, list[str]]) -> list[list[str]]:
    cycles: list[list[str]] = []
    state: dict[str, int] = {}
    stack: list[str] = []

    def visit(node: str) -> None:
        state[node] = 1
        stack.append(node)
        for dep in graph.get(node, []):
            if state.get(dep) == 1:
                cycles.append(stack[stack.index(dep):] + [dep])
            elif dep in graph and dep not in state:
                visit(dep)
        stack.pop()
        state[node] = 2

    for node in graph:
        if node not in state:
            visit(node)
    return cycles


# --------------------------------------------------------------------------
# Entry point
# --------------------------------------------------------------------------


def flag_report(folder: Path, today: date) -> tuple[list[str], bool]:
    """The --flags lines for one folder, and whether it passed every check."""
    feature = sanitise(folder.resolve().name)
    checker = Checker(folder)
    if checker.run():
        return [f"{feature}: plan fails check-plan.py; flags not reported"], False
    lines: list[str] = []
    # The folder passed, so flag-plan has already proven the shape: every flag
    # bullet is unrepeated, each name has exactly one add and one remove task,
    # and every remove task has a flag_owner and a real remove_by date.
    for doc in checker.by_step("05-implementation"):
        written = doc.fm.get("date") if doc.fm else None
        start = date.fromisoformat(written) if isinstance(written, str) and valid_date(written) else None
        tasks = {m.group(1): (m.group(2), bullets(block)) for _, m, block in sections(doc, TASK_HEAD)}
        adds: dict[str, str] = {}
        removes: dict[str, str] = {}
        for tid, (_, found) in tasks.items():
            verb, _, name = found.get("flag", (0, ""))[1].partition(" ")
            if verb in FLAG_VERBS:
                (adds if verb == "add" else removes)[name.strip()] = tid
        for name, a_f in adds.items():
            add_state = tasks[a_f][0]
            remove_state, found = tasks[removes[name]]
            owner = found["flag_owner"][1]
            remove_by = found["remove_by"][1]
            due = date.fromisoformat(remove_by)
            if remove_state == "x":
                status = "removed" if add_state == "x" else "inconsistent"
            else:
                status = "overdue" if due < today else "live"
            line = (f"{feature}: flag {name} · added [{add_state}] · owner {sanitise(owner, FIELD_LIMIT)} · "
                    f"remove by {sanitise(remove_by, FIELD_LIMIT)} · {status}")
            if start is not None and (due - start).days > 365:
                line += " · beyond a year"
            lines.append(line)
    return (lines or [f"{feature}: no flags"]), True


def hook_folder(path: str) -> Path | None:
    parts = Path(path).resolve().parts
    for i in range(len(parts) - 2):
        if parts[i] == "docs" and parts[i + 1] == "plans":
            folder = Path(*parts[: i + 3])
            return folder if folder.is_dir() else None
    return None


def main(argv: list[str] | None = None) -> int:
    ap = argparse.ArgumentParser(description="Check delivery-plan/1 plan folders.")
    ap.add_argument("folder", nargs="?", help="a feature folder, e.g. docs/plans/<feature>")
    ap.add_argument("--all", action="store_true", help="check every folder under docs/plans/")
    ap.add_argument("--hook", metavar="PATH", help="PostToolUse mode for an edited file PATH")
    ap.add_argument("--flags", action="store_true", help="report each feature flag instead of checking")
    ap.add_argument("--today", metavar="YYYY-MM-DD", help="the --flags report date (default: the local date)")
    args = ap.parse_args(argv)

    if args.flags and args.hook is not None:
        ap.error("--flags cannot be combined with --hook")
    if args.today is not None and not args.flags:
        ap.error("--today needs --flags")
    today = date.today()
    if args.today is not None:
        if not valid_date(args.today):
            ap.error("--today is not a real YYYY-MM-DD date")
        today = date.fromisoformat(args.today)

    if args.hook is not None:
        folder = hook_folder(args.hook)
        if folder is None:
            return 0
        failures = Checker(folder, hook=True).run()
        for f in failures:
            print(f.render(), file=sys.stderr)
        return 2 if failures else 0

    if args.all == bool(args.folder):
        ap.error("give exactly one of <feature-dir> or --all")
    if args.all:
        root = find_root(Path.cwd().resolve()) or Path.cwd()
        plans = root / "docs" / "plans"
        if not plans.is_dir():
            print(Failure("front-matter", plans, 0, "no docs/plans/ folder").render())
            return 1
        folders = sorted(p for p in plans.iterdir() if p.is_dir() and not p.name.startswith("."))
    else:
        folders = [Path(args.folder)]
        if not folders[0].is_dir():
            print(f"{sanitise(args.folder)}:0: [front-matter] not a folder")
            return 1
    if args.flags:
        passed = True
        for folder in folders:
            lines, ok = flag_report(folder, today)
            passed = passed and ok
            for line in lines:
                print(sanitise(line, len(line)))
        return 0 if passed else 1
    failures = [f for folder in folders for f in Checker(folder).run()]
    for f in failures:
        print(f.render())
    if not failures:
        # A count, so run-verify can tell a real check from one that saw nothing.
        n_docs = sum(len(list(folder.glob("0[1-5]-*.md"))) for folder in folders)
        print(f"checked {n_docs} documents in {len(folders)} plan folder(s): clean")
    return 1 if failures else 0


if __name__ == "__main__":
    sys.exit(main())
