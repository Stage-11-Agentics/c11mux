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
    if rails.contains(.sentinel) {
        events.append(contentsOf: scanLaunchSentinel(home: home, since: window.since))
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

// MARK: - Flags + boot time

enum HealthCLIError: Error, CustomStringConvertible {
    case mutuallyExclusiveSinceFlags
    case missingValue(flag: String)
    case invalidSinceValue(String)
    case unknownRail(String)
    case unknownFlag(String)

    var description: String {
        switch self {
        case .mutuallyExclusiveSinceFlags:
            return "--since and --since-boot are mutually exclusive"
        case .missingValue(let flag):
            return "\(flag) requires a value"
        case .invalidSinceValue(let v):
            return "invalid --since value '\(v)' (expected like 30m, 2h, 24h, 3d)"
        case .unknownRail(let r):
            return "unknown --rail '\(r)' (expected one of ips, sentry, metrickit, sentinel)"
        case .unknownFlag(let f):
            return "unknown flag '\(f)'"
        }
    }
}

struct HealthCLIOptions {
    let mode: HealthCollectionWindow.Mode
    /// Used only when `mode == .sinceDuration`; ignored for boot/default modes.
    let windowDuration: TimeInterval
    let railFilter: HealthEvent.Rail?
    let json: Bool
}

/// Accepts compact-suffix duration strings: 30m, 2h, 24h, 3d. Returns the
/// corresponding `TimeInterval`, or nil for malformed input.
func parseSinceFlag(_ value: String) -> TimeInterval? {
    guard let last = value.last else { return nil }
    let head = value.dropLast()
    guard !head.isEmpty, let n = Double(head), n > 0 else { return nil }
    switch last {
    case "m": return n * 60
    case "h": return n * 3600
    case "d": return n * 86400
    default: return nil
    }
}

/// Reads `kern.boottime` via `sysctlbyname`. Falls back to 24h ago on
/// failure so callers do not have to handle nil for a value the kernel
/// always exposes on macOS.
func bootTime() -> Date {
    var tv = timeval()
    var size = MemoryLayout<timeval>.size
    let result = sysctlbyname("kern.boottime", &tv, &size, nil, 0)
    if result == 0 {
        let seconds = TimeInterval(tv.tv_sec) + TimeInterval(tv.tv_usec) / 1_000_000
        return Date(timeIntervalSince1970: seconds)
    }
    return Date(timeIntervalSinceNow: -24 * 3600)
}

func parseHealthCLIArgs(_ args: [String]) throws -> HealthCLIOptions {
    var since: TimeInterval? = nil
    var sinceBoot = false
    var rail: HealthEvent.Rail? = nil
    var json = false

    var i = 0
    while i < args.count {
        let arg = args[i]
        switch arg {
        case "--json":
            json = true
            i += 1
        case "--since":
            guard i + 1 < args.count else { throw HealthCLIError.missingValue(flag: "--since") }
            let v = args[i + 1]
            guard let interval = parseSinceFlag(v) else {
                throw HealthCLIError.invalidSinceValue(v)
            }
            since = interval
            i += 2
        case "--since-boot":
            sinceBoot = true
            i += 1
        case "--rail":
            guard i + 1 < args.count else { throw HealthCLIError.missingValue(flag: "--rail") }
            let v = args[i + 1]
            guard let r = HealthEvent.Rail(rawValue: v) else {
                throw HealthCLIError.unknownRail(v)
            }
            rail = r
            i += 2
        case "-h", "--help":
            // Help is dispatched upstream via dispatchSubcommandHelp; tolerate here.
            i += 1
        default:
            throw HealthCLIError.unknownFlag(arg)
        }
    }

    if since != nil && sinceBoot {
        throw HealthCLIError.mutuallyExclusiveSinceFlags
    }

    let mode: HealthCollectionWindow.Mode
    let duration: TimeInterval
    if let since {
        mode = .sinceDuration
        duration = since
    } else if sinceBoot {
        mode = .sinceBoot
        duration = 0
    } else {
        mode = .defaultLast24h
        duration = 24 * 3600
    }

    return HealthCLIOptions(
        mode: mode,
        windowDuration: duration,
        railFilter: rail,
        json: json
    )
}

// MARK: - Diagnostic warnings

private struct UncleanExitMarker {
    let timestamp: Date
    let version: String
}

private func mostRecentSentinelMarker(home: String) -> UncleanExitMarker? {
    let cacheURL = URL(fileURLWithPath: "\(home)/Library/Caches")
    let fm = FileManager.default

    guard let bundleDirs = try? fm.contentsOfDirectory(
        at: cacheURL,
        includingPropertiesForKeys: nil,
        options: [.skipsHiddenFiles]
    ) else { return nil }

    var best: UncleanExitMarker? = nil

    for bundleDir in bundleDirs {
        guard bundleDir.lastPathComponent.hasPrefix("com.stage11.c11") else { continue }
        let sessionsDir = bundleDir.appendingPathComponent("sessions", isDirectory: true)
        guard let files = try? fm.contentsOfDirectory(
            at: sessionsDir,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles]
        ) else { continue }

        for url in files {
            let name = url.lastPathComponent
            let isUnclean = name.hasPrefix("unclean-exit-") && name.hasSuffix(".json")
            let isActive = name == "active.json"
            guard isUnclean || isActive else { continue }

            guard let data = try? Data(contentsOf: url),
                  let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
            else { continue }

            var ts: Date? = nil
            if let str = obj["launched_at"] as? String {
                let f = ISO8601DateFormatter()
                f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
                ts = f.date(from: str)
            }
            if ts == nil, isUnclean {
                let stamp = String(name.dropFirst("unclean-exit-".count).dropLast(".json".count))
                ts = parseFilenameSafeISO(stamp)
            }
            if ts == nil, let attrs = try? fm.attributesOfItem(atPath: url.path) {
                ts = attrs[.modificationDate] as? Date
            }

            guard let timestamp = ts,
                  let version = obj["version"] as? String,
                  !version.isEmpty
            else { continue }

            if best == nil || best!.timestamp < timestamp {
                best = UncleanExitMarker(timestamp: timestamp, version: version)
            }
        }
    }

    return best
}

/// Fires when MetricKit count is 0 AND the running c11 was version-bumped
/// within the last 24h. Compares `bundleVersion` against the most-recent
/// prior session marker's `version`; if the marker is missing, returns nil
/// (we have no baseline to compare against).
func metricKitBaselineWarning(
    home: String,
    bundleVersion: String?,
    metricKitCount: Int,
    now: Date = Date()
) -> String? {
    guard metricKitCount == 0,
          let curr = bundleVersion, !curr.isEmpty,
          let marker = mostRecentSentinelMarker(home: home)
    else { return nil }

    guard marker.version != curr else { return nil }
    let age = now.timeIntervalSince(marker.timestamp)
    guard age >= 0, age <= 24 * 3600 else { return nil }

    return "MetricKit baseline still establishing after version bump (\(marker.version) to \(curr)); diagnostic payloads may not deliver for ~24h."
}

/// Fires when `<home>/Library/Caches/com.stage11.c11/io.sentry/` exists and
/// is empty AND we have zero queued events overall. Operator can't tell
/// from "0 events" alone whether telemetry is off or just freshly drained.
func telemetryAmbiguityFooter(home: String, sentryCount: Int) -> String? {
    guard sentryCount == 0 else { return nil }
    let probe = "\(home)/Library/Caches/com.stage11.c11/io.sentry"
    let fm = FileManager.default
    var isDir: ObjCBool = false
    guard fm.fileExists(atPath: probe, isDirectory: &isDir), isDir.boolValue else { return nil }

    let probeURL = URL(fileURLWithPath: probe)
    if let enumerator = fm.enumerator(
        at: probeURL,
        includingPropertiesForKeys: [.isRegularFileKey],
        options: [.skipsHiddenFiles]
    ) {
        for case let f as URL in enumerator {
            if (try? f.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile) == true {
                return nil
            }
        }
    }

    return "Production Sentry cache empty: telemetry may be off, or events shipped on last launch and cleared the cache."
}

// MARK: - Launch sentinel rail

/// One row per `unclean-exit-*.json` archive written by
/// `LaunchSentinel.recordLaunchAndArchivePrevious()` in
/// `Sources/SentryHelper.swift`. Catches Force-Quit / SIGKILL terminations
/// where neither Sentry nor `.ips` files survive.
func scanLaunchSentinel(home: String, since: Date) -> [HealthEvent] {
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

        let sessionsDir = bundleDir.appendingPathComponent("sessions", isDirectory: true)
        guard let sessionFiles = try? fm.contentsOfDirectory(
            at: sessionsDir,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles]
        ) else { continue }

        for url in sessionFiles {
            let name = url.lastPathComponent
            guard name.hasPrefix("unclean-exit-"),
                  name.hasSuffix(".json")
            else { continue }
            guard let event = parseUncleanExitFile(at: url, since: since) else { continue }
            events.append(event)
        }
    }

    return events
}

/// Returns nil when the file's stamp predates `since`, or when the file
/// cannot be read or parsed. Filename is the source of truth for the
/// timestamp; the JSON body is best-effort metadata.
func parseUncleanExitFile(at url: URL, since: Date) -> HealthEvent? {
    let name = url.lastPathComponent
    let prefix = "unclean-exit-"
    let suffix = ".json"
    guard name.hasPrefix(prefix), name.hasSuffix(suffix) else { return nil }
    let stamp = String(name.dropFirst(prefix.count).dropLast(suffix.count))
    guard let date = parseFilenameSafeISO(stamp), date >= since else { return nil }

    var version = "?"
    var build = "?"
    var commit = "????????"

    if let data = try? Data(contentsOf: url),
       let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
        if let v = obj["version"] as? String, !v.isEmpty { version = v }
        if let b = obj["build"] as? String, !b.isEmpty { build = b }
        if let c = obj["commit"] as? String, !c.isEmpty {
            commit = String(c.prefix(8))
        }
    }

    let summary = "\(version) (\(build)) \(commit)"
    return HealthEvent(
        timestamp: date,
        rail: .sentinel,
        severity: .unclean_exit,
        summary: summary,
        path: url.path
    )
}

/// Default empty-result line when no events are present and no rail filter is in effect.
private let healthEmptyResultLine =
    "c11 health: nothing in the last 24h across ips, sentry, metrickit, sentinel."

func renderHealthTable(_ events: [HealthEvent], warnings: [String] = []) -> String {
    var lines: [String] = []
    if events.isEmpty {
        lines.append(healthEmptyResultLine)
    } else {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd HH:mm"
        lines.append("TIME             | RAIL      | SEVERITY     | SUMMARY")
        for ev in events {
            let time = f.string(from: ev.timestamp)
            let rail = ev.rail.rawValue.padding(toLength: 9, withPad: " ", startingAt: 0)
            let sev = ev.severity.rawValue.padding(toLength: 12, withPad: " ", startingAt: 0)
            lines.append("\(time) | \(rail) | \(sev) | \(ev.summary)")
        }
    }
    if !warnings.isEmpty {
        lines.append("")
        lines.append("Warnings:")
        for w in warnings {
            lines.append("  - \(w)")
        }
    }
    return lines.joined(separator: "\n") + "\n"
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
