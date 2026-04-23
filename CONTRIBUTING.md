# Contributing to c11

Thanks for considering a contribution. c11 is built by a small team and a rotating cast of their agents — outside PRs from humans and from humans-with-agents are both welcome, and both read the same way to us.

Start here, skim the links at the bottom for depth.

## Before you start

- **Read [PHILOSOPHY.md](PHILOSOPHY.md)** if your change touches product shape or primitives. c11 has strong opinions about staying unopinionated; knowing where those opinions live saves review rounds.
- **Glance at [CLAUDE.md](CLAUDE.md)** for operational guardrails — testing policy, submodule etiquette, latency-sensitive code paths, socket threading rules. CLAUDE.md is written for agents but it's accurate, terse, and useful to humans too.
- **Check open issues and the `TODO.md` / `C11_TODO.md` files** before opening a feature PR. Some ideas are intentionally parked.
- **File an issue first** for anything non-trivial. A two-line sketch of the approach in an issue is much cheaper than a rejected 800-line PR.

## Prerequisites

- macOS 14+ (Sonoma or later)
- Xcode 15+
- [Zig](https://ziglang.org/) (`brew install zig`) — needed to build the bundled Ghostty as an xcframework
- Git with submodule support (stock git is fine)

## Getting the source

```bash
git clone --recursive https://github.com/Stage-11-Agentics/c11.git
cd c11
./scripts/setup.sh
```

`setup.sh` initializes submodules (ghostty, bonsplit, homebrew-c11), builds `GhosttyKit.xcframework`, and sets up symlinks. Run it once, and re-run it if submodules change.

## The hot-reload loop

The day-to-day workflow is `./scripts/reload.sh`, which builds and launches a Debug app. **Always use `--tag`** — it gives your build its own name, bundle ID, socket, and DerivedData path so it doesn't fight with a co-located instance:

```bash
./scripts/reload.sh --tag my-branch-slug
```

Relevant variants:

| Script | What it does |
|---|---|
| `./scripts/reload.sh --tag <tag>` | Build + launch Debug, isolated (the default) |
| `./scripts/reloadp.sh` | Build + launch Release (kills running c11 first) |
| `./scripts/reloads.sh` | Build + launch Release as "c11 STAGING" |
| `./scripts/rebuild.sh` | Clean rebuild |

Full detail and gotchas live in [`skills/c11-hotload/SKILL.md`](skills/c11-hotload/SKILL.md).

## Running tests

c11 has three test suites. Order of escalation:

1. **Swift unit tests** (`c11Tests/`) — `xcodebuild -scheme c11-unit` or run them from Xcode. No app launch, fast.
2. **Python socket tests** (`tests_v2/`) — these attach to a running c11 instance over its socket. Launch a tagged Debug build first (`./scripts/reload.sh --tag testing`), then point the test runner at that build's socket:
   ```bash
   C11_SOCKET=/tmp/c11-debug-testing.sock ./scripts/run-tests-v2.sh
   ```
   Never run these against an untagged build while another c11 instance is also running — you will collide with it on `/tmp/c11.sock`.
3. **E2E / UI tests** (`c11UITests/`) — heavyweight, prefer running these on CI via `gh workflow run test-e2e.yml`. You can run them locally but they're slow and occasionally flaky on low-RAM machines.

> **Note for agent contributors working inside a live c11 session:** `CLAUDE.md` says "never run tests locally" — that rule exists because an agent launching an untagged debug build will hijack the operator's running socket. It does *not* apply to a human on their own machine running their own tests. When in doubt, use `--tag`.

## Opening a pull request

### Commit style

- **New commits, not amends.** If a pre-commit hook fails, fix it and push a new commit — don't rewrite history the reviewer might have already pulled.
- Write messages that explain *why*, not *what*. The diff already shows what.
- Sign off with your name as the git author; Co-Authored-By trailers for agents are encouraged when agents did meaningful work on the change.
- If your PR touches code that came from upstream [cmux](https://github.com/manaflow-ai/cmux), call it out so we can decide whether to also float the fix upstream. See the "cmux ↔ c11 relationship" section in [CLAUDE.md](CLAUDE.md).

### The PR template and review bots

Every PR uses [`.github/pull_request_template.md`](.github/pull_request_template.md). The important parts:

- **Demo video** for UI / behavior changes. A 20-second screen capture saves five rounds of review.
- **Review-bot trigger block.** After your latest commit, paste the `@codex review` / `@coderabbitai review` / etc. block as a PR comment to kick off automated reviewers. Resolve their feedback (or explain why not) before a human reviews.

### UI changes need a demo

We don't merge UI changes without a video. It's faster than prose, catches regressions reviewers wouldn't notice from the diff, and is the only way to verify typing-latency-sensitive paths didn't regress.

### Localization

c11 ships in English plus six translations (ja, uk, ko, zh-Hans, zh-Hant, ru). All strings live in `Resources/Localizable.xcstrings`.

- **Author English only.** Use `String(localized: "key.name", defaultValue: "English text")` at every user-facing call site. Don't hand-write the non-English values in product code.
- **Translations come after.** A follow-up pass syncs `Localizable.xcstrings` across the six locales. If your PR adds new English strings, flag that in the description so we know to schedule the translation sync.

### Code quality guardrails

A few areas have strict rules. If you're editing near any of these, read the full note in [`CLAUDE.md`](CLAUDE.md):

- **Typing-latency-sensitive paths** (e.g., `WindowTerminalHostView.hitTest()`, `TabItemView`, `TerminalSurface.forceRefresh()`). Extra allocations or main-thread work here are visible as typing lag.
- **Socket command threading.** Telemetry hot paths (`report_*`, status / progress updates) must not hop `DispatchQueue.main.sync`. Default new socket commands to off-main handling unless you have a concrete reason otherwise.
- **Socket focus policy.** Socket commands must not steal app focus — only explicit focus-intent commands (`window.focus`, `surface.focus`, etc.) may change selection.
- **Test quality.** Tests must verify observable runtime behavior. Do not add tests that grep source text, read `Info.plist`, or assert on AST shape. If a behavior isn't exercisable yet, add a seam first and test through it.

## Working on the ghostty submodule

The `ghostty` submodule points at [`manaflow-ai/ghostty`](https://github.com/manaflow-ai/ghostty) — a fork of upstream Ghostty with c11-specific patches.

```bash
cd ghostty
git checkout -b my-ghostty-feature
# make changes
git add .
git commit -m "Description of changes"
git push manaflow my-ghostty-feature
```

Then bump the submodule pointer in the parent repo:

```bash
cd ..
git add ghostty
git commit -m "Bump ghostty submodule"
```

**Always push the submodule commit to `manaflow/main` (or a branch on the fork) before committing the parent pointer.** A detached-HEAD submodule commit is orphaned and lost.

Conflict notes and fork status live in [`docs/ghostty-fork.md`](docs/ghostty-fork.md) and [`docs/upstream-sync.md`](docs/upstream-sync.md).

## Contributing with your agent

c11 is agent-native — we expect a lot of contributions to involve one. If you're bringing an agent to help, give it a look at [`docs/contributing-with-your-agent.md`](docs/contributing-with-your-agent.md) before you hand it the keyboard. It covers how to point the agent at the right context files and how the PR review flow works for agent-authored changes.

## Security

Please don't open public issues for security bugs. See [`SECURITY.md`](SECURITY.md) for the private disclosure flow.

## Code of Conduct

By participating in this project you agree to abide by the [Code of Conduct](CODE_OF_CONDUCT.md). Unkindness slows everybody down.

## License

By contributing, you agree that your changes are licensed under the project's GNU Affero General Public License v3.0 or later (`AGPL-3.0-or-later`). See [`LICENSE`](LICENSE) and [`NOTICE`](NOTICE) for details and upstream attribution.

## Where to go next

- [`PHILOSOPHY.md`](PHILOSOPHY.md) — why c11 is shaped the way it is
- [`CLAUDE.md`](CLAUDE.md) — operational notes, latency-sensitive paths, testing policy
- [`docs/DEVELOPMENT.md`](docs/DEVELOPMENT.md) — architecture tour, where things live in `Sources/`
- [`docs/socket-api-reference.md`](docs/socket-api-reference.md) — the socket API every c11 surface speaks
- [`skills/c11/SKILL.md`](skills/c11/SKILL.md) — the agent-facing guide to driving c11 (useful for humans too)
