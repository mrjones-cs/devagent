---
format: delivery-plan/1
feature: bad-flag-plan-remove-order
step: 05-implementation
status: approved
date: 2026-10-04
generator: delivery@v1.4.0
reads: 01-requirements.md, 02-design.md, 03-research.md, 04-review.md
branch: main
base: 0000000
flagged: true
verify_allowed:
  - bash scripts/test-thing.sh
---

# Implementation plan

Two flags, `new-search` and `bulk.export_v2`. T-01 is setup before both add
tasks; the remove tasks come last and are still open.

### T-01 [ ] Add the check command
- depends: none
- files: scripts/test-thing.sh
- acceptance: the check command runs
- verify: `bash scripts/test-thing.sh`
- timeout: 5m

### T-02 [ ] Add flag new-search, off by default
- depends: T-01
- flag: add new-search
- files: src/flags.py
- acceptance: the flag exists and is off by default
- verify: `bash scripts/test-thing.sh`
- timeout: 5m

### T-03 [ ] Add flag bulk.export_v2, off by default
- depends: T-01
- flag: add bulk.export_v2
- files: src/flags_export.py
- acceptance: the flag exists and is off by default
- verify: `bash scripts/test-thing.sh`
- timeout: 5m

### T-04 [ ] Search behind new-search
- depends: T-02, T-03
- files: src/search.py
- acceptance: the new search answers when the flag is on
- flag on: the new search endpoint returns results
- flag off: the old search answers and the new endpoint returns 404
- verify: `bash scripts/test-thing.sh`
- timeout: 10m

### T-05 [ ] Export behind bulk.export_v2
- depends: T-04
- files: src/export.py
- acceptance: bulk export works when its flag is on
- flag on: bulk export writes the v2 file and search still uses the new path
- flag off: export writes the v1 file and search follows its own flag
- verify: `bash scripts/test-thing.sh`
- timeout: 10m

### T-06 [ ] Remove flag new-search
- depends: T-01, T-02, T-03, T-04
- flag: remove new-search
- flag_owner: client platform lead
- remove_by: 2027-01-31
- files: src/flags.py, src/search.py
- acceptance: the old search path and the flag are gone
- verify: `bash scripts/test-thing.sh`
- timeout: 10m

### T-07 [ ] Remove flag bulk.export_v2
- depends: T-05
- flag: remove bulk.export_v2
- flag_owner: client data lead
- remove_by: 2027-03-31
- files: src/flags_export.py, src/export.py
- acceptance: the v1 export path and the flag are gone
- verify: `bash scripts/test-thing.sh`
- timeout: 10m

## Plan-level acceptance

| Criterion | Proven by |
|---|---|
| AC-1 | T-04 |
