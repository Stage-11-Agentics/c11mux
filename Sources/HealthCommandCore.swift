import Foundation

// Core for `c11 health`. Pure, testable: no UI, no socket, no Sentry SDK calls.
// The CLI shim at CLI/HealthCommand.swift wires this into the `c11 health` dispatch.

struct HealthEvent {
    enum Rail: String, CaseIterable {
        case ips
        case sentry
        case metrickit
        case sentinel
    }

    enum Severity: String {
        case crash
        case queued
        case metrickit
        case hang
        case resource
        case mixed
        case diagnostic
        case unclean_exit
    }

    let timestamp: Date
    let rail: Rail
    let severity: Severity
    let summary: String
    let path: String
}

struct HealthCollectionWindow {
    enum Mode: String {
        case sinceDuration = "since"
        case sinceBoot = "since-boot"
        case defaultLast24h = "default-24h"
    }

    let mode: Mode
    let since: Date
    let until: Date
}

/// Collect events across requested rails. Missing files or empty directories
/// must not produce an error: this command is read-only and has to be useful
/// on a machine where the producer code (sentinel, MetricKit subscription,
/// Sentry SDK) has never run.
///
/// `home` defaults to `NSHomeDirectory()` so the runtime test can pass a tmp dir.
func collectHealthEvents(
    window: HealthCollectionWindow,
    rails: Set<HealthEvent.Rail>,
    home: String = NSHomeDirectory()
) -> [HealthEvent] {
    return []
}

/// Default empty-result line when no events are present and no rail filter is in effect.
private let healthEmptyResultLine =
    "c11 health: nothing in the last 24h across ips, sentry, metrickit, sentinel."

func renderHealthTable(_ events: [HealthEvent]) -> String {
    if events.isEmpty {
        return healthEmptyResultLine + "\n"
    }
    return ""
}

func renderHealthJSON(
    events: [HealthEvent],
    window: HealthCollectionWindow,
    rails: Set<HealthEvent.Rail>,
    warnings: [String]
) throws -> Data {
    let iso = ISO8601DateFormatter()
    iso.formatOptions = [.withInternetDateTime, .withFractionalSeconds]

    var railCounts: [String: [String: Int]] = [:]
    for rail in HealthEvent.Rail.allCases where rails.contains(rail) {
        railCounts[rail.rawValue] = ["count": events.filter { $0.rail == rail }.count]
    }

    let eventsArray: [[String: Any]] = events.map { ev in
        [
            "timestamp": iso.string(from: ev.timestamp),
            "rail": ev.rail.rawValue,
            "severity": ev.severity.rawValue,
            "summary": ev.summary,
            "path": ev.path,
        ]
    }

    let payload: [String: Any] = [
        "window": [
            "since": iso.string(from: window.since),
            "until": iso.string(from: window.until),
            "mode": window.mode.rawValue,
        ],
        "rails": railCounts,
        "events": eventsArray,
        "warnings": warnings,
    ]

    return try JSONSerialization.data(
        withJSONObject: payload,
        options: [.prettyPrinted, .sortedKeys]
    )
}
