# WorkspaceApplyPlan schema (v1)

Reference for the JSON shape accepted by `workspace.apply`, emitted by
`workspace.export_blueprint`, and embedded inside `WorkspaceSnapshotFile`.
All fields use snake_case wire names.

## Top-level envelope

```json
{
  "version": 1,
  "workspace": { ... },
  "layout": { ... },
  "surfaces": [ ... ]
}
```

| Field | Type | Required | Notes |
|-------|------|----------|-------|
| `version` | int | yes | Must be `1` |
| `workspace` | WorkspaceSpec | yes | Workspace-level settings |
| `layout` | LayoutTreeSpec | yes | Pane/split tree |
| `surfaces` | SurfaceSpec[] | yes | Keyed by plan-local id |

## WorkspaceSpec

```json
{
  "title": "My workspace",
  "custom_color": "#C0392B",
  "working_directory": "/Users/me/project",
  "metadata": { "key": "value" }
}
```

All fields optional. `custom_color` is a hex string (`#RRGGBB`).
`metadata` values must be strings.

## LayoutTreeSpec

A recursive union: either a `pane` leaf or a `split` node.

### Pane leaf

```json
{ "type": "pane", "pane": { "surfaceIds": ["s1", "s2"], "selectedIndex": 0 } }
```

`selectedIndex` is optional; omit to preserve focus as-is.

### Split node

```json
{
  "type": "split",
  "split": {
    "orientation": "horizontal",
    "dividerPosition": 0.6,
    "first": { ... },
    "second": { ... }
  }
}
```

`orientation`: `"horizontal"` (side by side) or `"vertical"` (top/bottom).
`dividerPosition`: float in `(0, 1)`.

## SurfaceSpec

```json
{
  "id": "s1",
  "kind": "terminal",
  "title": "main",
  "description": "Primary shell",
  "working_directory": "/Users/me/project",
  "command": "echo hello",
  "url": "https://example.com",
  "file_path": "/Users/me/notes.md",
  "metadata": { "terminal_type": "claude-code" },
  "pane_metadata": { "mailbox.task": "CMUX-37" }
}
```

| Field | Kind | Notes |
|-------|------|-------|
| `id` | all | Plan-local stable id. Appears in `ApplyResult.surfaceRefs` |
| `kind` | all | `"terminal"`, `"browser"`, or `"markdown"` |
| `title` | all | Written via `setPanelCustomTitle` |
| `description` | all | Written to surface metadata under `description` key |
| `working_directory` | terminal | Shell launch directory; ignored (warning) on browser/markdown |
| `command` | terminal | Sent as text once the surface is ready |
| `url` | browser | Initial navigation URL |
| `file_path` | markdown | Absolute path to the markdown file |
| `metadata` | all | Surface-scoped key/value pairs (`SurfaceMetadataStore`) |
| `pane_metadata` | all | Pane-scoped key/value pairs; only the first surface per pane writes |

`metadata` and `pane_metadata` values must be JSON-serialisable. Non-string
values on the reserved `mailbox.*` pane namespace are dropped with a warning.

## ApplyResult

```json
{
  "workspaceRef": "workspace:<uuid>",
  "surfaceRefs": { "s1": "surface:<uuid>", "s2": "surface:<uuid>" },
  "paneRefs": { "s1": "pane:<uuid>" },
  "warnings": [],
  "failures": []
}
```

`failures` entries: `{ "code": "...", "step": "...", "message": "..." }`.
