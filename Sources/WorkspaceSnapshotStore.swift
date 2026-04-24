import Foundation

/// Filesystem I/O for snapshot envelopes. Writes always go to
/// `~/.c11-snapshots/` (the rename from `cmux` → `c11` is the one-way
/// door). Reads support a backwards-compat fallback to `~/.cmux-snapshots/`
/// so operators who piloted an earlier iteration don't lose files; `c11
/// list-snapshots` merges both locations and tags legacy rows.
///
/// Atomic writes use `Data.write(to:options:)` with `.atomic`. File names
/// are `<snapshot_id>.json` — the ULID stem is authoritative; renames on
/// disk would desync the envelope's `snapshot_id` and must be avoided.
///
/// Not `@MainActor`. Socket handlers call this off the main thread; tests
/// inject a `directoryOverride:` so the real home dir never leaks into
/// CI.
struct WorkspaceSnapshotStore: Sendable {

    private let currentDirectory: URL
    private let legacyDirectory: URL
    private let fileManager: FileManager

    init(
        currentDirectory: URL = WorkspaceSnapshotStore.defaultDirectory(),
        legacyDirectory: URL = WorkspaceSnapshotStore.defaultLegacyDirectory(),
        fileManager: FileManager = .default
    ) {
        self.currentDirectory = currentDirectory
        self.legacyDirectory = legacyDirectory
        self.fileManager = fileManager
    }

    // MARK: - Default locations

    /// `~/.c11-snapshots/`. Writes always land here.
    static func defaultDirectory() -> URL {
        let home = FileManager.default.homeDirectoryForCurrentUser
        return home.appendingPathComponent(".c11-snapshots", isDirectory: true)
    }

    /// `~/.cmux-snapshots/`. Read-only legacy path.
    static func defaultLegacyDirectory() -> URL {
        let home = FileManager.default.homeDirectoryForCurrentUser
        return home.appendingPathComponent(".cmux-snapshots", isDirectory: true)
    }

    // MARK: - Write

    enum StoreError: Error, Equatable, CustomStringConvertible {
        case createDirectoryFailed(String, underlying: String)
        case encodeFailed(String)
        case writeFailed(String, underlying: String)
        case readFailed(String, underlying: String)
        case decodeFailed(String, underlying: String)
        case notFound(String)

        var code: String {
            switch self {
            case .createDirectoryFailed: return "snapshot_dir_create_failed"
            case .encodeFailed:          return "snapshot_encode_failed"
            case .writeFailed:           return "snapshot_write_failed"
            case .readFailed:            return "snapshot_read_failed"
            case .decodeFailed:          return "snapshot_decode_failed"
            case .notFound:              return "snapshot_not_found"
            }
        }

        var description: String {
            switch self {
            case .createDirectoryFailed(let path, let err):
                return "snapshot dir create failed at \(path): \(err)"
            case .encodeFailed(let detail):
                return "snapshot encode failed: \(detail)"
            case .writeFailed(let path, let err):
                return "snapshot write failed at \(path): \(err)"
            case .readFailed(let path, let err):
                return "snapshot read failed at \(path): \(err)"
            case .decodeFailed(let path, let err):
                return "snapshot decode failed at \(path): \(err)"
            case .notFound(let id):
                return "snapshot id '\(id)' not found under ~/.c11-snapshots or ~/.cmux-snapshots"
            }
        }
    }

    /// Write `snapshot` to `<currentDirectory>/<snapshot.snapshot_id>.json`,
    /// or to an explicit path. Returns the resolved path. Atomic write;
    /// directory is created on demand.
    @discardableResult
    func write(_ snapshot: WorkspaceSnapshotFile, to explicitPath: URL? = nil) throws -> URL {
        let target: URL
        if let explicitPath {
            target = explicitPath
        } else {
            target = currentDirectory.appendingPathComponent("\(snapshot.snapshotId).json")
        }
        let parent = target.deletingLastPathComponent()
        do {
            try fileManager.createDirectory(at: parent, withIntermediateDirectories: true)
        } catch {
            throw StoreError.createDirectoryFailed(parent.path, underlying: "\(error)")
        }
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        encoder.dateEncodingStrategy = .iso8601
        let data: Data
        do {
            data = try encoder.encode(snapshot)
        } catch {
            throw StoreError.encodeFailed("\(error)")
        }
        do {
            try data.write(to: target, options: .atomic)
        } catch {
            throw StoreError.writeFailed(target.path, underlying: "\(error)")
        }
        return target
    }

    // MARK: - Read

    /// Read and decode a snapshot from an absolute URL. Does not consult the
    /// id-based lookup — see `read(byId:)` for that.
    func read(from url: URL) throws -> WorkspaceSnapshotFile {
        let data: Data
        do {
            data = try Data(contentsOf: url)
        } catch {
            throw StoreError.readFailed(url.path, underlying: "\(error)")
        }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        do {
            return try decoder.decode(WorkspaceSnapshotFile.self, from: data)
        } catch {
            throw StoreError.decodeFailed(url.path, underlying: "\(error)")
        }
    }

    /// Resolve an id to a path (current dir first, then legacy). Returns the
    /// first match. Throws `.notFound` when neither path exists.
    func resolvePath(byId snapshotId: String) throws -> URL {
        let primary = currentDirectory.appendingPathComponent("\(snapshotId).json")
        if fileManager.fileExists(atPath: primary.path) {
            return primary
        }
        let legacy = legacyDirectory.appendingPathComponent("\(snapshotId).json")
        if fileManager.fileExists(atPath: legacy.path) {
            return legacy
        }
        throw StoreError.notFound(snapshotId)
    }

    /// Read a snapshot by id, checking `~/.c11-snapshots/` then the legacy
    /// directory. Throws `.notFound` if neither has it.
    func read(byId snapshotId: String) throws -> WorkspaceSnapshotFile {
        try read(from: resolvePath(byId: snapshotId))
    }

    // MARK: - List

    /// Merge entries from the current directory + legacy directory into one
    /// list. Each entry carries its source. Sorted by `createdAt` descending
    /// (newest first) so `c11 list-snapshots` reads top-to-bottom.
    func list() throws -> [WorkspaceSnapshotIndex] {
        var result: [WorkspaceSnapshotIndex] = []
        result.append(contentsOf: enumerate(
            directory: currentDirectory,
            source: .current
        ))
        // Only walk the legacy path if it's not the same as the current —
        // test harnesses commonly override both to the same tmp dir.
        if legacyDirectory != currentDirectory {
            result.append(contentsOf: enumerate(
                directory: legacyDirectory,
                source: .legacy
            ))
        }
        result.sort { $0.createdAt > $1.createdAt }
        return result
    }

    /// Walk a directory and emit one `WorkspaceSnapshotIndex` per decodable
    /// `.json` file. Malformed files are skipped silently; the listing's
    /// job is to show what's usable, not to surface every parse error.
    /// (Callers who want strict-mode reads call `read(from:)` directly.)
    private func enumerate(
        directory: URL,
        source: WorkspaceSnapshotIndex.Source
    ) -> [WorkspaceSnapshotIndex] {
        guard fileManager.fileExists(atPath: directory.path) else { return [] }
        let entries: [URL]
        do {
            entries = try fileManager.contentsOfDirectory(
                at: directory,
                includingPropertiesForKeys: [.isRegularFileKey],
                options: [.skipsHiddenFiles]
            )
        } catch {
            return []
        }
        var out: [WorkspaceSnapshotIndex] = []
        for url in entries where url.pathExtension.lowercased() == "json" {
            guard let snapshot = try? read(from: url) else { continue }
            out.append(WorkspaceSnapshotIndex(
                snapshotId: snapshot.snapshotId,
                path: url.path,
                createdAt: snapshot.createdAt,
                workspaceTitle: snapshot.plan.workspace.title,
                surfaceCount: snapshot.plan.surfaces.count,
                origin: snapshot.origin,
                source: source
            ))
        }
        return out
    }
}
