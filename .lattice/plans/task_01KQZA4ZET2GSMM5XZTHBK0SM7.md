# C11-31: c11d cloud host: persistent daemon for remote workspaces

## Summary

Evolve `c11d` from a session-bound SSH helper into a persistent, first-class cloud host. The goal: provision a Hetzner / DigitalOcean / AWS box, run `c11d`, and use it from c11 like a local instance. No SSH dance, no tmux, no Mosh, no terminal emulator on the remote. Provision once, then your tabs and agents live there as readily as on the laptop in front of you. Leaving home stops costing you anything.

**Design doc:** `docs/c11d-cloud-host-design.md` (drafted alongside this ticket).

## Today

`c11d-remote` already exists — a Go daemon serving c11's v2 JSON-RPC over stdio, reached via `cmux ssh`. It handles PTY sessions with smallest-screen-wins resize, browser egress over SOCKS5/CONNECT, CLI relay, and structured error surfacing. See `docs/remote-daemon-spec.md` for the implemented surface.

Today's daemon is **session-bound**: launches when c11 establishes the SSH transport, dies when it detaches. Workspace state lives on the Mac. Provisioning is bring-your-own-host. No web/mobile reach.

## Scope (one ticket, multiple phases)

Operator preference: one big ticket rather than many small ones. Phases ship independently and are each useful on their own.

### P1 — Persistent daemon mode on an existing host
- `c11d serve --persistent` under systemd (Linux) / launchd (macOS).
- Reachable on the host's tailnet IP via mTLS (or signed token). `cmux ssh` remains as a second transport.
- Mac app gains "Connect to remote daemon…" alongside `cmux ssh`.
- Sessions survive client detach.

**Unlock:** "leave home, instances keep running" for anyone willing to do their own SSH/Tailscale setup.

### P2 — `c11 cloud init`
- One command provisions a box (Hetzner default; DO/AWS as plug-ins), joins tailnet, installs `c11d`, mirrors `~/.claude/` (skills + CLAUDE.md + settings) and a configured dotfile set, pre-installs Claude/Codex/Gemini CLIs and `gh`.
- `c11 cloud sync` reconciles without rebuilding. `c11 cloud destroy` is exactly that.

**Unlock:** P1's outcome in one command.

### P3 — Workspace state on the daemon (opt-in)
- For cloud-resident workspaces, `c11d` owns: surface manifests, sidebar telemetry, persistent agent identity / lifecycle wrappers.
- Mac app becomes a view; web client (P5) is another view.
- Local-only workspaces unchanged.

**Biggest architectural shift in the project.** Inverts state-of-record. May warrant its own design doc before implementation.

### P4 — Federated sidebar
- Multiple `c11d` hosts in one workspace.
- Each surface carries a host badge (e.g. `laptop`, `home-mac`, `hetzner-fra-1`).
- `c11 split --host hetzner-fra-1` targets explicitly; default targets workspace home host.
- `c11 tree` and `c11 send` traverse host boundaries transparently.

### P5 — `c11.web` thin client
- Browser client for the no-Mac case.
- xterm.js + minimal sidebar; no embedded browser pane.
- Mobile-shaped reduction: vertical surface list, tap-to-drill, push notifications when an agent blocks, voice-to-send.
- Explicit escape hatch, not a full replacement for the native app.

## Open questions (decide per phase)

1. **Repo sync model** (P2): git auto-fetch vs Mutagen-style continuous sync vs operator-managed clone. Bias: git auto-fetch with a per-workspace remote convention.
2. **State conflict model** (P3): when daemon is offline, do clients show a read-only cached view of last-known surfaces, or hide the workspace? Bias: read-only cached view with a "disconnected" badge.
3. **Multi-client editing** (P3): shared focus or per-client selection? Bias: per-client; surfaces are shared, focus is local.
4. **Default provider** (P2): Hetzner vs DigitalOcean for v1. Plug-in pattern for the rest.
5. **Daemon ↔ daemon traffic** (P4): direct or always through the client? Bias: always through client.
6. **Skill propagation scope** (P2): `~/.claude/skills/` only, or also project-scoped skills (e.g. `Stage11/.claude/skills/lattice-delegate/`)? Likely yes, scoped to synced repos.
7. **Scale-to-zero** (post-P5): hibernation when no clients attached and no agents running. Halves hobbyist cost; defer the design until the core path lands.

## Non-goals

- Renderer rewrite. Native macOS rendering (Ghostty, AppKit, sidebar, WKWebView browser pane) stays as-is.
- tmux replacement on the cloud side. `c11d` is a c11 daemon, not a general-purpose multiplexer.
- Removing `cmux ssh`. P1 makes persistent mode an additional transport.
- Auto-mirroring every remote TCP port to local loopback (already rejected for browser routing in `remote-daemon-spec.md` §4.4; same posture here).

## Existing assets

- `docs/c11d-cloud-host-design.md` — design doc (drafted alongside this ticket).
- `docs/remote-daemon-spec.md` — living spec for what already exists.
- `daemon/remote/` — Go module for the existing `c11d-remote` binary.

## Suggested first move

Spec P1 (persistent service mode): systemd/launchd unit, mTLS handshake, Mac app's "Connect to remote daemon…" UX, identity / known-hosts equivalent. Builds on the existing `c11d-remote` binary — mostly extending its lifecycle, not replacing it.
