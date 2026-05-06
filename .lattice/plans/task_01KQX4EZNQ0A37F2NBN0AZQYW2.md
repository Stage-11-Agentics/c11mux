# C11-29: Parallel-agent fanout primitives: grid layout + batch RPC

## Motivation

Test agent populating a six-Claude/Codex workspace surfaced two missing primitives. Both block the canonical use case c11 is built for — parallel-agent fanout.

1. **No grid layout.** Building a 3×2 grid of agents took 5+ sequential `new-split` calls plus resize-cascade arithmetic that's brittle under the current `resize-pane --amount` semantics. The shape "N×M panes for N×M agents" should be one command.
2. **No batch RPC.** "Rename 6 surfaces + send prompts to 6 PTYs" is 12 separate socket round-trips, each a fresh process spawn + connect + auth. For orchestration scripts this dominates wall-clock.

This ticket adds both primitives in one pass since they share the same use case (parallel-agent setup) and the same caller pattern (orchestrator scripts spinning up sibling agents).

## Scope

### 1. `c11 new-workspace --grid <cols>x<rows>` (+ `--cell` for non-terminal cells)

Add to the existing `new-workspace` command surface — no new top-level `layout` namespace. A grid is a generated blueprint, and workspace already owns blueprints (`workspace apply`, `workspace new --blueprint`, `new-workspace --layout`).

```bash
c11 new-workspace --grid 3x2                              # six terminals
c11 new-workspace --grid 3x2 --cwd ~/proj                 # all rooted in ~/proj
c11 new-workspace --grid 3x2 --cell 3:markdown --cell 5:browser
```

**Semantics:**
- Cell numbering is 1-indexed, row-major from top-left.
- Cells default to terminal; `--cell <n>:<type>` overrides one cell at a time.
- Supported cell types: `terminal`, `markdown`, `browser`.
- **Cap: max 2 `browser` cells per grid.** Reject with a clear error if exceeded ("grid supports at most 2 browser cells; got N — use sequential `new-pane --type browser` for heavier browser workloads").
- Equal-sized cells (no per-cell sizing hints in v1).
- No per-cell titles or descriptions — structural only. Agents set their own at orient time.
- `--grid` and `--layout` are mutually exclusive. Optionally allow `--layout grid:3x2` as a parser shorthand for the same code path.
- Response envelope: same as `new-workspace --layout` today (`workspace_id`, `workspace_ref`, `window_id`, `window_ref`, `layout_result`).

**Implementation note:** synthesize a `WorkspaceApplyPlan` from the grid spec and route through the existing apply pipeline. Don't add a parallel layout engine.

### 2. `c11 batch < ops.json`

Single-process, single-socket-connection, single-auth dispatcher for a sequence of c11 commands.

**Wire format (stdin or `--file`):**

```json
{
  "workspace": "workspace:2",
  "ops": [
    {"cmd": "set-title",   "surface": "surface:1", "args": {"title": "Reviewer 1"}},
    {"cmd": "set-title",   "surface": "surface:2", "args": {"title": "Reviewer 2"}},
    {"cmd": "send",        "surface": "surface:1", "args": {"text": "pwd"}},
    {"cmd": "send-key",    "surface": "surface:1", "args": {"key": "enter"}}
  ]
}
```

Top-level `workspace` is optional — when present, ops inherit it unless they specify their own `workspace`.

**Semantics:**
- **Sequential execution.** No concurrency in v1. (If ever needed: per-op `"parallel": true` or a dependency graph — not a global flag. Out of scope here.)
- **Continue-by-default on errors.** Each op runs independently; one failure does not roll back prior successes.
- **`--stop-on-error` flag** opts into fail-fast: abort after the first failed op, leaving prior ops applied.
- **Op cap: 25 per batch in v1.** Reject larger batches with a clear error. Raise after we have field data on real usage.
- **Single auth.** Socket connects once, password check once. This is the primary win.

**Output format (stdout JSON array, one entry per op, in input order):**

```json
[
  {"ok": true,  "result": {"surface": "surface:1", "title": "Reviewer 1"}},
  {"ok": true,  "result": {"surface": "surface:2", "title": "Reviewer 2"}},
  {"ok": false, "error": "not_found: surface", "cmd_index": 2},
  {"ok": true,  "result": {}}
]
```

Process exit code: `0` if every op succeeded, non-zero otherwise.

**Op coverage in v1:** the commonly-batched commands — `set-title`, `set-description`, `rename-tab`, `set-metadata`, `set-status`, `set-progress`, `send`, `send-key`, `set-agent`, `log`. Lower priority for v1: `new-split`, `new-pane`, `new-surface` (these involve focus/refs that are easier to reason about one-at-a-time). Decide during impl whether to gate or include.

## Out of scope (v1)

- Per-cell sizing hints in `--grid`.
- Reshaping an existing workspace into a grid (use `c11 workspace apply` with a synthesized plan).
- Concurrency in `batch`.
- Batch op count > 25.
- `c11 layout` top-level namespace.

## Skill update (close-out)

When this lands, update `skills/c11/SKILL.md`:
- Add `--grid` to the "Create splits, panes, surfaces" section with one concrete example.
- Add a "Batch operations" subsection showing the JSON shape and one realistic six-pane orchestration example.
- Cross-link from the `references/orchestration.md` parallel-agent setup pattern.

## Why one ticket

Both primitives serve the same caller (orchestrator scripts setting up parallel agents) and tend to be used together (create grid, then batch-rename + batch-send to populate it). Splitting would create coordination overhead with no offsetting benefit; the implementation surfaces don't conflict.

## Discovery context

Surfaced 2026-05-05 by a test agent populating a six-agent test workspace; full feedback in conversation history. Key data points: 5+ sequential `new-split` calls + brittle resize math to land equal columns; 12 round-trips for a 6-pane rename + send sequence.
