#!/usr/bin/env bash
#
# Fail if the repository names anything its maintainers keep out of it.
#
#     FORBIDDEN_TERMS='term-one|term-two' bash scripts/check-forbidden-terms.sh [--require]
#
# The pattern (an extended regular expression, matched case-insensitively) comes
# from the environment, never from a file in the repository: a list of terms in
# a public repo would be the very disclosure it exists to prevent. CI fills it
# from a repository secret.
#
# What is searched, in the current checkout:
#   - every tracked file's contents, binary files included
#   - every tracked file and directory NAME
#   - every commit's author, committer and message, on every branch and tag
#   - every line ever added or removed, on every branch and tag
#
# Output names files, counts and commit hashes only. It never prints the line
# that matched or the pattern, so a failing run does not itself leak the term.
#
# Exit: 0 clean (or skipped without --require) - 1 found - 2 unusable
#       (no pattern with --require, an invalid pattern, not a git repository)
#
set -uo pipefail

REQUIRE=0
for a in "$@"; do
  case "$a" in
    --require) REQUIRE=1 ;;
    -h|--help) sed -n '2,24p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
    *) echo "unknown option: $a" >&2; exit 2 ;;
  esac
done

git rev-parse --git-dir >/dev/null 2>&1 || { echo "error: not inside a git repository" >&2; exit 2; }

PAT="${FORBIDDEN_TERMS:-}"
if [ -z "$PAT" ]; then
  if [ "$REQUIRE" -eq 1 ]; then
    echo "error: FORBIDDEN_TERMS is empty, but this check is required" >&2
    exit 2
  fi
  echo "skipped: FORBIDDEN_TERMS is not set"
  exit 0
fi

# An invalid regular expression makes grep exit 2; "no match" is exit 1.
printf '' | grep -qiE -- "$PAT" 2>/dev/null
[ $? -le 1 ] || { echo "error: FORBIDDEN_TERMS is not a valid extended regular expression" >&2; exit 2; }

found=0

tree_files="$(git grep -a -i -l -E -e "$PAT" -- . 2>/dev/null || true)"
if [ -n "$tree_files" ]; then
  found=1
  echo "FOUND in the working tree, in $(printf '%s\n' "$tree_files" | wc -l | tr -d ' ') file(s):"
  printf '%s\n' "$tree_files" | sed 's/^/  /'
fi

name_hits="$(git ls-files | grep -ciE -- "$PAT" || true)"
if [ "${name_hits:-0}" -gt 0 ]; then
  found=1
  echo "FOUND in $name_hits tracked file or directory name(s) (not listed: the name would show the term)"
fi

# --author, --committer and --grep are separate filters (git ANDs them when
# combined), so ask for each on its own and merge the commit hashes.
meta_commits="$( { git log --all -i -E --author="$PAT" --format=%h
                   git log --all -i -E --committer="$PAT" --format=%h
                   git log --all -i -E --grep="$PAT" --format=%h; } 2>/dev/null | sort -u )"
if [ -n "$meta_commits" ]; then
  found=1
  echo "FOUND in the author, committer or message of $(printf '%s\n' "$meta_commits" | wc -l | tr -d ' ') commit(s):"
  printf '%s\n' "$meta_commits" | head -20 | sed 's/^/  /'
fi

# --text matters: without it git's pickaxe skips binary files, so a term added in
# a binary file and deleted later would be invisible here.
diff_commits="$(git log --all -i --text -G"$PAT" --format=%h 2>/dev/null || true)"
if [ -n "$diff_commits" ]; then
  found=1
  echo "FOUND in the history of $(printf '%s\n' "$diff_commits" | wc -l | tr -d ' ') commit(s) (a later commit may have removed it; it is still in every clone):"
  printf '%s\n' "$diff_commits" | head -20 | sed 's/^/  /'
fi

if [ "$found" -eq 1 ]; then
  echo "FAIL: the repository names a forbidden term. Fix the files; if history is affected, publish from a clean snapshot instead."
  exit 1
fi

echo "ok: no forbidden term in the tree, the names, or $(git rev-list --all | wc -l | tr -d ' ') commit(s) of history"
