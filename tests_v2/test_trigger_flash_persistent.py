#!/usr/bin/env python3
"""CMUX-10: persistent flash + color override + cancel-flash round-trip.

Connects to a tagged-build socket per CLAUDE.md (do not launch an untagged
``c11 DEV.app``). The test exercises:

  * one-shot ``surface.trigger_flash`` (control case)
  * persistent variant writes ``flash_state=persistent`` to surface metadata
  * cancel clears the metadata key
  * malformed ``--color`` is rejected with ``invalid_argument``

Visual assertions are deferred to the Validate phase; this is a state /
contract round-trip only.
"""

from __future__ import annotations

import os
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).parent))
from cmux import cmux, cmuxError


SOCKET_PATH = (
    os.environ.get("C11_SOCKET")
    or os.environ.get("CMUX_SOCKET")
    or "/tmp/cmux-debug.sock"
)


def _must(cond: bool, msg: str) -> None:
    if not cond:
        raise cmuxError(msg)


def main() -> int:
    with cmux(SOCKET_PATH) as c:
        ident = c.identify()
        focused = ident.get("focused") or {}
        surface_id = focused.get("surface_id")
        _must(bool(surface_id), f"identify should return a focused surface_id: {focused}")

        # 1. One-shot trigger (control case): no metadata side effect.
        result = c._call("surface.trigger_flash", {"surface_id": surface_id})
        _must(result.get("surface_id") == surface_id, f"one-shot: surface_id round-trip: {result}")
        _must(result.get("persistent") is False, f"one-shot: persistent flag should be False: {result}")

        # 2. Persistent trigger writes flash_state=persistent.
        result = c._call(
            "surface.trigger_flash",
            {"surface_id": surface_id, "persistent": True},
        )
        _must(result.get("persistent") is True, f"persistent: result echoes flag: {result}")

        meta = c._call("surface.get_metadata", {"surface_id": surface_id}) or {}
        meta_dict = meta.get("metadata") or {}
        _must(
            meta_dict.get("flash_state") == "persistent",
            f"persistent: flash_state should be 'persistent', got {meta_dict.get('flash_state')!r}",
        )

        # 3. Color override is honored.
        result = c._call(
            "surface.trigger_flash",
            {"surface_id": surface_id, "color": "#FF00FF"},
        )
        _must(result.get("surface_id") == surface_id, f"color: surface_id round-trip: {result}")

        # 4. Malformed color is rejected with invalid_argument.
        try:
            c._call("surface.trigger_flash", {"surface_id": surface_id, "color": "not-a-hex"})
        except cmuxError as e:
            _must("invalid_argument" in str(e) or "hex" in str(e).lower(), f"bad color: expected invalid_argument-ish error, got: {e}")
        else:
            raise cmuxError("bad color: expected error, got success")

        # 5. cancel_flash clears the metadata key.
        result = c._call("surface.cancel_flash", {"surface_id": surface_id})
        _must(result.get("surface_id") == surface_id, f"cancel: surface_id round-trip: {result}")

        meta = c._call("surface.get_metadata", {"surface_id": surface_id}) or {}
        meta_dict = meta.get("metadata") or {}
        _must(
            "flash_state" not in meta_dict,
            f"cancel: flash_state should be cleared, got {meta_dict.get('flash_state')!r}",
        )

        # 6. cancel_flash is idempotent (no error on a surface with no active flash).
        result = c._call("surface.cancel_flash", {"surface_id": surface_id})
        _must(result.get("surface_id") == surface_id, f"cancel idempotent: {result}")

    print("test_trigger_flash_persistent: OK")
    return 0


if __name__ == "__main__":
    sys.exit(main())
