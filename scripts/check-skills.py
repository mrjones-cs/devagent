#!/usr/bin/env python3
"""Check command for devagent. Standard library only, runs in ~0.1s.

    python3 scripts/check-skills.py

Catches the failure modes that loading a skill successfully will NOT catch:

  * a cross-reference to a file that does not exist, or exists but is not
    TRACKED, or resolves from the wrong base. All three have shipped: seven
    skills pointed at `_shared/owasp-top10.md` (relative to skills/ rather
    than to the skill's own directory), and CLAUDE.md plus incident-breach
    pointed at a global-config/README.md the repo never contained - which
    resolved on the author's machine only, to an untracked leftover.
    Existing here is not the bar; install.sh being able to reproduce it is.
  * a reference to a sibling skill that is not installed
  * a skill with no resident stub in CLAUDE.md, or a stub naming a skill that
    does not exist. The stub is the DETERMINISTIC trigger; skill description
    matching is probabilistic. A skill with no stub has lost half its wiring.
  * a stub that names a skill by its BARE name. Skills are invoked as
    `devagent-standards:<name>`, so a bare stub is not a usable name - it can
    only be resolved by falling back to description matching, which is the
    probabilistic half the stub exists to backstop. Six trigger-test agents
    hit this; three reported it unprompted.
  * frontmatter that is missing, malformed, or whose name does not match its
    directory
  * a thin description - the description is the entire trigger mechanism
  * a shipped plugin file that relies on a DESIGN section (`per DESIGN §3.2`,
    a bare `§3.4`). docs/ does not ship with the plugins, so the reference
    points at nothing at run time; `(DESIGN §n)` beside a stated rule is fine
  * a PROSE FIGURE that no longer matches reality - the skill count, the
    resident file's line and word count, and the derived token estimate are
    quoted in ~9 places across install.sh, README.md, build-pdf.py and
    config-architecture.md. Adding the eleventh skill staled nine of them and
    this checker reported clean throughout; they were caught only by rebuilding
    the PDF and reading it. Figures describing a PAST state are exempt when the
    sentence marks them as past (was/previously/then/at the time/historical).

Exit 0 = clean, 1 = findings.
"""

from __future__ import annotations

import json
import os
import re
import subprocess
import sys
from pathlib import Path

REPO = Path(__file__).resolve().parent.parent
PLUGIN = REPO / "plugins" / "devagent-standards"
SKILLS = PLUGIN / "skills"
DELIVERY = REPO / "plugins" / "delivery"
RESIDENT = REPO / "templates" / "CLAUDE.md"

MIN_DESC_CHARS = 120

# Deliberate exceptions to check_paths. Entries MUST be multi-segment to have
# any effect - single-segment names (`NOTES.md`, `RULES.md`, `CLAUDE.md`,
# `clients.local.md`) never reach here because PATH_RE does not match them.
# Every entry needs a stated reason, or this allowlist recreates the
# fitted-to-history problem it exists to avoid.
PATH_ALLOWLIST = {
}

# Allowed in PROSE only (README.md, config-architecture.md, install.sh,
# build-pdf.py) - never inside a SKILL.md, where the same string is a live
# pointer that has to resolve.
#
# This split is not tidiness. Putting `references/owasp-top10.md` in the global
# allowlist - so the docs could discuss the correct in-skill idiom - silently
# disabled the rule that catches the original 2026-08-21 bug, and the negative
# test caught it immediately. An allowlist entry is a hole; it must be no wider
# than the case that needs it.
DOC_PATH_ALLOWLIST = {
    # Key is the path WITHOUT the ~/.claude/ prefix - PATH_RE captures the
    # prefix separately, so a key including it would never match.
    "plugins/known_marketplaces.json":
        "Claude Code writes and owns this; install.sh must not touch it",
    "devagent-audit/search.jsonl":
        "written at runtime by the web-search script, not installed",
    ".git/delivery-build.lock":
        "the build lock, created at runtime inside a project's .git by build-lock",
    "devagent-audit/YYYY-MM.jsonl":
        "written at runtime by the devagent-guard hook, not installed - and "
        "a template name, not a real file",
    "references/owasp-top10.md":
        "the skill-relative form. Correct inside a SKILL.md and quoted as such "
        "in prose, but it does not resolve from the repo root",
    "_shared/owasp-top10.md":
        "names the 2026-08-21 bug path deliberately. It MUST NOT exist - if it "
        "ever resolves again, the bug is back",
}

findings: list[str] = []
notes: list[str] = []

# A backticked multi-segment relative path ending in .<ext>, with the prefix
# captured separately so the CORRECT form can be demanded, not just existence.
# Deliberately NOT limited to a known set of first segments - a first-segment
# allowlist is what let `claudedocs/global-config/README.md` ship dead.
# Single-segment names (`NOTES.md`, `RULES.md`) are out of scope by design:
# they are generic mentions, not paths, and checking them is all false
# positives.
PATH_RE = re.compile(r"`(\$\{CLAUDE_PLUGIN_ROOT\}/|~/\.claude/)?"
                     r"([A-Za-z0-9_.-]+(?:/[A-Za-z0-9_.-]+)+\.[A-Za-z0-9]+)`")


def fail(msg: str) -> None:
    findings.append(msg)


def parse_frontmatter(text: str) -> dict[str, str] | None:
    """Minimal frontmatter reader - avoids a yaml dependency."""
    if not text.startswith("---"):
        return None
    end = text.find("\n---", 3)
    if end == -1:
        return None
    out: dict[str, str] = {}
    key = None
    for line in text[3:end].splitlines():
        if not line.strip():
            continue
        m = re.match(r"^([A-Za-z_][A-Za-z0-9_-]*):\s*(.*)$", line)
        if m:
            key = m.group(1)
            out[key] = m.group(2).strip()
        elif key:  # folded continuation line
            out[key] += " " + line.strip()
    return out


def tracked_files() -> set[str]:
    """Repo-relative paths git knows about.

    The point of this check: a reference can resolve on the AUTHOR'S machine
    to an untracked leftover and be dead everywhere else. Existing here is not
    the bar; install.sh being able to reproduce it is.
    """
    try:
        out = subprocess.run(["git", "-C", str(REPO), "ls-files"],
                             capture_output=True, text=True, check=True).stdout
    except (OSError, subprocess.CalledProcessError):
        notes.append("git unavailable - skipped the tracked-ness check on paths")
        return set()
    return set(out.split())


# What install.sh places under ~/.claude/, dest -> repo-relative source.
# install.sh has no table to parse, so this declares it and installed_map()
# proves install.sh really names each pair - the two cannot drift silently.
INSTALLS = {
    "CLAUDE.md": "templates/CLAUDE.md",
    "claudedocs/notes-template.md": "templates/notes-template.md",
}


def installed_map() -> dict[str, str]:
    """dest-under-~/.claude -> repo-relative source, verified against install.sh."""
    try:
        sh = (REPO / "install.sh").read_text()
    except OSError:
        fail("cannot read install.sh - unable to verify ~/.claude/ references")
        return {}
    for dest, src in INSTALLS.items():
        if f"${{REPO}}/{src}" not in sh or f"${{CLAUDE_DIR}}/{dest}" not in sh:
            fail(f"install.sh no longer places ~/.claude/{dest} from {src} - "
                 f"update INSTALLS in check-skills.py or fix install.sh")
    return dict(INSTALLS)


def check_paths(label: str, text: str, own_dir: Path | None,
                tracked: set[str], installed: dict[str, str],
                prose: bool = False, plugin_root: Path = PLUGIN) -> None:
    """Verify every backticked path reference resolves, in the CORRECT form,
    to something the repo actually ships.

    prose=True relaxes only the DOC_PATH_ALLOWLIST cases - paths a document may
    legitimately name without them being live pointers. A SKILL.md never gets
    that relaxation.
    """
    for prefix, ref in PATH_RE.findall(text):
        if ref in PATH_ALLOWLIST or (prose and ref in DOC_PATH_ALLOWLIST):
            continue

        if prefix == "${CLAUDE_PLUGIN_ROOT}/":
            target = plugin_root / ref
            if not target.exists():
                fail(f"{label}: ${{CLAUDE_PLUGIN_ROOT}}/{ref} does not exist")
                continue

        elif prefix == "~/.claude/":
            # Must be something install.sh actually links, or it is dead on
            # every machine but the one where it happens to sit already.
            if ref not in installed:
                hint = ""
                if (REPO / "templates" / ref).exists():
                    hint = (f" (exists at templates/{ref} but install.sh does not "
                            f"place it - add it to install.sh and INSTALLS)")
                fail(f"~/.claude/{ref} referenced by {label} is not installed "
                     f"by install.sh{hint}")
                continue
            target = REPO / installed[ref]
            if not target.exists():
                fail(f"{label}: install.sh links {ref} from {installed[ref]}, "
                     f"which does not exist")
                continue

        elif own_dir is not None:
            # Inside a SKILL.md a bare relative path resolves from the skill's
            # OWN directory. Resolving from anywhere else is the bug class that
            # shipped as _shared/owasp-top10.md - caught structurally here.
            target = own_dir / ref
            if not target.exists():
                if (plugin_root / ref).exists():
                    fail(f"{label}: `{ref}` resolves from the plugin root, not "
                         f"from skills/{own_dir.name}/ - write it as "
                         f"${{CLAUDE_PLUGIN_ROOT}}/{ref}")
                elif (REPO / ref).exists():
                    fail(f"{label}: `{ref}` resolves from the repo root, which a "
                         f"skill cannot reach - it is dead when installed")
                else:
                    fail(f"{label}: `{ref}` does not resolve from "
                         f"skills/{own_dir.name}/ and exists nowhere")
                continue
        else:
            target = REPO / ref
            if not target.exists():
                fail(f"{label}: `{ref}` does not exist in the repo")
                continue

        if tracked:
            try:
                rel = target.resolve().relative_to(REPO.resolve()).as_posix()
            except ValueError:
                fail(f"{label}: `{ref}` resolves outside the repo to "
                     f"{target} - install.sh cannot reproduce it")
                continue
            if rel not in tracked:
                fail(f"{label}: `{ref}` resolves to {rel}, which is NOT tracked "
                     f"by git - it exists on this machine only")


# Files that quote figures about the config, and get the dead-path scan too.
# README.md and config-architecture.md were previously scanned for NEITHER,
# which is the same blind spot that let global/CLAUDE.md's own pointer to a
# never-shipped README survive four commits.
DOC_FILES = [
    "README.md",
    "install.sh",
    "docs/DESIGN.md",
    "docs/ARCHITECTURE.md",
    "docs/CUSTOMIZING.md",
    "CONTRIBUTING.md",
    "SECURITY.md",
]

# A figure in a sentence about a PAST state is not drift. Marking it in the
# prose is cheaper and more honest than an allowlist of stale numbers, which
# would go stale itself.
# A sentence ends at terminal punctuation, optionally followed by closing
# quotes, brackets or a comma, then whitespace. Plain ". " missed `.",` - the
# end of a quoted string in build-pdf.py - so a sentence on the previous line
# never ended and its "was" leaked forward.
SENTENCE_END = re.compile(r"[.!?][\"')\],]*\s")

# A line that opens a new list item, table row, shell echo or comment does not
# continue the previous line's sentence, even with no punctuation between.
NEW_ITEM = re.compile(r"^\s*([-*|#]|\d+\.\s|echo\b)")

PAST_MARKER = re.compile(r"\b(was|were|previously|historical(?:ly)?|"
                         r"at the time|then|pre-edit|before|used to)\b", re.I)

WORD_NUM = {"nine": 9, "ten": 10, "eleven": 11, "twelve": 12, "thirteen": 13,
            "fourteen": 14, "fifteen": 15}

# PLURAL "skills" only, and only letters/spaces/hyphens/backticks between the
# number and the word. Both matter: "a skill cannot stop the agent" (singular)
# and `"26", "A skill cannot ..."` (a line count in a table, comma and quote
# between) are prose, not figures, and matched before this was tightened.
SKILL_COUNT_RE = re.compile(
    r"\b(\d+|nine|ten|eleven|twelve|thirteen|fourteen|fifteen)\b"
    r"[A-Za-z`\- ]{0,30}?\bskills\b", re.I)
LINES_RE = re.compile(r"\b([\d,]+)\s+lines\b")
WORDS_RE = re.compile(r"\b([\d,]+)\s+words\b")
TOKENS_RE = re.compile(r"~(\d+\.\d+)k tokens")


# Manifest descriptions are the user-visible strings in /plugin, and they went
# stale twice before anything read them. Scanned for figures only - their
# "./plugins/..." sources are not backticked prose paths.
FIGURE_ONLY_FILES = [
    ".claude-plugin/marketplace.json",
    "plugins/devagent-standards/.claude-plugin/plugin.json",
    "plugins/delivery/.claude-plugin/plugin.json",
]

# A count whose span names the delivery plugin ("9 delivery skills", "nine
# step skills") is checked against delivery; every other count is the
# standards plugin's. Without this split the second plugin's count would
# either fail every time or tempt someone to switch the rule off.
DELIVERY_COUNT_WORDS = re.compile(r"\b(delivery|step)\b", re.I)


def check_figures(n_skills: int, res_lines: int, res_words: int,
                  n_delivery: int = 0) -> None:
    """Assert the prose figures match reality.

    The token figure is derived at ~1.39 tokens per word, the ratio measured
    for this file - so it moves whenever the word count does.
    """
    est_tokens = round(res_words * 1.39 / 1000, 1)

    for rel in DOC_FILES + FIGURE_ONLY_FILES:
        path = REPO / rel
        if not path.exists():
            if rel in DOC_FILES:
                fail(f"{rel}: listed in DOC_FILES but missing")
            continue
        prev = ""
        for lineno, line in enumerate(path.read_text().splitlines(), 1):

            def is_past(start: int, _line: str = line, prev: str = prev) -> bool:
                """Is the figure at this offset describing a PAST state?

                Searches BACKWARD from the figure to the previous sentence
                end, across the previous line too. Four things this has to get
                right, each of which broke a simpler version:
                  * whole-line scope exempted "should read ~5.7k tokens (was
                    19.6k)" entirely - the trailing historical figure vouched
                    for the current one, hiding real drift. So: backward only;
                  * cutting on ":" or ";" severed "The problem was attention
                    dilution: 11,700 words" from its own "was". So: sentence
                    boundaries only;
                  * prose wraps, so "The file was 1,582 lines" and
                    "/ 11,721 words" are different physical lines. So: include
                    the previous line;
                  * one marker must still govern a chained list -
                    "was 1,582 lines / 11,721 words / ~19.6k tokens";
                  * the previous line is only context when the current line
                    CONTINUES it. "(was 19.6k)" ending one list item or echo
                    exempted "12 devagent-standards skills" on the next, and
                    four stale counts passed that way (found 2026-10-03).
                Markers must therefore PRECEDE the figure they excuse. Prose
                that trails its marker ("ten skills ... pre-edit") should drop
                the stale count instead; a historical figure in prose is
                drift-bait that adds nothing.
                """
                span = (_line[:start] if NEW_ITEM.match(_line)
                        else prev + " " + _line[:start])
                ends = list(SENTENCE_END.finditer(span))
                if ends:
                    span = span[ends[-1].end():]
                return bool(PAST_MARKER.search(span))

            # Word count gets a small tolerance: `wc -w` and Python's split()
            # disagree by 2 on this file, so demanding equality would fail
            # whichever tool the author did not use. Any real edit moves the
            # count by far more than the tolerance.
            for raw, expected, label, tol in (
                (SKILL_COUNT_RE.search(line),
                 n_delivery if (SKILL_COUNT_RE.search(line) and DELIVERY_COUNT_WORDS.search(
                     SKILL_COUNT_RE.search(line).group(0))) else n_skills,
                 "skill count", 0),
                (LINES_RE.search(line), res_lines, "resident line count", 0),
                (WORDS_RE.search(line), res_words, "resident word count", 5),
            ):
                if not raw:
                    continue
                tok = raw.group(1).lower()
                got = WORD_NUM.get(tok)
                if got is None:
                    try:
                        got = int(tok.replace(",", ""))
                    except ValueError:
                        continue
                if abs(got - expected) > tol and not is_past(raw.start()):
                    fail(f"{rel}:{lineno}: {label} reads {raw.group(1)!r}, "
                         f"actual is {expected} - stale figure (or mark the "
                         f"sentence as past tense if it describes a past state)")

            for m in TOKENS_RE.finditer(line):
                if abs(float(m.group(1)) - est_tokens) > 0.05 \
                        and not is_past(m.start()):
                    fail(f"{rel}:{lineno}: token figure reads ~{m.group(1)}k, "
                         f"derived value is ~{est_tokens}k ({res_words} words "
                         f"x 1.39) - stale figure")

            prev = line


LENS_WHEN = {"always", "personal_data", "calls_model", "has_ui"}

# The plugins install without docs/, so a shipped step or agent that defers to
# "§3.4" points at nothing at run time: the requirements analyst set the tier
# "per DESIGN §3.2" and never saw it. A shipped file states its rule itself and
# may cite DESIGN only as a parenthetical maintainer pointer, `(DESIGN §n`.
# `02 §n` points into the plan's own design file, which does ship.
SECTION_REF = re.compile(r"(?<!\(DESIGN )(?<!02 )§")


def check_section_refs() -> None:
    for root in (PLUGIN, DELIVERY):
        for f in sorted(root.rglob("*.md")) if root.is_dir() else []:
            for n, line in enumerate(f.read_text().splitlines(), 1):
                if SECTION_REF.search(line):
                    fail(f"{f.relative_to(REPO)}:{n}: section reference outside "
                         f"`(DESIGN §n)` - docs/DESIGN.md does not ship with the "
                         f"plugin, so state the rule here and cite it in parentheses")


def check_delivery(tracked: set[str], installed: dict[str, str],
                   resident: str) -> int:
    """Rules for the delivery plugin. Returns its skill count (0 if absent).

    Its skills are typed by the operator, never description-matched, so the
    standards rules invert: each must be user-only and must NOT have a
    resident stub. Agents and lenses get structure checks.
    """
    if not DELIVERY.exists():
        return 0
    manifest = check_json(DELIVERY / ".claude-plugin" / "plugin.json")
    if manifest:
        if manifest.get("name") != "delivery":
            fail(f"delivery plugin.json name is {manifest.get('name')!r}, expected 'delivery'")
        if "devagent-standards" not in (manifest.get("dependencies") or []):
            fail("delivery plugin.json must declare dependencies: [\"devagent-standards\"]")

    count = 0
    skills = DELIVERY / "skills"
    for d in sorted(skills.iterdir()) if skills.is_dir() else []:
        if not d.is_dir():
            continue
        f = d / "SKILL.md"
        if not f.exists():
            fail(f"delivery skills/{d.name}/ has no SKILL.md")
            continue
        count += 1
        text = f.read_text()
        fm = parse_frontmatter(text) or {}
        label = f"delivery:{d.name}"
        if fm.get("name") != d.name:
            fail(f"{label}: frontmatter name is {fm.get('name')!r}, must match directory")
        if not fm.get("description"):
            fail(f"{label}: no description")
        if str(fm.get("disable-model-invocation", "")).lower() != "true":
            fail(f"{label}: needs `disable-model-invocation: true` - delivery "
                 f"steps are typed by the operator, never auto-invoked")
        if f"**`delivery:{d.name}`**" in resident:
            fail(f"{label}: must not have a resident stub - stubs exist for "
                 f"description-matched skills only")
        check_paths(label, text, d, tracked, installed, plugin_root=DELIVERY)

    agents = DELIVERY / "agents"
    for f in sorted(agents.glob("*.md")) if agents.is_dir() else []:
        fm = parse_frontmatter(f.read_text()) or {}
        if fm.get("name") != f.stem:
            fail(f"delivery agent {f.name}: agent name {fm.get('name')!r} must "
                 f"equal the filename")
        if not fm.get("tools"):
            fail(f"delivery agent {f.name}: needs explicit tools - least "
                 f"privilege per agent")

    lenses = DELIVERY / "references" / "lenses"
    for f in sorted(lenses.glob("*.md")) if lenses.is_dir() else []:
        fm = parse_frontmatter(f.read_text()) or {}
        if fm.get("slug") != f.stem:
            fail(f"delivery lens {f.name}: slug {fm.get('slug')!r} must equal the filename")
        for k in ("standards", "when", "model"):
            if k not in fm:
                fail(f"delivery lens {f.name}: missing `{k}`")
        if fm.get("when") and fm.get("when") not in LENS_WHEN:
            fail(f"delivery lens {f.name}: when={fm.get('when')!r} not in {sorted(LENS_WHEN)}")

    check_pins()
    return count


def check_pins() -> None:
    """Every PINS.md value must appear where the row says it is set.

    Rows set in machine-local files are checked only where that file exists
    (never in CI); rows set in the repo are always checked.
    """
    pins = DELIVERY / "PINS.md"
    if not pins.exists():
        return
    for line in pins.read_text().splitlines():
        cells = [c.strip() for c in line.strip().strip("|").split("|")]
        if len(cells) < 3 or cells[0] in ("Pin", "") or set(cells[0]) <= {"-"}:
            continue
        value, where = cells[1], cells[2]
        m = re.match(r"`([^`]+)`", where)
        if not m:
            continue
        target = Path(os.path.expanduser(m.group(1))) if m.group(1).startswith("~") \
            else REPO / m.group(1)
        if not target.exists():
            continue
        files = [target] if target.is_file() else [p for p in target.rglob("*") if p.is_file()]
        if not any(value in p.read_text(errors="ignore") for p in files):
            fail(f"PINS.md: {cells[0]} = {value} not found in {m.group(1)} - the "
                 f"pin and the code disagree")


def check_json(path: Path) -> dict | None:
    try:
        return json.loads(path.read_text())
    except FileNotFoundError:
        fail(f"missing: {path.relative_to(REPO)}")
    except json.JSONDecodeError as e:
        fail(f"invalid JSON in {path.relative_to(REPO)}: {e}")
    return None


def main() -> int:
    # ---------------------------------------------------------------- manifests
    check_json(REPO / ".claude-plugin" / "marketplace.json")
    manifest = check_json(PLUGIN / ".claude-plugin" / "plugin.json")
    if manifest and manifest.get("name") != "devagent-standards":
        fail(f"plugin.json name is {manifest.get('name')!r}, expected 'devagent-standards'")

    # Structural rules from the plugin docs
    if (PLUGIN / ".claude-plugin" / "skills").exists():
        fail("skills/ must be at plugin root, not nested inside .claude-plugin/")
    if not SKILLS.is_dir():
        fail("no skills/ directory at plugin root")
        return report()

    # A directory inside skills/ with no SKILL.md is not a skill. It may be
    # ignored silently, which is how a stray _shared/ survived unnoticed.
    for d in sorted(SKILLS.iterdir()):
        if d.is_dir() and not (d / "SKILL.md").exists():
            fail(f"skills/{d.name}/ has no SKILL.md - move non-skill assets to "
                 f"plugins/devagent-standards/references/")

    skill_dirs = sorted(d for d in SKILLS.iterdir() if (d / "SKILL.md").exists())
    names = {d.name for d in skill_dirs}
    if not skill_dirs:
        fail("no skills found")
        return report()

    resident = RESIDENT.read_text() if RESIDENT.exists() else ""
    if not resident:
        fail(f"cannot read {RESIDENT.relative_to(REPO)}")

    tracked = tracked_files()
    installed = installed_map()

    # The resident file gets the same path scan. It was previously checked only
    # for stubs, which is how its own pointer to a never-shipped README lived
    # for four commits.
    if resident:
        check_paths("templates/CLAUDE.md", resident, None, tracked, installed)

    # The sibling docs get the same dead-path scan. They quote paths just as
    # freely and were previously scanned for nothing at all.
    for rel in DOC_FILES:
        p = REPO / rel
        if p.exists():
            check_paths(rel, p.read_text(), None, tracked, installed,
                        prose=True)

    # ------------------------------------------------------------- per skill
    for d in skill_dirs:
        sk = d.name
        text = (d / "SKILL.md").read_text()
        fm = parse_frontmatter(text)

        if fm is None:
            fail(f"{sk}: no parseable YAML frontmatter")
            continue
        if fm.get("name") != sk:
            fail(f"{sk}: frontmatter name is {fm.get('name')!r}, must match directory")
        desc = fm.get("description", "")
        if not desc:
            fail(f"{sk}: no description - the description IS the trigger")
        elif len(desc) < MIN_DESC_CHARS:
            fail(f"{sk}: description is only {len(desc)} chars (< {MIN_DESC_CHARS}); "
                 f"too thin to match reliably")

        # Every backticked path reference: resolves, in the correct form, to
        # something git tracks. Replaces the old first-segment allowlist, which
        # would not have caught the _shared/ bug it was written for.
        check_paths(sk, text, d, tracked, installed)

        # Sibling-skill mentions should name a real skill. Scan ONLY the Related
        # section - elsewhere, backticked hyphenated tokens are usually CSP
        # directives, HTML attributes or CLI flags (`unsafe-inline`, `v-html`).
        related = text.split("## Related", 1)
        if len(related) == 2:
            for ref in re.findall(r"^- `([a-z][a-z0-9-]{3,})`", related[1], re.M):
                if ref in names or ref == sk:
                    continue
                notes.append(f"{sk}: Related lists `{ref}` - not an installed skill "
                             f"(fine if it is a built-in, e.g. dataviz)")

        # Every skill needs a resident stub naming it. Either form counts here -
        # prose cross-references legitimately use the bare name. The DETAILED
        # STANDARDS stub itself must use the invocable form; enforced below.
        if resident and f"`{sk}`" not in resident \
                and f"`devagent-standards:{sk}`" not in resident:
            fail(f"{sk}: NO resident stub in templates/CLAUDE.md - the deterministic "
                 f"trigger is missing")

    # ------------------------------------- reverse direction: stubs -> skills
    if resident:
        stub_section = resident.split("DETAILED STANDARDS", 1)
        if len(stub_section) == 2:
            body = stub_section[1]
            # The optional prefix must be part of the pattern, not assumed absent:
            # matching only the bare form would make this whole check silently
            # unreachable the moment the stubs were prefixed.
            for _, ref in re.findall(r"\*\*`(devagent-standards:)?([a-z][a-z0-9-]+)`\*\*",
                                     body):
                if ref not in names:
                    fail(f"templates/CLAUDE.md has a stub for `{ref}`, which is not an "
                         f"installed skill")
            # The stub is the deterministic trigger, so the name it prints has to
            # be the name the skill is actually invoked by.
            for sk in sorted(names):
                if f"**`devagent-standards:{sk}`**" not in body:
                    fail(f"templates/CLAUDE.md stub for `{sk}` names it bare - write it "
                         f"as `devagent-standards:{sk}`, the invocable name")
        else:
            fail("templates/CLAUDE.md has no 'DETAILED STANDARDS' stub section")

    # Prose figures last, so their findings read after the structural ones.
    n_delivery = check_delivery(tracked, installed, resident)
    check_section_refs()

    if resident:
        check_figures(len(skill_dirs), len(resident.splitlines()),
                      len(resident.split()), n_delivery)

    print(f"checked {len(skill_dirs)} skills: {', '.join(sorted(names))}")
    return report()


def report() -> int:
    for n in notes:
        print(f"  note: {n}")
    if findings:
        print(f"\n{len(findings)} finding(s):")
        for f in findings:
            print(f"  FAIL: {f}")
        return 1
    print("clean")
    return 0


if __name__ == "__main__":
    sys.exit(main())
