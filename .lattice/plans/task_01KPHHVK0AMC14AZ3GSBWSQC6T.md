# CMUX-17: Grooming pass — bring backlog plan notes up to complexity-matched fidelity

## Why

Most backlog plan notes today are 3-line stubs. That's adequate for a chore but leaves an agent dispatched against a feature, spike, or epic without enough context to do good work. The dispatch loop only works if the plan note is rich enough to brief a fresh agent.

## Scope

Walk every active ticket (status NOT in `in_progress`/`review`/`done`/`cancelled`), read the ticket and its current plan, and bring the plan note up to a fidelity that matches the type and complexity:

- **chore / cleanup** → ~5–15 lines: bullets of what to do, where, how to verify.
- **task** (typical) → ~30–80 lines: file paths, sequence of changes, test approach, rollback if any.
- **task** (high complexity, multi-PR) → ~80–200 lines: sequenced sections, hand-off points, what's deferred.
- **spike** → open questions, exploration boundaries, success criteria, what artifact the spike produces.
- **bug** → repro, suspected cause, fix approach, regression test.
- **epic** → break into sub-tickets via `lattice create` + `lattice link subtask_of`; the epic's plan summarizes them.

## Tickets to skip (already claimed by other agents)

- CMUX-2 (Tier 1 Phase 2 persistence — agent in flight)
- CMUX-9 (Custom theming spike — in progress)
- CMUX-13 (Trident plan review — agent in flight)
- CMUX-17 (this ticket)

## Hard constraints

- Do NOT change priorities, statuses, assignments, urgencies, or non-`subtask_of` links. This is a **fidelity pass**, not a re-ranking pass.
- Do NOT edit code. Only write to `.lattice/notes/*.md`.
- Use codebase + `docs/` + `CLAUDE.md` as source of truth — do not invent context.
- If a ticket genuinely needs human input before it can be planned, write that into the plan note and flag it in the closing report.

## Footer convention

Each touched note gets:

```
## Grooming pass 2026-04-18 by agent:claude-opus-4-7
<one-sentence note: "expanded from stub", "broke into 3 subtasks", "noted blocker on Y", etc.>
```

## Success criteria

- Every non-skipped active ticket has a plan note whose length and structure match its type/complexity.
- No stubs left on the board (unless a stub is genuinely the right fidelity, e.g. for a true single-line chore).
- Closing report enumerates: total touched, substantive expansions, problems surfaced, human-input needed.
