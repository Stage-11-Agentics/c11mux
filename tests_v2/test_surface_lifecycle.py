#!/usr/bin/env python3
"""C11-25 surface lifecycle smoke test.

Validates that the canonical `lifecycle_state` metadata key is wired
through the surface.set_metadata / surface.get_metadata socket path:

  - Accepted values: active, throttled, suspended, hibernated.
  - Rejected values: anything else, including any non-string.
  - Round-trips through the metadata store and is readable via
    surface.get_metadata.

Does NOT exercise the runtime hibernate dispatch end-to-end — that
requires triggering the operator menu, which lives outside the socket
PTY reach and is covered by the c11Tests Swift unit tests + a tagged-
build computer-use scenario in the Validate phase.

Per CLAUDE.md, never run locally — CI / VM only.
"""

from __future__ import annotations

import os
import sys
import time
from pathlib import Path
from typing import Any

sys.path.insert(0, str(Path(__file__).parent))
from cmux import cmux, cmuxError


SOCKET_PATH = os.environ.get("CMUX_SOCKET", "/tmp/cmux-debug.sock")

LEGAL_STATES = ["active", "throttled", "suspended", "hibernated"]


def _must(cond: bool, msg: str) -> None:
    if not cond:
        raise cmuxError(msg)


def _fresh_surface(c) -> tuple[str, str]:
    workspace_id = c.new_workspace()
    current = c._call("surface.current", {"workspace_id": workspace_id}) or {}
    surface_id = str(current.get("surface_id") or "")
    _must(bool(surface_id), f"surface.current returned no surface_id: {current}")
    return workspace_id, surface_id


def _run_legal_values(c) -> None:
    workspace_id, surface_id = _fresh_surface(c)
    try:
        for state in LEGAL_STATES:
            res = (
                c._call(
                    "surface.set_metadata",
                    {
                        "surface_id": surface_id,
                        "mode": "merge",
                        "source": "explicit",
                        "metadata": {"lifecycle_state": state},
                    },
                )
                or {}
            )
            applied = res.get("applied") or {}
            _must(
                applied.get("lifecycle_state") is True,
                f"lifecycle_state={state} should be accepted: {res}",
            )

            got = (
                c._call("surface.get_metadata", {"surface_id": surface_id})
                or {}
            )
            md = got.get("metadata") or {}
            _must(
                md.get("lifecycle_state") == state,
                f"lifecycle_state should round-trip as {state!r}: {md}",
            )
    finally:
        c.close_workspace(workspace_id)


def _run_rejects_unknown_value(c) -> None:
    workspace_id, surface_id = _fresh_surface(c)
    try:
        # The validator rejects anything outside the four enum values.
        try:
            c._call(
                "surface.set_metadata",
                {
                    "surface_id": surface_id,
                    "mode": "merge",
                    "source": "explicit",
                    "metadata": {"lifecycle_state": "frozen"},
                },
            )
        except cmuxError as err:
            msg = str(err)
            _must(
                "reserved_key_invalid_type" in msg or "lifecycle_state" in msg,
                f"unknown value should be rejected with reserved_key_invalid_type, got: {msg!r}",
            )
        else:
            raise cmuxError(
                "lifecycle_state='frozen' was accepted; the validator is not wired"
            )
    finally:
        c.close_workspace(workspace_id)


def _run_rejects_non_string(c) -> None:
    workspace_id, surface_id = _fresh_surface(c)
    try:
        try:
            c._call(
                "surface.set_metadata",
                {
                    "surface_id": surface_id,
                    "mode": "merge",
                    "source": "explicit",
                    "metadata": {"lifecycle_state": 1},
                },
            )
        except cmuxError as err:
            msg = str(err)
            _must(
                "reserved_key_invalid_type" in msg or "lifecycle_state" in msg,
                f"non-string value should be rejected, got: {msg!r}",
            )
        else:
            raise cmuxError(
                "lifecycle_state=1 was accepted; the validator is not wired"
            )
    finally:
        c.close_workspace(workspace_id)


def main() -> int:
    with cmux(SOCKET_PATH) as client:
        _run_legal_values(client)
        _run_rejects_unknown_value(client)
        _run_rejects_non_string(client)
    print("OK c11-25 surface lifecycle metadata roundtrip")
    return 0


if __name__ == "__main__":
    sys.exit(main())
