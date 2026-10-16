#!/usr/bin/env bash
#
# Negative tests for check-skills.py: reintroduce each bug it claims to catch
# and confirm it FAILS, then confirm the tree is restored and it passes again.
#
#     bash scripts/test-check-skills.sh
#
# Why this exists: a validator that matches nothing reports clean. This repo
# has hit that twice - a regex fitted to one historical filename that would
# never have caught the bug class it was written for, and a reverse stub check
# whose pattern stopped matching the moment the stubs were reformatted. Both
# were green. A checker without negative tests is an assertion, not a check.
#
# Mutations are applied to a COPY of the working tree, never to the repo, so an
# interrupted run cannot leave the real files damaged.

set -uo pipefail

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PASS=0
NOFIRE=0
WORK=""

cleanup() { [ -n "$WORK" ] && rm -rf "$WORK"; }
trap cleanup EXIT

WORK="$(mktemp -d /tmp/devagent-checktest.XXXXXX)"
R="$WORK/repo"
mkdir -p "$R"
# --cached --others --exclude-standard = tracked PLUS new-but-not-ignored.
# Plain `git ls-files` omits files that have not been `git add`ed yet, so a
# newly written skill is absent from the snapshot and the baseline fails for
# a reason that has nothing to do with the test. Ignored files stay excluded,
# which is what makes the clients.local.md bootstrap test meaningful.
git -C "$REPO" ls-files --cached --others --exclude-standard >"$WORK/files.txt"
rsync -a --files-from="$WORK/files.txt" "$REPO/" "$R/"
cp -R "$REPO/.git" "$R/.git" 2>/dev/null || true

# COVER=1 records branch coverage of every checker run (gate G-3), using the
# pinned test-only tool from plugins/delivery/PINS.md. Off by default and in CI.
ck() {
  if [ -n "${COVER:-}" ]; then
    (cd "$R" && uv run -q --with 'coverage==7.16.2' python -m coverage run --branch -p \
       --data-file="$WORK/.coverage" scripts/check-skills.py 2>&1)
  else
    (cd "$R" && python3 scripts/check-skills.py 2>&1)
  fi
}
restore() {
  # Planted files go FIRST, then the snapshot is re-synced: a planted
  # agents/builder.md must not survive, and a real one must come back.
  rm -rf "$R/plugins/devagent-standards/skills/zzz-fake" \
         "$R/plugins/devagent-standards/skills/notaskill" "$R/docs/local" \
         "$R/plugins/delivery/skills/zzz-step" \
         "$R/plugins/delivery/agents/builder.md" \
         "$R/plugins/delivery/references/lenses/attacker.md"
  rsync -a --delete --files-from="$WORK/files.txt" "$REPO/" "$R/"
}

# name | expected substring in the failure | mutation (run inside $R)
t() {
  local name="$1" expect="$2"; shift 2
  ( cd "$R" && eval "$@" ) >/dev/null 2>&1
  local out rc
  out="$(ck)"; rc=$?
  if [ "$rc" -ne 0 ] && printf '%s' "$out" | grep -qi -- "$expect"; then
    PASS=$((PASS+1)); printf '  \033[32mPASS\033[0m   %s\n' "$name"
  else
    NOFIRE=$((NOFIRE+1)); printf '  \033[31mNOFIRE\033[0m %s (exit %s)\n' "$name" "$rc"
  fi
  restore
}

echo "check-skills.py negative tests"
base="$(ck)"
if printf '%s' "$base" | grep -q '^clean$'; then
  echo "  baseline: clean"
else
  echo "  baseline is NOT clean - fix the repo before trusting these results:"
  printf '%s\n' "$base" | grep FAIL | sed 's/^/    /'
  exit 1
fi
echo

t "dead relative cross-reference in a skill" "does not resolve" \
  "printf '\nSee \`references/nope.md\`.\n' >> plugins/devagent-standards/skills/encryption/SKILL.md"

t "the original _shared/ base-directory bug" "resolves from the plugin root" \
  "printf '\nSee \`references/owasp-top10.md\`.\n' >> plugins/devagent-standards/skills/encryption/SKILL.md"

t "reference resolving only to an untracked file" "NOT tracked" \
  "mkdir -p docs/local && echo x > docs/local/scratch.md && printf '\nSee \`docs/local/scratch.md\`.\n' >> templates/CLAUDE.md"

t "skill with no resident stub" "NO resident stub" \
  "mkdir -p plugins/devagent-standards/skills/zzz-fake && printf -- '---\nname: zzz-fake\ndescription: %s\n---\n\n# x\n' \"\$(printf 'a%.0s' {1..150})\" > plugins/devagent-standards/skills/zzz-fake/SKILL.md"

# Anchored on the first real stub, not on a sentence. An earlier version keyed
# off the phrase "summary is not the standard"; that wording was later edited,
# the mutation silently became a no-op, and the test reported NOFIRE against a
# rule that was in fact working. Anchor on structure, not prose.
t "stub naming a skill that does not exist" "not an installed skill" \
  "python3 -c \"
import pathlib
p=pathlib.Path('templates/CLAUDE.md'); t=p.read_text()
i=t.index('**\\\`devagent-standards:')
p.write_text(t[:i] + '**\\\`devagent-standards:ghost-skill\\\`** - nope.' + chr(10)*2 + t[i:])\""

t "stub naming a skill by its bare name" "names it bare" \
  "perl -0pi -e 's/\*\*\`devagent-standards:encryption\`\*\*/**\`encryption\`**/' templates/CLAUDE.md"

t "frontmatter name not matching the directory" "must match directory" \
  "perl -0pi -e 's/^name: encryption/name: encryption-oops/m' plugins/devagent-standards/skills/encryption/SKILL.md"

t "description too thin to match on" "too thin to match" \
  "perl -0pi -e 's/^description: .*/description: Encryption stuff./m' plugins/devagent-standards/skills/encryption/SKILL.md"

t "directory under skills/ with no SKILL.md" "has no SKILL.md" \
  "mkdir -p plugins/devagent-standards/skills/notaskill && echo x > plugins/devagent-standards/skills/notaskill/thing.md"

t "~/.claude/ path install.sh does not link" "not installed by install.sh" \
  "printf '\nSee \`~/.claude/claudedocs/unlinked.md\`.\n' >> templates/CLAUDE.md"

t "DETAILED STANDARDS section removed" "DETAILED STANDARDS" \
  "perl -0pi -e 's/# DETAILED STANDARDS - LOAD THE SKILL/# DETAIL SECTION/' templates/CLAUDE.md"

t "corrupt plugin.json" "invalid JSON" \
  "echo '{oops' > plugins/devagent-standards/.claude-plugin/plugin.json"

t "plugin renamed" "expected 'devagent-standards'" \
  "perl -0pi -e 's/\"name\": \"devagent-standards\"/\"name\": \"other\"/' plugins/devagent-standards/.claude-plugin/plugin.json"

# ---- the figure rules, added 2026-08-23 -----------------------------------
t "stale skill count in prose" "skill count reads" \
  "perl -0pi -e 's/- the 13 devagent-standards skills/- the 11 devagent-standards skills/' README.md"

t "stale resident line count" "resident line count reads" \
  "perl -0pi -e 's/\(615 lines,/(540 lines,/' README.md"

t "stale token figure" "token figure reads" \
  "perl -0pi -e 's/615 lines, ~6\.6k tokens/615 lines, ~5.6k tokens/' README.md"

t "a figure excused by a LATER past marker is still caught" "token figure reads" \
  "perl -0pi -e 's/memory files ~6\.6k tokens \(was close/memory files ~5.6k tokens (was close/' README.md"

# ---- added 2026-10-03: two ways a stale count passed unflagged -------------
t "a past marker on the PREVIOUS list item does not excuse this one" "skill count reads" \
  "perl -0pi -e 's/- the 13 devagent-standards skills and/- the 12 devagent-standards skills and/' README.md"

t "a past marker before a quoted sentence end does not leak forward" "skill count reads" \
  "printf '\nThe old note said \"it was smaller.\" The 12 devagent-standards skills load on demand.\n' >> README.md"

t "a capitalised number-word count is still caught" "skill count reads" \
  "perl -0pi -e 's/Thirteen on-demand skills/Twelve on-demand skills/' README.md"

# ---- added 2026-10-14 (T-02): the delivery plugin's rules ------------------
# Helpers plant a minimal delivery skill / agent / lens in the throwaway copy.
dskill() {  # $1 name, $2 extra frontmatter line
  mkdir -p "plugins/delivery/skills/$1"
  printf -- '---\nname: %s\ndescription: A delivery step used only for this negative test of the checker rules.\n%s\n---\n\n# x\n' "$1" "$2" > "plugins/delivery/skills/$1/SKILL.md"
}
dagent() {  # $1 filename stem, $2 frontmatter name, $3 tools line
  mkdir -p plugins/delivery/agents
  printf -- '---\nname: %s\ndescription: test agent\n%s\n---\n\n# x\n' "$2" "$3" > "plugins/delivery/agents/$1.md"
}
dlens() {  # $1 stem, $2 extra lines
  mkdir -p plugins/delivery/references/lenses
  printf -- '---\nslug: %s\n%s\n---\n\n# x\n' "$1" "$2" > "plugins/delivery/references/lenses/$1.md"
}

t "delivery skill without disable-model-invocation" "disable-model-invocation" \
  "dskill zzz-step ''"

t "delivery skill given a resident stub" "must not have a resident stub" \
  "dskill zzz-step 'disable-model-invocation: true' && printf '\n**\`delivery:zzz-step\`** - nope.\n' >> templates/CLAUDE.md"

t "delivery agent name not matching its file" "must equal the filename" \
  "dagent builder wrong-name 'tools: Read'"

t "delivery agent without explicit tools" "needs explicit tools" \
  "dagent builder builder ''"

t "delivery lens missing when" "missing \`when\`" \
  "dlens attacker \"standards: [auth-portal]\nmodel: opus\""

t "stale skill count in a manifest description" "skill count reads" \
  "perl -0pi -e 's/thirteen on-demand skills/twelve on-demand skills/' .claude-plugin/marketplace.json"

t "PINS.md disagreeing with the code" "the pin and the code disagree" \
  "perl -0pi -e 's/\| delivery-plugin \| 1\.0\.0 \|/| delivery-plugin | 9.9.9 |/' plugins/delivery/PINS.md"

t "delivery manifest without its dependency" "dependencies" \
  "perl -0pi -e 's/\"dependencies\": \[\"devagent-standards\"\],//' plugins/delivery/.claude-plugin/plugin.json"

echo
after="$(ck)"
printf '%s' "$after" | grep -q '^clean$' \
  && echo "  restore verified: checker clean again" \
  || { echo "  RESTORE FAILED - the copy is dirty"; NOFIRE=$((NOFIRE+1)); }

echo
if [ -n "${COVER:-}" ]; then
  (cd "$WORK" && uv run -q --with 'coverage==7.16.2' python -m coverage combine -q --data-file="$WORK/.coverage" "$WORK"/.coverage.* >/dev/null 2>&1
   uv run -q --with 'coverage==7.16.2' python -m coverage report --data-file="$WORK/.coverage" --include='*/scripts/check-skills.py' --show-missing > "$WORK/cov.txt" 2>&1; cat "$WORK/cov.txt" | tail -3)
  cp "$WORK/cov.txt" /tmp/check-skills-coverage.txt 2>/dev/null || true
fi
echo "$PASS rules fired correctly, $NOFIRE did not"
[ "$NOFIRE" -eq 0 ] || exit 1
