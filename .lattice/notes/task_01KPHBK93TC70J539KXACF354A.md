# CMUX-7 — Summonable guide agent for forking/modifying c11mux

Spike. The organism builds its own organs — make the path from "I want to change this behavior in c11mux" to "my fork is rebuilt and running" a summonable operator move, not an advanced one.

## Spike framing

c11mux is meant to be forkable infrastructure for hyperengineers, but the on-ramp from *using* it to *modifying* it is undocumented terrain. Clone, fork, find the right file, make the change, `./scripts/reload.sh --tag`, verify. Every step is learnable but not legible. This spike explores what a **summonable guide** looks like — a c11mux-aware agent any operator or agent can invoke from any pane to be walked through that chain.

## Voice

Match `docs/c11mux-voice.md` — internal register. lowercase default. punchy verbs. no onboarding warmth. the cli is an extension of the operator's cognition. do not reach for "let's get started!" or "great question!" — c11mux is the room the spike is already moving in.

## Exploration boundaries

Scope the spike to answer four questions. Each has a suggested direction — deviate if the investigation says otherwise.

### 1. Summoning surface — what invokes the guide?

Options to compare:

- **Claude skill** auto-loaded by env detection (pattern matches existing `skills/cmux/SKILL.md`). Lowest friction — the skill is already the c11mux seam for agents.
- **`cmux guide` subcommand** that spawns a claude-code pane with a curated prompt and the fork flow as context.
- **Slash command** (`/cmux-fork`) registered in `~/.claude/commands/`.

Lean: the skill is the canonical path (principle: "the skill file is the only outgoing touch"). A subcommand that launches claude-code with the skill pre-loaded is an orthogonal convenience that could ship later.

### 2. Grounding material — what does the guide know?

Minimum set the guide should reference:

- Project CLAUDE.md (build/reload commands, pitfalls, submodule workflow).
- `docs/ghostty-fork.md` (upstream-sync discipline).
- `docs/c11mux-voice.md` (so the guide produces voice-consistent copy when walking the operator through README/CHANGELOG edits).
- The repo structure (Sources/, Resources/, scripts/, ghostty/, vendor/bonsplit).
- `./scripts/reload.sh --tag` (the only sanctioned debug launch path).

Open: does the guide read these at runtime, or are key excerpts pre-loaded into the skill body? Trade-off is freshness vs. reliability under context limits.

### 3. One-shot walkthrough vs. persistent pair-programmer

Cut:

- **One-shot** — the operator runs the summon, the guide walks them through A→Z once, they end with a working tagged build. Cheap, easy to ship, easy to rerun.
- **Persistent** — the guide stays loaded for the session and picks up where the operator left off, tracking progress through fork → modify → reload → verify.

Lean: one-shot for spike v1. Persistent is a natural follow-up once we see what operators actually do with it.

### 4. Target persona

Explicit: an existing operator who already uses c11mux but hasn't yet modified it. *Not* a first-time user. The guide assumes c11mux is already launched and the operator is in a pane — it doesn't onboard.

## Spike deliverables

- **A plan doc** (`docs/c11mux-summonable-guide-plan.md`) with: chosen summoning surface + rationale, minimal grounding material list, one-shot walkthrough script, voice sample.
- **A runnable prototype** of whichever option wins — could be a new section in `skills/cmux/SKILL.md`, a new `skills/cmux-fork/SKILL.md`, or a `cmux guide` subcommand stub. One of the three, end-to-end.
- **A validation pass** — Atin summons the guide, walks through forking c11mux once, reports what felt off. Iterate once.

## Success criteria for "spike done"

1. An operator (or their agent) in a c11mux pane can summon the guide in one command.
2. The guide produces a linear walkthrough from fork → tagged reload → verify without requiring the operator to leave the pane.
3. The voice matches `docs/c11mux-voice.md`.
4. Forking c11mux feels like a normal operator move, not an advanced one — validated by Atin doing it once and reporting whether the friction is gone.

## Artifacts produced

- Plan doc (above).
- Runnable prototype (above).
- A decision recorded in `DECISIONS.md` (or equivalent) on which summoning surface is canonical going forward.

## Connects to

- The spike thesis: *the organism builds its own organs*. This ticket is one of the organs.
- CMUX-8 (YouTube setup examples): the guide and the videos are the two halves of the forkability story — the videos show what a spike looks like, the guide walks operators to the point where they can produce one.
- Existing skills architecture: `skills/cmux/`, `skills/cmux-browser/`, `skills/cmux-markdown/`, `skills/cmux-debug-windows/`.

## Non-goals

- Not a tutorial for people who've never used c11mux.
- Not a commit/PR workflow guide — that's a generic skill, not a c11mux organ.
- Not a replacement for the CLAUDE.md — the guide reads the CLAUDE.md; the operator-facing walkthrough is the product.

## Grooming pass 2026-04-18 by agent:claude-opus-4-7
Reshaped the dense paragraph stub into a proper spike structure (boundaries, success criteria, deliverables, artifact list, non-goals) and proposed leans for each open question while keeping them open.
