Phases 3 + 4 shipped in PR #27 (squash-merged at 6fcc31bc on 2026-04-19), completing the four-phase scope of CMUX-11.

Acceptance criteria check (agent-verified against the merged tree):

1. Phase 3 persists via SessionPaneLayoutSnapshot extension, additive-optional, schema stays v1: SessionPersistence.swift adds optional id / metadata / metadataSources fields with `= nil` defaults; PaneMetadataPersistenceTests.testPrePhase3SnapshotDecodesCleanlyWithoutMetadataFields verifies pre-Phase-3 snapshots decode cleanly.

2. Restore rehydrates the in-memory store on app launch: Workspace.restorePaneMetadataFromSnapshot pairs each leaf with its freshly minted PaneID by tree position and calls PaneMetadataStore.restoreFromSnapshot under the new pane UUID.

3. Autosave fingerprint includes paneMetadataStoreRevision: TabManager.sessionAutosaveFingerprint folds in PaneMetadataStore.shared.currentRevision() next to the surface counter, so pane-only writes flush on the same 8s cadence.

4. 64 KiB per-pane cap preserved on restore (silent rejection): Workspace.restorePaneMetadataFromSnapshot now applies PersistedMetadataBridge.enforceSizeCap before decode and filters metadataSources to surviving keys; testRestoreCapDropsOversizedKeyAndAlignsSources covers the call shape end-to-end. Save-side cap unchanged.

5. Precedence (explicit > declare > osc > heuristic) preserved on restore: testRestoreFromSnapshotPreservesNonExplicitSourceAttribution confirms a .declare value from a snapshot stays .declare and is NOT promoted to .explicit, matching the surface-store contract.

6. Phase 4 skill cross-reference: 9 added lines in skills/cmux/SKILL.md ("Pane-layer lineage" subsection) covering --pane writes, read-then-write via prior_values, the :: rules (pointing back to surface convention rather than re-documenting), and the /clear cue. Cross-reference shape, not re-documentation, per ticket.

Trident review (9 reviewers, 3 syntheses) ran post-PR; all substantive findings closed in commit 520ea766 before merge:
- Blocker (Claude-Critical + Codex-Standard convergence): rollback gate `continue` skipping pane clear in debugForceMetadataSaveAndLoad — fixed by lifting both clears above the gate and walking live pane IDs for symmetry.
- Important (Codex unique): restore-side 64KiB cap — addressed (item 4 above).
- Important (Claude-Critical): DEBUG log for unparseable bonsplit pane id — added.
- Potential (Gemini x2): comment accuracy on SessionPaneLayoutSnapshot.id and Workspace.prunePaneMetadata — corrected.

Builds green: `xcodebuild -scheme cmux build` and `xcodebuild -scheme cmux-unit build-for-testing` (cmuxTests.xctest produced with PaneMetadataPersistenceTests.swift compiled in). XCTest + tests_v2 socket-test runs deferred to CI per repo policy. Non-macOS CI checks (web-typecheck, remote-daemon-tests, workflow-guard-tests) green; macOS jobs failed with the known bonsplit-submodule-clone infrastructure error — bypassed via --admin --squash per project convention.

Trident review pack archived at notes/trident-review-CMUX-11-pack-20260419-0304/.