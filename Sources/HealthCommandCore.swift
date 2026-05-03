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
    var events: [HealthEvent] = []
    if rails.contains(.ips) {
        events.append(contentsOf: scanIPS(home: home, since: window.since))
    }
    if rails.contains(.sentry) {
        events.append(contentsOf: scanSentryQueued(home: home, since: window.since))
    }
    if rails.contains(.metrickit) {
        events.append(contentsOf: scanMetricKit(home: home, since: window.since))
    }
    return events.sorted { $0.timestamp > $1.timestamp }
}

// MARK: - IPS rail

/// Apple's CrashReporter ".ips" files start with a single-line JSON header,
/// then a newline, then a JSON payload. We parse only that first line.
struct IPSHeader {
    let incidentID: String?
    let bundleID: String?
    let bugType: String?
}

func parseIPSFirstLine(_ line: String) -> IPSHeader? {
    guard let data = line.data(using: .utf8),
          let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
    else { return nil }
    return IPSHeader(
        incidentID: obj["incident_id"] as? String,
        bundleID: obj["bundleID"] as? String,
        bugType: obj["bug_type"] as? String
    )
}

func scanIPS(home: String, since: Date) -> [HealthEvent] {
    let baseDir = "\(home)/Library/Logs/DiagnosticReports"
    let baseURL = URL(fileURLWithPath: baseDir)
    let fm = FileManager.default

    guard let topLevel = try? fm.contentsOfDirectory(
        at: baseURL,
        includingPropertiesForKeys: [.isDirectoryKey],
        options: [.skipsHiddenFiles]
    ) else { return [] }

    var events: [HealthEvent] = []

    for entry in topLevel {
        let isDir = (try? entry.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) ?? false
        let name = entry.lastPathComponent

        if isDir {
            guard name.hasPrefix("com.stage11.c11") else { continue }
            if let inside = try? fm.contentsOfDirectory(
                at: entry,
                includingPropertiesForKeys: nil,
                options: [.skipsHiddenFiles]
            ) {
                for url in inside where url.pathExtension == "ips" {
                    if let ev = ipsEventIfRecent(at: url, since: since) {
                        events.append(ev)
                    }
                }
            }
            continue
        }

        guard entry.pathExtension == "ips" else { continue }
        let stem = entry.deletingPathExtension().lastPathComponent
        guard stem.lowercased().contains("c11") else { continue }
        if let ev = ipsEventIfRecent(at: entry, since: since) {
            events.append(ev)
        }
    }

    return events
}

private func ipsEventIfRecent(at url: URL, since: Date) -> HealthEvent? {
    let fm = FileManager.default
    guard let attrs = try? fm.attributesOfItem(atPath: url.path),
          let mtime = attrs[.modificationDate] as? Date,
          mtime >= since
    else { return nil }

    let summary: String
    if let line = readFirstLine(of: url), let header = parseIPSFirstLine(line) {
        let bundle = header.bundleID ?? "?"
        let bug = header.bugType ?? "?"
        let inc = header.incidentID.map { String($0.prefix(8)) } ?? "?"
        summary = "\(bundle) bug_type=\(bug) (\(inc))"
    } else {
        summary = url.lastPathComponent
    }

    return HealthEvent(
        timestamp: mtime,
        rail: .ips,
        severity: .crash,
        summary: summary,
        path: url.path
    )
}

private func readFirstLine(of url: URL) -> String? {
    guard let handle = try? FileHandle(forReadingFrom: url) else { return nil }
    defer { try? handle.close() }
    let data = (try? handle.read(upToCount: 8192)) ?? Data()
    guard let text = String(data: data, encoding: .utf8) else { return nil }
    if let nl = text.firstIndex(of: "\n") {
        return String(text[..<nl])
    }
    return text
}

// MARK: - Sentry queued rail

/// Walks `<home>/Library/Caches/com.stage11.c11*/io.sentry/` recursively and
/// emits one event per file. Sentry-Cocoa typically writes envelopes under
/// `io.sentry/envelopes/`, but we don't make that assumption: any regular file
/// inside `io.sentry/` is treated as a queued event. Envelope contents are
/// never parsed.
func scanSentryQueued(home: String, since: Date) -> [HealthEvent] {
    let cacheURL = URL(fileURLWithPath: "\(home)/Library/Caches")
    let fm = FileManager.default

    guard let bundleDirs = try? fm.contentsOfDirectory(
        at: cacheURL,
        includingPropertiesForKeys: [.isDirectoryKey],
        options: [.skipsHiddenFiles]
    ) else { return [] }

    var events: [HealthEvent] = []

    for bundleDir in bundleDirs {
        let bundleName = bundleDir.lastPathComponent
        guard bundleName.hasPrefix("com.stage11.c11") else { continue }
        let isDir = (try? bundleDir.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) ?? false
        guard isDir else { continue }

        let sentryRoot = bundleDir.appendingPathComponent("io.sentry", isDirectory: true)
        guard fm.fileExists(atPath: sentryRoot.path) else { continue }
        events.append(contentsOf: walkSentryDir(sentryRoot, bundleName: bundleName, since: since))
    }

    return events
}

private func walkSentryDir(_ dir: URL, bundleName: String, since: Date) -> [HealthEvent] {
    let fm = FileManager.default
    guard let enumerator = fm.enumerator(
        at: dir,
        includingPropertiesForKeys: [.isRegularFileKey, .contentModificationDateKey],
        options: [.skipsHiddenFiles]
    ) else { return [] }

    var events: [HealthEvent] = []
    for case let url as URL in enumerator {
        guard let values = try? url.resourceValues(forKeys: [.isRegularFileKey, .contentModificationDateKey]),
              values.isRegularFile == true,
              let mtime = values.contentModificationDate,
              mtime >= since
        else { continue }

        events.append(HealthEvent(
            timestamp: mtime,
            rail: .sentry,
            severity: .queued,
            summary: "\(bundleName)/\(url.lastPathComponent)",
            path: url.path
        ))
    }
    return events
}

// MARK: - MetricKit rail

/// Filename grammar for files written by `CrashDiagnostics.persist` in
/// `Sources/SentryHelper.swift`:
///
///     <stamp>-<kind>.json
///
/// where `<stamp>` is `YYYY-MM-DDTHH-MM-SS.fffZ` (ISO 8601 with `:` replaced
/// by `-`, always UTC, fixed 24 chars) and `<kind>` is one of:
///   - `metric` (MXMetricPayload telemetry baseline; skipped in v1)
///   - `diagnostic` (MXDiagnosticPayload with no per-category counts)
///   - one or more of `crash<n>` / `hang<n>` / `cpu<n>` / `disk<n>` joined by
///     `-` in the fixed order crash, hang, cpu, disk.
struct MetricKitFilename {
    let timestamp: Date
    let kind: String
}

/// Returns nil for `metric` rows (per plan: skip telemetry baselines), nil
/// for unparseable stamps, and nil for malformed kind tokens.
func parseMetricKitFilename(_ name: String) -> MetricKitFilename? {
    guard name.hasSuffix(".json") else { return nil }
    let stem = String(name.dropLast(".json".count))

    // The stamp is exactly 24 characters: YYYY-MM-DDTHH-MM-SS.fffZ.
    let stampLength = 24
    guard stem.count > stampLength + 1 else { return nil }
    let stampEnd = stem.index(stem.startIndex, offsetBy: stampLength)
    let stampStr = String(stem[..<stampEnd])

    let afterStamp = stem[stampEnd...]
    guard afterStamp.first == "-" else { return nil }
    let kind = String(afterStamp.dropFirst())

    guard let date = parseFilenameSafeISO(stampStr) else { return nil }
    guard isValidMetricKitKind(kind) else { return nil }

    // Skip MXMetricPayload baselines: they aren't diagnostic events.
    if kind == "metric" { return nil }

    return MetricKitFilename(timestamp: date, kind: kind)
}

private func parseFilenameSafeISO(_ stamp: String) -> Date? {
    guard stamp.count == 24, stamp.last == "Z" else { return nil }
    var chars = Array(stamp)
    guard chars[10] == "T",
          chars[13] == "-",
          chars[16] == "-",
          chars[19] == "."
    else { return nil }
    chars[13] = ":"
    chars[16] = ":"
    let normalized = String(chars)
    let f = ISO8601DateFormatter()
    f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    return f.date(from: normalized)
}

private func isValidMetricKitKind(_ kind: String) -> Bool {
    if kind == "metric" || kind == "diagnostic" { return true }
    let tokens = kind.split(separator: "-").map(String.init)
    guard !tokens.isEmpty else { return false }
    return tokens.allSatisfy(isValidCategoryToken)
}

private func isValidCategoryToken(_ token: String) -> Bool {
    let prefixes = ["crash", "hang", "cpu", "disk"]
    for prefix in prefixes where token.hasPrefix(prefix) {
        let suffix = token.dropFirst(prefix.count)
        return !suffix.isEmpty && suffix.allSatisfy { $0.isNumber }
    }
    return false
}

private func metricKitSeverity(forKind kind: String) -> HealthEvent.Severity {
    if kind == "diagnostic" { return .diagnostic }
    let tokens = kind.split(separator: "-").map(String.init)
    let hasCrash = tokens.contains { $0.hasPrefix("crash") }
    let hasHang = tokens.contains { $0.hasPrefix("hang") }
    let hasResource = tokens.contains { $0.hasPrefix("cpu") || $0.hasPrefix("disk") }
    let categoryCount = [hasCrash, hasHang, hasResource].filter { $0 }.count
    if categoryCount > 1 { return .mixed }
    if hasCrash { return .crash }
    if hasHang { return .hang }
    if hasResource { return .resource }
    return .diagnostic
}

func scanMetricKit(home: String, since: Date) -> [HealthEvent] {
    let dir = URL(fileURLWithPath: "\(home)/Library/Logs/c11/metrickit")
    let fm = FileManager.default

    guard let files = try? fm.contentsOfDirectory(
        at: dir,
        includingPropertiesForKeys: nil,
        options: [.skipsHiddenFiles]
    ) else { return [] }

    var events: [HealthEvent] = []
    for url in files where url.pathExtension == "json" {
        guard let parsed = parseMetricKitFilename(url.lastPathComponent),
              parsed.timestamp >= since
        else { continue }
        events.append(HealthEvent(
            timestamp: parsed.timestamp,
            rail: .metrickit,
            severity: metricKitSeverity(forKind: parsed.kind),
            summary: parsed.kind,
            path: url.path
        ))
    }
    return events
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
