import Foundation

// Thin CLI entry for `c11 health`. Wired from CLI/c11.swift.
// All parsing, scanning, and rendering lives in Sources/HealthCommandCore.swift
// so the main `c11` target (and c11Tests) can exercise the same code paths.

func runHealth(commandArgs: [String], jsonOutput: Bool) throws {
    let opts: HealthCLIOptions
    do {
        opts = try parseHealthCLIArgs(commandArgs)
    } catch let error as HealthCLIError {
        FileHandle.standardError.write(Data("c11 health: \(error.description)\n".utf8))
        throw CLIError(message: error.description)
    }

    let wantsJSON = jsonOutput || opts.json
    let now = Date()
    let since: Date
    switch opts.mode {
    case .sinceDuration:
        since = now.addingTimeInterval(-opts.windowDuration)
    case .sinceBoot:
        since = bootTime()
    case .defaultLast24h:
        since = now.addingTimeInterval(-24 * 3600)
    }
    let window = HealthCollectionWindow(mode: opts.mode, since: since, until: now)

    let allRails: Set<HealthEvent.Rail> = Set(HealthEvent.Rail.allCases)
    let rails: Set<HealthEvent.Rail> = opts.railFilter.map { [$0] } ?? allRails

    let home = NSHomeDirectory()
    let events = collectHealthEvents(window: window, rails: rails, home: home)

    let metrickitCount = events.filter { $0.rail == .metrickit }.count
    let sentryCount = events.filter { $0.rail == .sentry }.count
    let bundleVersion = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String

    var warnings: [String] = []
    if rails.contains(.metrickit),
       let w = metricKitBaselineWarning(
        home: home,
        bundleVersion: bundleVersion,
        metricKitCount: metrickitCount
       ) {
        warnings.append(w)
    }
    if rails.contains(.sentry),
       let w = telemetryAmbiguityFooter(home: home, sentryCount: sentryCount) {
        warnings.append(w)
    }

    if wantsJSON {
        let data = try renderHealthJSON(
            events: events,
            window: window,
            rails: rails,
            warnings: warnings
        )
        if let text = String(data: data, encoding: .utf8) {
            print(text)
        }
        return
    }

    print(renderHealthTable(events, warnings: warnings), terminator: "")
}
