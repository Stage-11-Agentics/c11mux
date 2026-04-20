import Foundation
import CryptoKit

// MARK: - Public types

enum SkillInstallerTarget: String, CaseIterable {
    case claude
    case codex
    case kimi
    case opencode

    var displayName: String {
        switch self {
        case .claude: return "Claude Code"
        case .codex: return "Codex"
        case .kimi: return "Kimi"
        case .opencode: return "OpenCode"
        }
    }

    /// Root config dir conventionally used by each TUI (`~/.claude`, `~/.codex`, …).
    func configRoot(home: URL) -> URL {
        home.appendingPathComponent(".\(rawValue)", isDirectory: true)
    }

    /// Destination skills dir (`~/.claude/skills`, `~/.codex/skills`, …).
    func skillsDir(home: URL) -> URL {
        configRoot(home: home).appendingPathComponent("skills", isDirectory: true)
    }

    /// True when the TUI's config root exists — the only signal c11mux uses
    /// to infer that a user cares about a given tool.
    func isDetected(home: URL, fileManager: FileManager = .default) -> Bool {
        var isDir: ObjCBool = false
        let exists = fileManager.fileExists(atPath: configRoot(home: home).path, isDirectory: &isDir)
        return exists && isDir.boolValue
    }
}

struct SkillInstallerPackage: Equatable {
    let name: String
    let sourceDir: URL
}

struct SkillInstallerRecord: Codable, Equatable {
    /// Bumped when the on-disk manifest schema changes in a backwards-incompatible way.
    static let schemaVersion = 1

    let schema: Int
    let packageName: String
    let installedAt: String
    let appVersion: String
    let appBuild: String
    let commitShort: String
    let sourceContentHash: String

    enum CodingKeys: String, CodingKey {
        case schema = "c11mux_skill_schema"
        case packageName = "package"
        case installedAt = "installed_at"
        case appVersion = "app_version"
        case appBuild = "app_build"
        case commitShort = "commit"
        case sourceContentHash = "source_sha256"
    }
}

enum SkillInstallerState: String, Equatable {
    case notInstalled
    case installedCurrent
    case installedOutdated
    case installedNoManifest
    case schemaMismatch
}

struct SkillInstallerPackageStatus: Equatable {
    let package: SkillInstallerPackage
    let target: SkillInstallerTarget
    let destinationDir: URL
    let state: SkillInstallerState
    let record: SkillInstallerRecord?
    let sourceContentHash: String
}

struct SkillInstallerApplyResult: Equatable {
    let target: SkillInstallerTarget
    let installed: [String]
    let refreshed: [String]
    let skipped: [String]
    let destDir: URL
}

struct SkillInstallerRemoveResult: Equatable {
    let target: SkillInstallerTarget
    let removed: [String]
    let skipped: [String]
    let destDir: URL
}

struct SkillInstallerError: Error {
    enum Code: String {
        case noSourceFound
        case sourceNotReadable
        case targetNotDetected
        case destUnwritable
        case copyFailed
        case manifestMalformed
    }
    let code: Code
    let message: String
}

// MARK: - SkillInstaller namespace

enum SkillInstaller {
    static let manifestFilename = ".c11mux-skill.json"

    // MARK: Source discovery

    /// Locate the bundled `skills/` directory. Tries (in order):
    ///   1) adjacent to the executable's `Contents/Resources/skills/` (shipped .app)
    ///   2) walking up from the executable to find `<repo>/skills/` (dev)
    ///   3) `CMUX_SKILLS_SOURCE` env var as an explicit override
    static func defaultSourceURL(
        executableURL: URL?,
        env: [String: String] = ProcessInfo.processInfo.environment,
        fileManager: FileManager = .default
    ) -> URL? {
        if let override = env["CMUX_SKILLS_SOURCE"], !override.isEmpty {
            let url = URL(fileURLWithPath: (override as NSString).expandingTildeInPath, isDirectory: true)
            if fileManager.fileExists(atPath: url.path) {
                return url.standardizedFileURL
            }
        }

        guard let executableURL else { return nil }
        var current = executableURL.deletingLastPathComponent().standardizedFileURL
        while true {
            if current.lastPathComponent == "Contents" {
                let bundled = current
                    .appendingPathComponent("Resources", isDirectory: true)
                    .appendingPathComponent("skills", isDirectory: true)
                if fileManager.fileExists(atPath: bundled.path) {
                    return bundled.standardizedFileURL
                }
            }

            let projectMarker = current.appendingPathComponent("GhosttyTabs.xcodeproj/project.pbxproj", isDirectory: false)
            let repoSkills = current.appendingPathComponent("skills", isDirectory: true)
            if fileManager.fileExists(atPath: projectMarker.path),
               fileManager.fileExists(atPath: repoSkills.path) {
                return repoSkills.standardizedFileURL
            }

            let parent = current.deletingLastPathComponent().standardizedFileURL
            if parent.path == current.path { break }
            current = parent
        }
        return nil
    }

    /// Each direct child of `sourceDir` that contains a `SKILL.md` is a skill
    /// candidate. If `sourceDir/MANIFEST.json` declares an `installable` list,
    /// that list filters the candidates (so maintainer-only skills like
    /// `release` are not pushed to user machines). Packages are returned in
    /// stable alphabetical order.
    static func discoverPackages(
        sourceDir: URL,
        fileManager: FileManager = .default
    ) throws -> [SkillInstallerPackage] {
        var isDir: ObjCBool = false
        guard fileManager.fileExists(atPath: sourceDir.path, isDirectory: &isDir), isDir.boolValue else {
            throw SkillInstallerError(
                code: .noSourceFound,
                message: "Bundled skills directory not found at \(sourceDir.path)."
            )
        }
        let children: [URL]
        do {
            children = try fileManager.contentsOfDirectory(
                at: sourceDir,
                includingPropertiesForKeys: [.isDirectoryKey],
                options: [.skipsHiddenFiles]
            )
        } catch {
            throw SkillInstallerError(
                code: .sourceNotReadable,
                message: "Cannot enumerate skills source: \(error.localizedDescription)"
            )
        }

        let allowlist: Set<String>? = readInstallableAllowlist(sourceDir: sourceDir, fileManager: fileManager)

        let packages: [SkillInstallerPackage] = children.compactMap { url in
            var childIsDir: ObjCBool = false
            guard fileManager.fileExists(atPath: url.path, isDirectory: &childIsDir), childIsDir.boolValue else {
                return nil
            }
            let skillMd = url.appendingPathComponent("SKILL.md", isDirectory: false)
            guard fileManager.fileExists(atPath: skillMd.path) else { return nil }
            let name = url.lastPathComponent
            if let allowlist, !allowlist.contains(name) { return nil }
            return SkillInstallerPackage(name: name, sourceDir: url.standardizedFileURL)
        }
        return packages.sorted { $0.name < $1.name }
    }

    private static func readInstallableAllowlist(
        sourceDir: URL,
        fileManager: FileManager
    ) -> Set<String>? {
        let manifest = sourceDir.appendingPathComponent("MANIFEST.json", isDirectory: false)
        guard fileManager.fileExists(atPath: manifest.path),
              let data = try? Data(contentsOf: manifest),
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let list = obj["installable"] as? [String] else {
            return nil
        }
        return Set(list)
    }

    // MARK: Hashing

    /// Deterministic SHA-256 over a directory: hashes the sorted list of
    /// (relative path + `\0` + file bytes + `\0`) for every file under `dir`.
    /// Skips dotfiles so the installer's own manifest file doesn't perturb the hash.
    static func contentHash(
        of dir: URL,
        fileManager: FileManager = .default
    ) throws -> String {
        let base = dir.standardizedFileURL
        let basePath = base.path
        guard let enumerator = fileManager.enumerator(
            at: base,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: []
        ) else {
            throw SkillInstallerError(
                code: .sourceNotReadable,
                message: "Cannot enumerate directory: \(base.path)"
            )
        }
        var entries: [(rel: String, absolute: URL)] = []
        for case let fileURL as URL in enumerator {
            let resolved = fileURL.standardizedFileURL
            let rel = String(resolved.path.dropFirst(basePath.count).drop(while: { $0 == "/" }))
            if rel.hasPrefix(".") || rel.contains("/.") { continue }
            let values = try resolved.resourceValues(forKeys: [.isRegularFileKey])
            guard values.isRegularFile == true else { continue }
            entries.append((rel, resolved))
        }
        entries.sort { $0.rel < $1.rel }

        var hasher = SHA256()
        for entry in entries {
            if let relData = entry.rel.data(using: .utf8) {
                hasher.update(data: relData)
            }
            hasher.update(data: Data([0]))
            let data = try Data(contentsOf: entry.absolute)
            hasher.update(data: data)
            hasher.update(data: Data([0]))
        }
        let digest = hasher.finalize()
        return "sha256:" + digest.map { String(format: "%02x", $0) }.joined()
    }

    // MARK: Status

    static func status(
        for target: SkillInstallerTarget,
        home: URL,
        sourceDir: URL,
        fileManager: FileManager = .default
    ) throws -> [SkillInstallerPackageStatus] {
        let packages = try discoverPackages(sourceDir: sourceDir, fileManager: fileManager)
        let destRoot = target.skillsDir(home: home)
        return try packages.map { package in
            let destDir = destRoot.appendingPathComponent(package.name, isDirectory: true)
            let sourceHash = try contentHash(of: package.sourceDir, fileManager: fileManager)
            let manifest = destDir.appendingPathComponent(manifestFilename, isDirectory: false)
            var destExists: ObjCBool = false
            let destPresent = fileManager.fileExists(atPath: destDir.path, isDirectory: &destExists) && destExists.boolValue
            let manifestPresent = fileManager.fileExists(atPath: manifest.path)

            if !destPresent {
                return SkillInstallerPackageStatus(
                    package: package,
                    target: target,
                    destinationDir: destDir,
                    state: .notInstalled,
                    record: nil,
                    sourceContentHash: sourceHash
                )
            }
            if !manifestPresent {
                return SkillInstallerPackageStatus(
                    package: package,
                    target: target,
                    destinationDir: destDir,
                    state: .installedNoManifest,
                    record: nil,
                    sourceContentHash: sourceHash
                )
            }
            let record: SkillInstallerRecord
            do {
                let data = try Data(contentsOf: manifest)
                record = try JSONDecoder().decode(SkillInstallerRecord.self, from: data)
            } catch {
                return SkillInstallerPackageStatus(
                    package: package,
                    target: target,
                    destinationDir: destDir,
                    state: .installedNoManifest,
                    record: nil,
                    sourceContentHash: sourceHash
                )
            }
            if record.schema != SkillInstallerRecord.schemaVersion {
                return SkillInstallerPackageStatus(
                    package: package,
                    target: target,
                    destinationDir: destDir,
                    state: .schemaMismatch,
                    record: record,
                    sourceContentHash: sourceHash
                )
            }
            let state: SkillInstallerState = (record.sourceContentHash == sourceHash)
                ? .installedCurrent : .installedOutdated
            return SkillInstallerPackageStatus(
                package: package,
                target: target,
                destinationDir: destDir,
                state: state,
                record: record,
                sourceContentHash: sourceHash
            )
        }
    }

    // MARK: Install

    struct AppIdentity {
        let version: String
        let build: String
        let commitShort: String

        static var current: AppIdentity {
            let info = Bundle.main.infoDictionary ?? [:]
            let version = (info["CFBundleShortVersionString"] as? String) ?? "0.0.0"
            let build = (info["CFBundleVersion"] as? String) ?? "0"
            let commit = (info["CMUXCommit"] as? String) ?? ""
            return AppIdentity(version: version, build: build, commitShort: commit)
        }
    }

    /// Copy every bundled package into `<home>/.<target>/skills/<package>/`, writing
    /// a manifest per package. Idempotent: packages whose source hash matches the
    /// manifest are skipped unless `force` is true.
    static func install(
        target: SkillInstallerTarget,
        home: URL,
        sourceDir: URL,
        force: Bool,
        appIdentity: AppIdentity = .current,
        now: () -> Date = Date.init,
        fileManager: FileManager = .default
    ) throws -> SkillInstallerApplyResult {
        let statuses = try status(for: target, home: home, sourceDir: sourceDir, fileManager: fileManager)
        let destRoot = target.skillsDir(home: home)
        do {
            try fileManager.createDirectory(at: destRoot, withIntermediateDirectories: true)
        } catch {
            throw SkillInstallerError(
                code: .destUnwritable,
                message: "Cannot create \(destRoot.path): \(error.localizedDescription)"
            )
        }

        let isoFormatter = ISO8601DateFormatter()
        isoFormatter.formatOptions = [.withInternetDateTime]
        let timestamp = isoFormatter.string(from: now())

        var installed: [String] = []
        var refreshed: [String] = []
        var skipped: [String] = []

        for st in statuses {
            let dest = st.destinationDir
            let isUpToDate = (st.state == .installedCurrent)
            if isUpToDate && !force {
                skipped.append(st.package.name)
                continue
            }

            // Remove any prior copy to avoid leaving orphaned files behind.
            if fileManager.fileExists(atPath: dest.path) {
                do {
                    try fileManager.removeItem(at: dest)
                } catch {
                    throw SkillInstallerError(
                        code: .copyFailed,
                        message: "Cannot remove existing \(dest.path): \(error.localizedDescription)"
                    )
                }
            }
            do {
                try fileManager.copyItem(at: st.package.sourceDir, to: dest)
            } catch {
                throw SkillInstallerError(
                    code: .copyFailed,
                    message: "Cannot copy \(st.package.name) to \(dest.path): \(error.localizedDescription)"
                )
            }

            let record = SkillInstallerRecord(
                schema: SkillInstallerRecord.schemaVersion,
                packageName: st.package.name,
                installedAt: timestamp,
                appVersion: appIdentity.version,
                appBuild: appIdentity.build,
                commitShort: appIdentity.commitShort,
                sourceContentHash: st.sourceContentHash
            )
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            let data = try encoder.encode(record)
            try data.write(to: dest.appendingPathComponent(manifestFilename, isDirectory: false), options: .atomic)

            switch st.state {
            case .notInstalled:
                installed.append(st.package.name)
            case .installedCurrent, .installedOutdated, .installedNoManifest, .schemaMismatch:
                refreshed.append(st.package.name)
            }
        }

        return SkillInstallerApplyResult(
            target: target,
            installed: installed,
            refreshed: refreshed,
            skipped: skipped,
            destDir: destRoot
        )
    }

    // MARK: Remove

    /// Remove c11mux-installed skill packages from a target. Only removes a
    /// package dir if its `.c11mux-skill.json` manifest is present — protects
    /// directories the user created themselves.
    static func remove(
        target: SkillInstallerTarget,
        home: URL,
        sourceDir: URL,
        fileManager: FileManager = .default
    ) throws -> SkillInstallerRemoveResult {
        let packages = try discoverPackages(sourceDir: sourceDir, fileManager: fileManager)
        let destRoot = target.skillsDir(home: home)
        var removed: [String] = []
        var skipped: [String] = []

        for pkg in packages {
            let dest = destRoot.appendingPathComponent(pkg.name, isDirectory: true)
            let manifest = dest.appendingPathComponent(manifestFilename, isDirectory: false)
            guard fileManager.fileExists(atPath: dest.path) else {
                skipped.append(pkg.name)
                continue
            }
            guard fileManager.fileExists(atPath: manifest.path) else {
                // User-owned; don't touch.
                skipped.append(pkg.name)
                continue
            }
            do {
                try fileManager.removeItem(at: dest)
            } catch {
                throw SkillInstallerError(
                    code: .copyFailed,
                    message: "Cannot remove \(dest.path): \(error.localizedDescription)"
                )
            }
            removed.append(pkg.name)
        }
        return SkillInstallerRemoveResult(
            target: target,
            removed: removed,
            skipped: skipped,
            destDir: destRoot
        )
    }
}
