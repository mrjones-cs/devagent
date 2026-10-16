---
format: delivery-plan/1
feature: r
step: 05-implementation
status: approved
date: 2026-10-14
generator: delivery@test
reads: []
branch: main
base: BASE_SHA
verify_allowed:
  - python3 check.py src/a.txt
---

# Fixture plan for build-ready grouping

### T-01 [ ] First
- depends: none
- files: src/a.txt
- acceptance: x
- verify: `python3 check.py src/a.txt`
- timeout: 1m

### T-02 [ ] Same file as T-01
- depends: none
- files: src/a.txt
- acceptance: x
- verify: `python3 check.py src/a.txt`
- timeout: 1m

### T-03 [ ] Directory containing T-01's file
- depends: none
- files: src/
- acceptance: x
- verify: `python3 check.py src/a.txt`
- timeout: 1m

### T-04 [ ] Waits for T-01
- depends: T-01
- files: lib/w.py
- acceptance: x
- verify: `python3 check.py src/a.txt`
- timeout: 1m

### T-05 [ ] Independent docs
- depends: none
- files: docs/x.md
- acceptance: x
- verify: `python3 check.py src/a.txt`
- timeout: 1m

### T-06 [ ] Independent lib
- depends: none
- files: lib/y.py
- acceptance: x
- verify: `python3 check.py src/a.txt`
- timeout: 1m

### T-07 [ ] Fourth independent task
- depends: none
- files: tests/z.py
- acceptance: x
- verify: `python3 check.py src/a.txt`
- timeout: 1m
