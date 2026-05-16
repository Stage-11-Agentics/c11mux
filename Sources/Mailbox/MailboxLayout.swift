import Foundation

/// Pure path builders for the per-workspace mailbox tree. No I/O happens here —
/// the dispatcher owns directory creation at first send; this module only
/// computes the URLs and validates surface-name components.
///
/// Layout on disk:
///
///     <state>/workspaces/<workspace-uuid>/mailboxes/
///         _outbox/               (shared drop zone)
///         _processing/           (atomic-move target while dispatching)
///         _rejected/             (malformed envelopes + sibling .err files)
///         blobs/                 (body_ref payloads, v1.1 writers)
///         _dispatch.log          (append-only NDJSON, one line per event)
///         <surface-name>/        (per-recipient inbox)
///             01K3A2B7X8...msg   (pending message)
///
/// See `docs/c11-messaging-primitive-design.md` §3 and
/// `spec/mailbox-envelope.v1.schema.json` for the envelope format.
enum MailboxLayout {

    // MARK: - Names

    /// Directory name under `~/Library/Application Support/` where c11 keeps
    /// the socket, workspace snapshots, and the mailbox tree. Mirrors
    /// `SocketControlSettings.socketDirectoryName`; duplicated here so the
    /// CLI target (which compiles without SocketControlSettings.swift) can
    /// resolve the state root without a cross-target import.
    static let stateDirectoryName = "c11"

    static let workspacesDirectoryName = "workspaces"
    static let mailboxesDirectoryName = "mailboxes"
    static let outboxDirectoryName = "_outbox"
    static let processingDirectoryName = "_processing"
    static let rejectedDirectoryName = "_rejected"
    static let blobsDirectoryName = "blobs"
    static let dispatchLogFileName = "_dispatch.log"

    /// Extension for a fully-written envelope visible to the dispatcher.
    static let envelopeExtension = "msg"
    /// Extension for in-flight writes (hidden from the dispatcher by filename filter).
    static let tempExtension = "tmp"
    /// Sibling file next to a rejected envelope, explaining why it was quarantined.
    static let rejectedErrorExtension = "err"

    /// Max UTF-8 byte length for a surface name used as an inbox directory component.
    static let maxSurfaceNameBytes = 64

    // MARK: - Errors

    enum Error: Swift.Error, Equatable {
        case stateDirectoryUnavailable
        case invalidSurfaceName(name: String, reason: SurfaceNameRejection)
    }

    enum SurfaceNameRejection: String, Equatable {
        case empty
        case containsPathSeparator
        case containsNullByte
        case parentReference
        case leadingDot
        case tooLong
    }

    // MARK: - State root

    /// Resolves the c11 state root (default:
    /// `~/Library/Application Support/c11`). Tests that need isolation
    /// override HOME on the c11 process rather than overriding this function.
    static func defaultStateURL(fileManager: FileManager = .default) throws -> URL {
        StateDirectoryMigration.ensureMigrated(fileManager: fileManager)
        guard let appSupport = fileManager.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        ).first else {
            throw Error.stateDirectoryUnavailable
        }
        return appSupport.appendingPathComponent(stateDirectoryName, isDirectory: true)
    }

    // MARK: - Path builders

    static func mailboxesRoot(state: URL, workspaceId: UUID) -> URL {
        state
            .appendingPathComponent(workspacesDirectoryName, isDirectory: true)
            .appendingPathComponent(workspaceId.uuidString, isDirectory: true)
            .appendingPathComponent(mailboxesDirectoryName, isDirectory: true)
    }

    static func outboxURL(state: URL, workspaceId: UUID) -> URL {
        mailboxesRoot(state: state, workspaceId: workspaceId)
            .appendingPathComponent(outboxDirectoryName, isDirectory: true)
    }

    static func processingURL(state: URL, workspaceId: UUID) -> URL {
        mailboxesRoot(state: state, workspaceId: workspaceId)
            .appendingPathComponent(processingDirectoryName, isDirectory: true)
    }

    static func rejectedURL(state: URL, workspaceId: UUID) -> URL {
        mailboxesRoot(state: state, workspaceId: workspaceId)
            .appendingPathComponent(rejectedDirectoryName, isDirectory: true)
    }

    static func blobsURL(state: URL, workspaceId: UUID) -> URL {
        mailboxesRoot(state: state, workspaceId: workspaceId)
            .appendingPathComponent(blobsDirectoryName, isDirectory: true)
    }

    static func dispatchLogURL(state: URL, workspaceId: UUID) -> URL {
        mailboxesRoot(state: state, workspaceId: workspaceId)
            .appendingPathComponent(dispatchLogFileName, isDirectory: false)
    }

    /// Returns the inbox directory for a given surface name. Rejects names that
    /// would escape the mailbox tree or produce hidden/unsafe directory entries.
    static func inboxURL(state: URL, workspaceId: UUID, surfaceName: String) throws -> URL {
        try validateSurfaceName(surfaceName)
        return mailboxesRoot(state: state, workspaceId: workspaceId)
            .appendingPathComponent(surfaceName, isDirectory: true)
    }

    // MARK: - Filenames

    static func envelopeFilename(id: String) -> String {
        "\(id).\(envelopeExtension)"
    }

    static func tempFilename(id: String) -> String {
        ".\(id).\(tempExtension)"
    }

    static func rejectedErrorFilename(id: String) -> String {
        "\(id).\(rejectedErrorExtension)"
    }

    // MARK: - Surface-name validation

    /// Early bail-out used by the CLI and the dispatcher. The schema's
    /// `from` / `to` / `reply_to` fields are plain strings; the mailbox tree
    /// uses them as directory components, so the same name must also be safe
    /// on a POSIX filesystem.
    static func validateSurfaceName(_ name: String) throws {
        if name.isEmpty {
            throw Error.invalidSurfaceName(name: name, reason: .empty)
        }
        if name.utf8.count > maxSurfaceNameBytes {
            throw Error.invalidSurfaceName(name: name, reason: .tooLong)
        }
        if name.contains("/") {
            throw Error.invalidSurfaceName(name: name, reason: .containsPathSeparator)
        }
        if name.contains("\0") {
            throw Error.invalidSurfaceName(name: name, reason: .containsNullByte)
        }
        if name == "." || name == ".." {
            throw Error.invalidSurfaceName(name: name, reason: .parentReference)
        }
        if name.hasPrefix(".") {
            throw Error.invalidSurfaceName(name: name, reason: .leadingDot)
        }
    }
}

/// One-time-per-process migration of the c11 state directory from the legacy
/// `c11mux` name to the canonical `c11` name. Every state-root resolver
/// (`MailboxLayout.defaultStateURL`, `SocketControlSettings.stableSocketDirectoryURL`,
/// the password-store path builder, `SessionPersistence`, and the
/// remote-daemon cache root) calls `ensureMigrated` before constructing
/// its URL. Idempotent and thread-safe; cross-process safety is best-effort
/// via `moveItem`'s atomicity.
///
/// Migration steps (only when legacy exists and current does not):
///   1. `moveItem` `~/Library/Application Support/c11mux` →
///      `~/Library/Application Support/c11` (atomic on same volume).
///   2. Create a relative symlink at the legacy path pointing at `c11`,
///      so downgraded older binaries continue to find their state.
///      The symlink can be dropped in a later release once the downgrade
///      window has closed; see `docs/c11-state-dir-rename-plan.md`.
enum StateDirectoryMigration {
    static let legacyName = "c11mux"
    static let currentName = "c11"

    private static let lock = NSLock()
    private static var didRun = false

    static func ensureMigrated(fileManager: FileManager = .default) {
        lock.lock()
        defer { lock.unlock() }
        if didRun { return }
        didRun = true

        guard let appSupport = fileManager.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        ).first else {
            return
        }

        let legacyURL = appSupport.appendingPathComponent(legacyName, isDirectory: true)
        let currentURL = appSupport.appendingPathComponent(currentName, isDirectory: true)

        // Fresh install (neither exists) or already migrated (current exists)
        // or co-existing (both exist, leave alone): nothing to do.
        let legacyExists = fileManager.fileExists(atPath: legacyURL.path)
        let currentExists = fileManager.fileExists(atPath: currentURL.path)
        guard legacyExists, !currentExists else { return }

        do {
            try fileManager.moveItem(at: legacyURL, to: currentURL)
            try fileManager.createSymbolicLink(
                atPath: legacyURL.path,
                withDestinationPath: currentName
            )
        } catch {
            FileHandle.standardError.write(Data(
                "c11: state-directory migration failed: \(error.localizedDescription)\n".utf8
            ))
        }
    }
}
