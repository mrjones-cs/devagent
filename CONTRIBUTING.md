# Contributing to DevAgent

Thanks for helping. DevAgent guards the machine people build software on, so
the bar for changes is evidence, not plausibility.

## Before you start

- **Bug reports and ideas:** open an issue. For anything security-relevant,
  use [SECURITY.md](SECURITY.md) instead.
- **Larger changes** (a new rule, a new workflow step, a change to the plan
  grammar): open an issue first, so the design can be agreed before the work.

## Development setup

```bash
git clone https://github.com/<you>/devagent.git && cd devagent
python3 scripts/check-skills.py    # must print "clean"
```

Requirements: `python3` 3.11+, `git`, `bash`; `uv` for coverage runs;
Claude Code for `claude plugin validate --strict`. Nothing else: every script
is standard library only, and new dependencies are not accepted without
discussion (see "Dependencies" below).

## The rules for a change

1. **Run every check, not just the one you touched.** Mode-dependent
   behaviour lives in more than one place. The full list is in the README
   under "Checks"; CI runs all of it.
2. **Tests in both directions.** A guard rule needs cases that must fire and
   benign look-alikes that must not. A validator needs a negative test that
   fails without your change.
3. **Prove the tests catch the bug.** Break your change on purpose and watch
   a test fail (a mutation check). Say in the pull request which mutation you
   tried and how many tests failed.
4. **Coverage:** at least 80% line and branch on new and changed code
   (`COVER=1 bash scripts/<suite>.sh`).
5. **Keep the docs true.** `check-skills.py` fails on stale counts, dead path
   references and missing skill stubs. A change to a component updates
   [docs/DESIGN.md](docs/DESIGN.md) in the same pull request.
6. **No organisation, client or personal data** in anything committed: names,
   account IDs, emails, internal hostnames, absolute paths with a username.

## Dependencies

Scripts are standard-library Python or bash, because they run on every tool
call or with the operator's credentials, and an installed package runs its
own code before anyone reviews it. Test-only tools are pinned to an exact
version and run through `uv`, never installed globally. Every pin is recorded
in `plugins/delivery/PINS.md`.

## Pull requests

- One logical change per pull request, with a description of what it fixes,
  how you verified it (commands and counts), and what you could not verify.
- Commits generated with an AI assistant: say so in the description, or with
  an `Assisted-by:` trailer.
- By contributing you agree your contribution is licensed under the
  [MIT License](LICENSE).

## Code of conduct

This project follows the [Contributor Covenant](CODE_OF_CONDUCT.md).
