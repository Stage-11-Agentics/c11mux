#!/usr/bin/env python3
"""
Concatenate Claude Code /export-ed chat markdowns into one C11-25 doc.

Drop your six raw export files in ./inbox/ with these names:
    01-orchestrator.md
    02-delegator.md
    03-plan.md
    04-impl.md
    05-review.md
    06-translator.md

Then run this script. Output: ./c11-25-full-chat.md.

This script does NOT parse the chat content — it appends the exports verbatim
with a tiny HTML-comment divider between them so the chat reads as raw as it
came out of Claude Code.
"""
from __future__ import annotations

import argparse
from pathlib import Path
import sys

HERE = Path(__file__).parent
DEFAULT_INBOX = HERE / "inbox"
DEFAULT_OUT = HERE / "c11-25-full-chat.md"

VIDEO = "https://stage11.ai/yc-demo-coding-session.mov"

# (filename in inbox/, role label, one-line blurb)
# Order = order they appear in the final doc. Add Review and Validate here
# when the operator hands those exports in; no renumbering needed.
SESSIONS = [
    ("orchestrator.md", "Orchestrator",
     "Operator-facing driver. Framed C11-25 from the operator's prompt, "
     "kicked off the delegator in a fresh worktree, watched phase agents, "
     "and handled mid-flight steering."),
    ("delegator.md", "Delegator",
     "Carved a per-ticket git worktree, spawned the phase agents in "
     "sibling surfaces, and ran the trident review pass."),
    ("plan.md", "Plan",
     "Implementation-plan agent. Read the ticket, surveyed the code, and "
     "produced the plan the Impl agent worked from."),
    ("impl.md", "Impl",
     "Implementation agent. Did the actual code work against the plan."),
    ("review.md", "Review",
     "Trident-review sibling. Executed the synthesis-action.md produced "
     "by the nine-agent parallel review pass."),
    # ("validate.md", "Validate",
    #  "Validation sibling. Ran the final verification pass against the impl."),
    ("translator.md", "Translator",
     "Localization sweep. Synced any new English strings into "
     "ja/uk/ko/zh-Hans/zh-Hant/ru in Resources/Localizable.xcstrings."),
]

HEADER_TEMPLATE = """---
title: "C11-25 Surface Lifecycle Performance — Full Chat Record"
ticket: C11-25
project: c11
date: 2026-05-04
video: {video}
sessions: {n_sessions}
---

# C11-25 — Surface Lifecycle Performance

**c11** is Stage 11's native macOS terminal multiplexer for the operator:agent pair — terminals, browsers, and markdown surfaces composed in one window, every surface addressable from a CLI/socket so many agents can work in parallel without the operator brokering each move. Lineage: tmux → cmux → c11.

**Trident code review** is the nine-agent parallel review pattern that makes work like this tractable. Nine agents read the same diff in parallel from different angles (correctness, performance, security, ergonomics, test coverage, and more), each writes findings to disk, and a synthesis pass merges them into a single `synthesis-action.md` that the Review sibling executes directly. In practice it is exceptionally effective — the parallel breadth catches issues a single reviewer routinely misses, and the synthesis-to-action handoff means findings land as code changes, not a wall of comments to triage.

## ▶ Watch the video first — really

A live-stream recording of **exactly this coding session** lives at **[{video}]({video})**.

We strongly recommend watching it before (or instead of) reading the transcript below. A team of agents works in parallel here — an Orchestrator, a Delegator, and a set of phase siblings — so the work is inherently non-linear: things happen simultaneously across surfaces, the operator steers mid-stream, and the trident review fans out across nine reviewers at once. A flat chat log linearizes all of that and is genuinely harder to follow than the screen recording, where you can see surfaces lighting up next to each other in real time.

The transcript is here for completeness and as a searchable record. But if you only have time for one thing: **watch the video.** It will make a lot more sense, a lot faster, and we hope it gives you a much clearer picture of how this kind of multi-agent work actually feels in practice.

**Flow:** Operator framed C11-25 in the **Orchestrator**. The **Delegator** carved a fresh git worktree and ran phase agents: **Plan** produced the implementation plan, **Impl** did the work, **Review** ran the trident pass and applied the synthesis, **Translator** localized any new English strings into the six supported locales. What follows is the raw chat record, exactly as exported from Claude Code.
"""


def main() -> int:
    if not INBOX.exists():
        INBOX.mkdir(parents=True)
        print(f"Created {INBOX} — drop the exported chat files in there and re-run.", file=sys.stderr)
        return 1

    parts: list[str] = [HEADER_TEMPLATE.format(video=VIDEO, n_sessions=len(SESSIONS))]
    missing: list[str] = []
    total = len(SESSIONS)

    for idx, (fname, role, blurb) in enumerate(SESSIONS, start=1):
        path = INBOX / fname
        divider = (
            "\n\n---\n\n"
            "<!-- ============================================================ -->\n"
            f"<!-- SESSION {idx} / {total} — {role}                              -->\n"
            f"<!-- {blurb}\n"
            "-->\n"
            "<!-- ============================================================ -->\n\n"
        )
        parts.append(divider)
        if path.exists():
            parts.append(path.read_text())
        else:
            missing.append(fname)
            parts.append(f"_(missing: {fname} — drop the export in inbox/ and re-run)_\n")

    OUT.write_text("".join(parts))
    size_kb = OUT.stat().st_size / 1024
    print(f"Wrote {OUT} ({size_kb:.1f} KB)")
    if missing:
        print("\nMissing exports (still placeholders in the output):", file=sys.stderr)
        for m in missing:
            print(f"  - inbox/{m}", file=sys.stderr)
    return 0


if __name__ == "__main__":
    sys.exit(main())
