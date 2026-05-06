# C11-28: C11-25 follow-up: lifecycle hardening + observability

Follow-up to C11-25 review (synthesis-action.md Surface-to-user items S5/S6/S7/S8/S9/S11 + Evolutionary E3, deferred per operator scope decision).

Bundled into one ticket because all items touch the same surface lifecycle / metrics infrastructure. Triage when planning; can split into multiple PRs at impl time.

## S5 — 2 Hz sidebar metrics tick fans out per workspace

`VerticalTabsSidebar.body` re-evaluates per revision bump on the sidebar metric publisher. Critical-Claude flagged as Important. Needs an Instruments pass (Time Profiler / Animation Hitches) at scale (20–30 workspaces, mirroring the c11-26-followup conditions that surfaced the parent ticket).

## S6 — `takeSnapshot` callback can be eaten by WebKit

`WKWebView.takeSnapshot(with:completionHandler:)` has rare cases where the completion never fires. C11-25's hibernate path uses a DispatchGroup but no timeout — defensive fix to release the group after N seconds with an empty placeholder.

## S7 — `BrowserSnapshotStore` is unbounded

I2 (in C11-25's review fixes) closed the close-path leak. Bigger hygiene question is unbounded growth: each hibernate adds an NSImage; nothing evicts. Add an LRU cap, or pair with on-disk persistence so the in-memory cache can be bounded.

## S8 — `formatSurfaceMetrics` rounding edge can render "1024MB"

Cosmetic. The current threshold check renders "1024MB" instead of "1.0GB" at exactly 1024 MB. Adjust threshold to roll over at 1024.

## S9 — SPI unavailability not log-once

When `_webProcessIdentifier` returns nil (SPI removed in a future WebKit), c11 silently renders "—" for browser metrics with no diagnostic. Add `os_log` once per surface at first nil so the failure is visible in Console.app.

## S11 — `updateWorkspaceId` leaves stale lifecycle_state metadata

When a surface is moved between workspaces, the canonical `lifecycle_state` metadata key isn't cleared on the source workspace. Pre-existing surface-move infrastructure gap; surfaces only when lifecycle_state is read after a move.

## E3 — `surface.subscribe_lifecycle` socket method

Reframes C11-25 as "scheduler with observable transitions" — agents and Lattice/Mycelium consumers could subscribe to lifecycle events instead of polling. ~30 LoC. Defer until a concrete second consumer asks.

## Background

All items surfaced in C11-25's trident-code-review (synthesis-action.md, 2026-05-05). Operator deferred so C11-25 could ship.
