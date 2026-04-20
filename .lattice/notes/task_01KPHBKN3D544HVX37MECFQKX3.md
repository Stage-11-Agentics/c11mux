# CMUX-8 — c11mux setup examples: YouTube recordings + README showcase

Task. The README's current shape shows *what* c11mux is; this ticket shows *what it's for*.

## The intent in one line

An operator landing on the repo sees, within 30 seconds, the texture of running a real spike — parallel agents, branch-per-agent, sidebar loaded, browser pane live.

## What to record

Not demos of splitting a terminal. Recordings of a hyperengineer running a real spike. Speech-to-text and typing both, because that's the actual operating mode. Complex multi-pane workspaces with multiple parallel agents: claude-code, codex, kimi — the works.

### Proposed 3–5 videos (final count Atin's call)

1. **Multi-agent code review.** 4–6 panes, one per model reviewing the same diff, sidebar status pills firing as each completes. Demonstrates: parallel agents, sidebar telemetry, `cmux tree` spatial reasoning.
2. **Branch-per-agent spike.** Three agents on three branches of the same feature, browser pane showing the PR UI as one lands. Demonstrates: workspace isolation, embedded browser validation loop.
3. **Fork-and-modify a c11mux behavior.** Operator changes something in c11mux itself, `./scripts/reload.sh --tag`, validates the tagged build. Demonstrates: forkability, the tagged-reload discipline. Pairs naturally with CMUX-7's summonable guide.
4. **Lattice-driven workflow.** Tickets, plan notes, agent claims showing how the parallel agents coordinate through Lattice. Demonstrates: the content primitive beneath the multiplexer.
5. **Browser-loop validation.** Embedded browser driving a real web task end-to-end (form submit, state check, screenshot). Demonstrates: `cmux browser` as the validation tool of record when inside c11mux.

Atin's call on which 3–5 to record and in what order. Atin is the hyperengineer in the videos — nobody else's workflow reads as authentic.

## Deliverables

- **3–5 YouTube recordings** uploaded to the Stage 11 / c11mux channel (unlisted or public per Privacy-by-default — default to unlisted, flip to public when Atin says so).
- **README section** with thumbnails and links, plus a one-paragraph write-up for each video: what's happening, why, which c11mux primitives are in play.
- **Optional: example workspace configs / manifests** for operators to copy. If a `cmux workspace export` primitive exists or is close, wire it in; otherwise defer.

## Voice

Match `docs/c11mux-voice.md`. Corporate-like surface in the README section, but internal register voltage:

- no "get started today!"
- no onboarding warmth
- lowercase default in headings/copy where it fits the rest of the README
- load-bearing vocabulary: `hyperengineer`, `spike`, `surface`, `pane`, `workspace`, `agent`. do not substitute `user`, `developer`, `power user`.
- verbs of forward motion: spawn, deploy, declare, ship, cut, spike, forge.

## Execution sequence

1. Atin shortlists the 3–5 videos from the proposals above (or replaces them).
2. Record each as a single unedited take where possible. Re-take if tooling stumbles, not if speech does — the stumble is part of operator cadence.
3. Upload as unlisted. Each video needs a title in c11mux voice, not a corporate demo title.
4. Draft README section (thumbnails + links + paragraph per video) in a feature branch.
5. Atin reviews; iterate on voice once.
6. Land on main, flip videos to public if Atin signs off.

## Open questions

- [ ] Channel: Stage 11 umbrella or c11mux-specific?
- [ ] Thumbnails: Midjourney in the Gregorovitch visual aesthetic, or frame captures, or hybrid?
- [ ] Closed captions: auto-generated or hand-polished? STT in the recordings means the captions will be imperfect by default.
- [ ] Cross-linking: do the videos link back to CMUX-7's summonable guide once that ships?

## Non-goals

- Not a "getting started" tutorial — that's corporate-register and explicitly out of voice.
- Not splitting-a-terminal demos. Every recording shows real spike work, not primitive exercises.
- Not Atin narrating features — narrate the spike, not the multiplexer.

## Grooming pass 2026-04-18 by agent:claude-opus-4-7
Reshaped the dense paragraph stub into a video-by-video proposal, explicit voice constraints pulled from the voice doc, a six-step execution sequence, and open questions for Atin to call.
