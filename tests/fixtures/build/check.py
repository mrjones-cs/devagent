"""Fake verify runner for scripts/test-build-protocol.sh (a fixture, not a tool).

    python3 check.py <path>

Passes ("1 passed") when <path> exists and does not contain the word BAD.
"""
import sys
from pathlib import Path

p = Path(sys.argv[1])
if p.is_file() and "BAD" not in p.read_text():
    print("1 passed, 0 failed")
    sys.exit(0)
print("0 passed, 1 failed")
sys.exit(1)
