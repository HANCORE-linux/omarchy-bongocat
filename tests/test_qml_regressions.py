#!/usr/bin/env python3
"""Static regressions for QML lifecycle patterns not covered offscreen."""

from pathlib import Path
import re


REPO = Path(__file__).resolve().parent.parent
HANDLERS = ("onBarConfigChanged", "onShellConfigChanged")
DIRECT_STEPS = (
    "var service = root",
    "if (!service) return",
    "service.verifyPersistedSettings()",
    "service.syncFromShell()",
    "service.recoverPendingJournal()",
    "service.writePendingJournal()",
)


def shell_connections(source: str) -> str:
    start_marker = "  Connections {\n    target: root.shell\n"
    end_marker = "\n  }\n\n  Component.onCompleted:"
    start = source.index(start_marker)
    end = source.index(end_marker, start) + len("\n  }")
    return source[start:end]


def assert_self_contained_handlers(block: str) -> None:
    functions = list(re.finditer(r"\bfunction\s+(\w+)\s*\(", block))
    assert [match.group(1) for match in functions] == list(HANDLERS)

    for index, handler in enumerate(HANDLERS):
        start = functions[index].start()
        end = functions[index + 1].start() if index + 1 < len(functions) else len(block)
        body = block[start:end]
        cursor = 0
        for step in DIRECT_STEPS:
            position = body.find(step, cursor)
            assert position >= 0, f"{handler} must directly contain {step}"
            cursor = position + len(step)


def main() -> int:
    service = (REPO / "Service.qml").read_text()
    assert_self_contained_handlers(shell_connections(service))

    # Negative control: guards in the signal handlers do not make delegation
    # to another Connections-local helper safe during teardown.
    unsafe = """  Connections {
    target: root.shell
    function synchronize(service) {
      service.verifyPersistedSettings()
      service.syncFromShell()
      service.recoverPendingJournal()
      service.writePendingJournal()
    }
    function onBarConfigChanged() {
      var service = root
      if (!service) return
      synchronize(service)
    }
    function onShellConfigChanged() {
      var service = root
      if (!service) return
      synchronize(service)
    }
  }"""
    try:
        assert_self_contained_handlers(unsafe)
    except AssertionError:
        pass
    else:
        raise AssertionError("Connections-local helper regression was accepted")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
