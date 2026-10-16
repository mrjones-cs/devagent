---
format: delivery-plan/1
feature: good
step: 05-implementation
status: approved
date: 2026-10-04
generator: delivery@v1.4.0
reads: 01-requirements.md, 02-design.md, 03-research.md, 04-review.md
branch: main
base: 0000000
manual_evidence: [T-02]   # written by hand before run-verify existed
verify_allowed:
  - bash scripts/test-thing.sh
  - python3 scripts/check.py
---

# Implementation plan

### T-01 [x] Build the thing
- depends: none
- files: src/a.py
- acceptance: the thing works
- verify: `bash scripts/test-thing.sh`
- timeout: 5m
- evidence: run-verify · exit 0 · tests 12 · 4.2s · log evidence/T-01.log sha256:73e136c552c4a947513eb0c83a8994e391da755afe997824b858b36133cdee96 · 2026-10-05

### T-02 [x] Build the other thing
- depends: T-01
- files: src/b.py
- acceptance: the other thing works
- verify: `python3 scripts/check.py`
- timeout: 5m
- evidence: manual (pre run-verify) · `python3 scripts/check.py` → exit 0 · 2026-10-05

### T-03 [~] Build a third thing
- owner: fixture.owner · session: 2026-10-06 · started: 2026-10-06 · worktree: main
- depends: T-01, T-02
- files: src/c.py
- acceptance: the third thing works
- verify: `bash scripts/test-thing.sh`
- timeout: 10m

### T-04 [!] Build a blocked thing
- reason: scope — touched a path outside files
- depends: T-03
- files: src/d.py
- acceptance: the blocked thing works
- verify: `bash scripts/test-thing.sh`
- timeout: 1h

### T-05 [ ] Build the last thing
- depends: T-04
- files: src/e.py
- acceptance: the last thing works
- verify: `bash scripts/test-thing.sh`
- timeout: 30s

## Plan-level acceptance

| Criterion | Proven by |
|---|---|
| AC-1 | T-01 |
