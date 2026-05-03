import Foundation

// Thin CLI entry for `c11 health`. Wired from CLI/c11.swift.
// All parsing, scanning, and rendering lives in Sources/HealthCommandCore.swift
// so the main `c11` target (and c11Tests) can exercise the same code paths.

func runHealth(commandArgs: [String], jsonOutput: Bool) throws {
    let wantsJSON = jsonOutput || commandArgs.contains("--json")
    let now = Date()
    let window = HealthCollectionWindow(
        mode: .defaultLast24h,
        since: now.addingTimeInterval(-24 * 3600),
        until: now
    )
    let rails: Set<HealthEvent.Rail> = Set(HealthEvent.Rail.allCases)
    let events = collectHealthEvents(window: window, rails: rails)

    if wantsJSON {
        let data = try renderHealthJSON(
            events: events,
            window: window,
            rails: rails,
            warnings: []
        )
        if let text = String(data: data, encoding: .utf8) {
            print(text)
        }
        return
    }

    print(renderHealthTable(events), terminator: "")
}
