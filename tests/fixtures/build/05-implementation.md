---
format: delivery-plan/1
feature: f
step: 05-implementation
status: approved
date: 2026-10-14
generator: delivery@test
reads: []
branch: main
base: BASE_SHA
verify_allowed:
  - python3 check.py src/a.txt
  - python3 check.py src/b.txt
  - python3 check.py src/c.txt
  - python3 check.py src/d.txt
  - python3 check.py src/e.txt
  - python3 check.py src/f.txt
  - python3 check.py src/g.txt
  - python3 check.py src/h.txt
  - python3 check.py src/p.txt
---

# Fixture plan for scripts/test-build-protocol.sh

Each task is driven by the test as a scripted builder. `check.py <path>`
passes when the path exists and does not contain the word BAD.

### T-01 [ ] Happy path
- depends: none
- files: src/a.txt
- acceptance: a.txt exists
- verify: `python3 check.py src/a.txt`
- timeout: 2m

### T-02 [ ] Strays outside its files
- depends: none
- files: src/b.txt
- acceptance: b.txt exists
- verify: `python3 check.py src/b.txt`
- timeout: 2m

### T-03 [ ] Touches CI configuration
- depends: none
- files: src/c.txt, .github/workflows/ci.yml
- acceptance: c.txt exists
- verify: `python3 check.py src/c.txt`
- timeout: 2m

### T-04 [ ] Writes the shared file first
- depends: none
- files: src/d.txt, src/shared.txt
- acceptance: d.txt exists
- verify: `python3 check.py src/d.txt`
- timeout: 2m

### T-05 [ ] Writes the shared file second
- depends: none
- files: src/e.txt, src/shared.txt
- acceptance: e.txt exists
- verify: `python3 check.py src/e.txt`
- timeout: 2m

### T-06 [ ] Fails its verify
- depends: none
- files: src/f.txt
- acceptance: f.txt is good
- verify: `python3 check.py src/f.txt`
- timeout: 2m

### T-07 [ ] Killed before committing
- depends: none
- files: src/g.txt
- acceptance: g.txt exists
- verify: `python3 check.py src/g.txt`
- timeout: 2m

### T-08 [ ] Killed after committing
- depends: none
- files: src/h.txt
- acceptance: h.txt exists
- verify: `python3 check.py src/h.txt`
- timeout: 2m

### T-09 [ ] Lists Playwright output as a file
- depends: none
- files: src/p.txt, .playwright-mcp/
- acceptance: p.txt exists
- verify: `python3 check.py src/p.txt`
- timeout: 2m

### T-10 [ ] Depends on the happy path
- depends: T-01
- files: src/j.txt
- acceptance: j.txt exists
- verify: `python3 check.py src/a.txt`
- timeout: 2m
