#!/usr/bin/env python3
"""Focused upstream-parity checks for the privacy-minimized input helper."""

from pathlib import Path
import runpy


REPO = Path(__file__).resolve().parent.parent
HELPER = runpy.run_path(str(REPO / "helper" / "bongo-input"))
paw_for_key = HELPER["paw_for_key"]

UPSTREAM_LEFT_KEYS = frozenset(
    [1, 2, 3, 4, 5, 6, 7, 15, 16, 17, 18, 19, 20, 29, 30, 31, 32, 33,
     34, 41, 42, 44, 45, 46, 47, 48, 56, 58, 125]
)


def main() -> int:
    assert HELPER["LEFT_KEYS"] == UPSTREAM_LEFT_KEYS
    assert paw_for_key(30) == "L"  # A
    assert paw_for_key(38) == "R"  # L
    assert paw_for_key(59) == "R"  # F1 is not in upstream's left set
    assert paw_for_key(63) == "R"  # F5 is not in upstream's left set
    assert paw_for_key(113) == "R"  # Unlisted media keys fall right upstream
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
