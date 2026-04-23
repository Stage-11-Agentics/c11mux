# Contributing to c11 with your agent

c11 is agent-native. It was built with agents, is maintained with agents, and expects to be extended with agents. If you're here to help your agent help us, you're in the right place.

This doc is the agent-specific supplement to [`CONTRIBUTING.md`](../CONTRIBUTING.md). Read that first for the human-facing workflow (setup, hot reload, tests, PR template). This page covers the parts that are specific to having an agent in the driver's seat.

## Ground rules

- **Agent-authored PRs are welcome.** We don't gate on who held the keyboard. We gate on whether the change is correct, tested, and well-shaped.
- **You are still the author.** Review the diff before opening the PR. Understand the change well enough to answer review comments. An agent that can't be explained by its operator is a liability; a change its operator can defend is a contribution.
- **Signal agent involvement.** Add a `Co-Authored-By` trailer naming the agent(s) when they did meaningful work on the commit. It's honest, helps us calibrate review depth, and normalizes the practice.
- **Read before you write.** Agents that skip [`CLAUDE.md`](../CLAUDE.md), [`PHILOSOPHY.md`](../PHILOSOPHY.md), and the relevant files in [`skills/`](../skills/) consistently produce PRs that miss load-bearing invariants (threading rules, latency-sensitive paths, primitives-before-policy). Load the context first.

## Point your agent at the right files

Before your agent touches c11 source, make sure it's read these. They're terse, they're accurate, and they save review rounds.

| File | What it's for | Why your agent needs it |
|---|---|---|
| [`CLAUDE.md`](../CLAUDE.md) | Operational guardrails for agents working in this repo | Threading policy, focus-steal policy, latency-sensitive paths, test quality rules, submodule etiquette |
| [`PHILOSOPHY.md`](../PHILOSOPHY.md) | Why c11 is shaped the way it is | Keeps the agent from proposing features that violate "host and primitive, not intelligence layer" |
| [`skills/c11/SKILL.md`](../skills/c11/SKILL.md) | How to drive c11 from outside the process | Lets your agent use c11 itself while working — split panes, open a browser to validate, report status |
| [`skills/c11-hotload/SKILL.md`](../skills/c11-hotload/SKILL.md) | Build / reload loop | Keeps the agent from launching untagged debug builds that collide with your running session |
| [`skills/release/SKILL.md`](../skills/release/SKILL.md) | Release flow | Only load if the agent is touching release machinery |
| [`docs/DEVELOPMENT.md`](DEVELOPMENT.md) | Architecture tour | One-screen map of `Sources/` before the agent starts grepping blindly |
| [`docs/socket-api-reference.md`](socket-api-reference.md) | The socket API every c11 surface speaks | Essential for CLI, browser, or metadata changes |

### Pointing different agents at these files

How you load these into your agent's context is your problem, not c11's (see the "unopinionated about the terminal" principle in [`CLAUDE.md`](../CLAUDE.md)). A few patterns that work:

- **Claude Code** — `CLAUDE.md` and `AGENTS.md` (symlink to `CLAUDE.md`) are auto-loaded from the repo root. For deeper context, have the agent `Read` the linked files on demand. `skills/c11/SKILL.md` can be surfaced via the Skill tool if you have the c11 skill installed globally or per-repo.
- **Codex CLI** — `AGENTS.md` at the repo root is auto-loaded. For skills and reference docs, instruct the agent to fetch them as needed.
- **Other agents (Kimi, Gemini, custom)** — pass the file paths in the initial prompt or system message.

We maintain `AGENTS.md` as a symlink to `CLAUDE.md` so both Claude Code and Codex see the same instructions. If you're adding support for a new agent format that expects a different filename, prefer a symlink over a copy — drift between them is a footgun.

## The PR flow for agent-authored changes

The flow is identical to the human flow, with two additions:

1. **Bot review block.** After your agent's latest commit, paste the review-bot trigger block from [`.github/pull_request_template.md`](../.github/pull_request_template.md) as a PR comment. This invokes `@codex`, `@coderabbitai`, `@greptile-apps`, and `@cubic-dev-ai` for independent review. Resolve their feedback (or explain why it's wrong) before requesting human review.
2. **Validation evidence.** UI changes need a demo video. Behavior changes need enough test output, log snippets, or screenshots in the PR description that a reviewer can confirm the change worked without rebuilding locally. A confident PR description saves everybody time.

## Common failure modes

Patterns we've seen cause PR rework:

- **Missing the tag rule.** The agent runs `xcodebuild` or `open` on an untagged `c11 DEV.app` and hijacks the operator's running socket. Fix: always use `./scripts/reload.sh --tag <branch-slug>`. See [`skills/c11-hotload/SKILL.md`](../skills/c11-hotload/SKILL.md).
- **Adding main-thread work to a typing path.** `WindowTerminalHostView.hitTest()`, `TabItemView.body`, and `TerminalSurface.forceRefresh()` are called every keystroke. New allocations, `@ObservedObject` bindings, or `DispatchQueue.main.sync` in these spots cause visible typing lag.
- **Agent-side hook feature requests.** Proposals that require c11 to "ask the agent to write a file" or "call back to Claude" violate the "observe from outside — never hook into agents" principle in [`PHILOSOPHY.md`](../PHILOSOPHY.md). c11 stays agent-agnostic; reach for external observation (`c11 tree`, pane scrollback) plus a small local model instead.
- **Tests that read source text.** Tests that grep source files or assert on `Info.plist` shape get rejected. Verify observable runtime behavior through real executable paths.
- **Submodule commits on detached HEAD.** Your agent commits in `ghostty/` without pushing the submodule commit to `manaflow/main` first. The commit is orphaned; the parent pointer references a SHA nobody else can fetch. Push the submodule first, then bump the parent pointer.

## Tell us what your agent learned

If your agent hit a surprising pothole getting a PR landed — missing documentation, an unclear invariant, a skill file that didn't cover the case — open a small follow-up PR updating the docs. We'd rather fix the onboarding than watch the next agent trip on the same rock.

## Growing this page

This doc is the designated growing seam for c11's agent-facing contributor experience. If you find yourself wanting to tell every future agent-operator the same thing, add a section here. Good candidates:

- New agent platforms we've tested contributions from
- Skill-file patterns that worked well
- Agent-specific footguns we've seen in PRs
- Communication conventions (tagging, metadata, log formats) that make multi-agent review smoother

Keep it terse. This is the agent's briefing, not a textbook.
