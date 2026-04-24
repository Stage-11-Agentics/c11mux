import Foundation

/// On-disk envelope for a captured workspace. Wraps a `WorkspaceApplyPlan` —
/// the Phase 0 shared primitive that Blueprints (Phase 2) and Snapshots
/// (Phase 1) both emit — alongside snapshot-scoped metadata that does not
/// belong on the plan itself (a Blueprint is a hand-authored plan; it has
/// no `snapshot_id` or capture timestamp).
///
/// The wire shape is intentionally one level of nesting:
///
/// ```json
/// {
///   "version": 1,
///   "snapshot_id": "01KQ0XYZ...",
///   "created_at": "2026-04-24T18:30:00.000Z",
///   "c11_version": "0.01.123+42",
///   "origin": "manual",
///   "plan": { ...<WorkspaceApplyPlan>... }
/// }
/// ```
///
/// Purely a value type. Capture lives in `WorkspaceSnapshotCapture.swift`,
/// filesystem I/O in `WorkspaceSnapshotStore.swift`, and the pure
/// envelope→plan conversion in `WorkspaceSnapshotConverter.swift`. This file
/// intentionally holds no behavior; keeping it lean lets the converter test
/// file stay `Foundation`-only.
struct WorkspaceSnapshotFile: Codable, Sendable, Equatable {
    /// Envelope schema version. Phase 1 ships `1`; a breaking envelope
    /// change bumps this without touching the embedded plan's version.
    var version: Int
    /// ULID; matches the on-disk filename stem (`<snapshot_id>.json`).
    var snapshotId: String
    /// UTC capture time, ISO-8601 with fractional seconds. Carried on the
    /// envelope so the embedded plan stays pure (Blueprints do not have a
    /// capture timestamp).
    var createdAt: Date
    /// `CFBundleShortVersionString+CFBundleVersion` at capture time. Lets
    /// operators correlate a snapshot with the binary that produced it.
    var c11Version: String
    /// How this snapshot was produced.
    var origin: Origin
    /// The captured workspace, expressed as a `WorkspaceApplyPlan` that the
    /// executor can apply verbatim on restore.
    var plan: WorkspaceApplyPlan

    enum Origin: String, Codable, Sendable, Equatable {
        case manual
        case autoRestart = "auto-restart"
    }

    init(
        version: Int = 1,
        snapshotId: String,
        createdAt: Date,
        c11Version: String,
        origin: Origin,
        plan: WorkspaceApplyPlan
    ) {
        self.version = version
        self.snapshotId = snapshotId
        self.createdAt = createdAt
        self.c11Version = c11Version
        self.origin = origin
        self.plan = plan
    }

    private enum CodingKeys: String, CodingKey {
        case version
        case snapshotId = "snapshot_id"
        case createdAt = "created_at"
        case c11Version = "c11_version"
        case origin
        case plan
    }
}

/// Lightweight list entry returned by `WorkspaceSnapshotStore.list()` and
/// surfaced by `c11 list-snapshots`. Deliberately a subset of the full
/// envelope — callers that need the plan re-read the file by id.
struct WorkspaceSnapshotIndex: Codable, Sendable, Equatable {
    /// ULID from the filename stem.
    var snapshotId: String
    /// Resolved absolute path on disk.
    var path: String
    /// From the envelope.
    var createdAt: Date
    /// Best-effort `WorkspaceSpec.title`, or `nil` if the plan didn't set one.
    var workspaceTitle: String?
    /// Surface count, cached from the plan so `list` doesn't decode the full
    /// `layout` tree for every entry.
    var surfaceCount: Int
    /// Mirrors `WorkspaceSnapshotFile.Origin`.
    var origin: WorkspaceSnapshotFile.Origin
    /// Where the entry was discovered: `current` for `~/.c11-snapshots/`,
    /// `legacy` for the `~/.cmux-snapshots/` read-fallback path.
    var source: Source

    enum Source: String, Codable, Sendable, Equatable {
        case current
        case legacy
    }

    private enum CodingKeys: String, CodingKey {
        case snapshotId = "snapshot_id"
        case path
        case createdAt = "created_at"
        case workspaceTitle = "workspace_title"
        case surfaceCount = "surface_count"
        case origin
        case source
    }
}

/// Approximate-ULID generator for snapshot ids. Not a full ULID implementation —
/// Crockford base32 time + 80-bit random — but the output matches the layout
/// (26 chars, base32, time-ordered prefix) and is sufficient for filename
/// stems. Pure; no AppKit.
enum WorkspaceSnapshotID {
    private static let alphabet: [Character] = Array("0123456789ABCDEFGHJKMNPQRSTVWXYZ")

    /// Generate a fresh ULID-shaped id from the given clock and RNG. Both are
    /// injectable for deterministic tests. Defaults use wall-clock and
    /// `SystemRandomNumberGenerator`.
    static func generate(
        now: Date = Date(),
        random: (() -> UInt64) = Self.defaultRandom
    ) -> String {
        let millis = UInt64(now.timeIntervalSince1970 * 1000)
        var out = ""
        out.reserveCapacity(26)
        // 48-bit time → 10 base32 chars.
        var t = millis
        var timeChars = Array(repeating: Character("0"), count: 10)
        for i in (0..<10).reversed() {
            timeChars[i] = alphabet[Int(t & 0x1F)]
            t >>= 5
        }
        for c in timeChars { out.append(c) }
        // 80-bit random → 16 base32 chars. Two 64-bit calls give us 128 bits;
        // we only need 80. Shift out of a 128-bit accumulator.
        let r1 = random()
        let r2 = random()
        // Lay them out as 128 bits, take the top 80.
        let high = r1
        let lowTop16: UInt64 = r2 >> 48
        var acc: UInt64 = (high << 16) | lowTop16
        var randChars = Array(repeating: Character("0"), count: 16)
        for i in (0..<16).reversed() {
            randChars[i] = alphabet[Int(acc & 0x1F)]
            acc >>= 5
        }
        for c in randChars { out.append(c) }
        return out
    }

    private static func defaultRandom() -> UInt64 {
        var rng = SystemRandomNumberGenerator()
        return rng.next()
    }
}
