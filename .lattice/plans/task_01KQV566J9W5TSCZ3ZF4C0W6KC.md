# C11-27: C11-25 follow-up: Hibernate workspace UX (S2+S3)

Follow-up to C11-25 review (synthesis-action.md Surface-to-user items S2 and S3, deferred per operator scope decision).

## S2 — In-place Resume affordance on hibernated placeholder

When a workspace is hibernated, its browser surfaces show a static NSImage placeholder. Right now the only way to resume is right-clicking the workspace tab in the sidebar (or using the App menu bar's Workspace → Resume Workspace). There's no in-place "click to resume" affordance on the placeholder itself.

Recommended: a tap target overlay on the placeholder NSImageView. ~5 LoC of overlay; the design (icon vs. full card; size; hover state) needs operator input.

## S3 — Workspace-level Hibernate doesn't honor multi-selection

Sibling sidebar commands (Close Workspace, Mark Read/Unread) operate on the selected set when multiple workspaces are selected. Hibernate Workspace currently operates only on the right-clicked workspace.

Reasonable people can disagree on whether this should change — flagging for operator preference.

## Background

Both items surfaced in C11-25's trident-code-review (synthesis-action.md, 2026-05-05). Operator deferred to follow-up ticket so C11-25 could ship.
