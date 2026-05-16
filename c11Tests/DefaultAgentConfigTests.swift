import XCTest

#if canImport(c11_DEV)
@testable import c11_DEV
#elseif canImport(c11)
@testable import c11
#endif

final class DefaultAgentConfigTests: XCTestCase {

    // MARK: - Codable round-trip

    func testBashIsDefault() {
        XCTAssertEqual(DefaultAgentConfig.bash.agentType, .bash)
        XCTAssertEqual(DefaultAgentConfig.bash.envOverrides, [:])
    }

    func testCodableRoundTripPreservesEveryField() throws {
        let cfg = DefaultAgentConfig(
            agentType: .claudeCode,
            customCommand: "",
            model: "claude-opus-4-7",
            extraArgs: "--dangerously-skip-permissions",
            initialPrompt: "follow the implementation plan",
            cwdMode: .fixed,
            fixedCwd: "/tmp/work",
            envOverrides: ["FOO": "bar", "BAZ": "qux"]
        )
        let data = try JSONEncoder().encode(cfg)
        let decoded = try JSONDecoder().decode(DefaultAgentConfig.self, from: data)
        XCTAssertEqual(decoded, cfg)
    }

    func testLenientDecodeFillsMissingFields() throws {
        let json = #"{"agentType":"claude-code"}"#
        let data = Data(json.utf8)
        let decoded = try JSONDecoder().decode(DefaultAgentConfig.self, from: data)
        XCTAssertEqual(decoded.agentType, .claudeCode)
        XCTAssertEqual(decoded.model, "")
        XCTAssertEqual(decoded.extraArgs, "")
        XCTAssertEqual(decoded.cwdMode, .inherit)
        XCTAssertEqual(decoded.envOverrides, [:])
    }

    func testCorruptDataFallsBackToBash() throws {
        let json = #"{"agentType":"not-a-real-type"}"#
        let data = Data(json.utf8)
        let decoded = try JSONDecoder().decode(DefaultAgentConfig.self, from: data)
        // Unknown agent type falls back to bash via the lenient decoder.
        XCTAssertEqual(decoded.agentType, .bash)
    }

    // MARK: - UserDefaults store

    private func makeStore() -> (DefaultAgentConfigStore, UserDefaults) {
        let suite = "DefaultAgentConfigTests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        return (DefaultAgentConfigStore(defaults: defaults), defaults)
    }

    func testStoreReturnsBashWhenEmpty() {
        let (store, _) = makeStore()
        XCTAssertEqual(store.current, .bash)
    }

    func testStoreRoundTripsSavedConfig() {
        let (store, _) = makeStore()
        let cfg = DefaultAgentConfig(
            agentType: .codex,
            customCommand: "",
            model: "",
            extraArgs: "--yolo",
            initialPrompt: "",
            cwdMode: .inherit,
            fixedCwd: "",
            envOverrides: [:]
        )
        store.save(cfg)
        XCTAssertEqual(store.current, cfg)
    }

    func testStoreResetClearsValue() {
        let (store, _) = makeStore()
        store.save(.bash)
        store.reset()
        XCTAssertEqual(store.current, .bash)
    }

    func testStoreReturnsBashOnGarbageData() {
        let (store, defaults) = makeStore()
        defaults.set(Data("not json".utf8), forKey: DefaultAgentConfigStore.defaultsKey)
        XCTAssertEqual(store.current, .bash)
    }

    // MARK: - Project config discovery

    func testProjectConfigFindReturnsNilForMissingFile() throws {
        let tmp = try makeTempDir()
        defer { try? FileManager.default.removeItem(at: tmp) }
        XCTAssertNil(DefaultAgentProjectConfig.find(from: tmp.path))
    }

    func testProjectConfigFindReadsExactDirectory() throws {
        let tmp = try makeTempDir()
        defer { try? FileManager.default.removeItem(at: tmp) }
        let dotDir = tmp.appendingPathComponent(".c11", isDirectory: true)
        try FileManager.default.createDirectory(at: dotDir, withIntermediateDirectories: true)
        let cfg = DefaultAgentConfig(
            agentType: .claudeCode,
            customCommand: "",
            model: "claude-haiku-4-5-20251001",
            extraArgs: "",
            initialPrompt: "",
            cwdMode: .inherit,
            fixedCwd: "",
            envOverrides: [:]
        )
        let data = try JSONEncoder().encode(cfg)
        try data.write(to: dotDir.appendingPathComponent("agents.json"))
        XCTAssertEqual(DefaultAgentProjectConfig.find(from: tmp.path), cfg)
    }

    func testProjectConfigFindWalksUpward() throws {
        let tmp = try makeTempDir()
        defer { try? FileManager.default.removeItem(at: tmp) }
        let nested = tmp.appendingPathComponent("a").appendingPathComponent("b").appendingPathComponent("c")
        try FileManager.default.createDirectory(at: nested, withIntermediateDirectories: true)
        let dotDir = tmp.appendingPathComponent(".c11", isDirectory: true)
        try FileManager.default.createDirectory(at: dotDir, withIntermediateDirectories: true)
        let cfg = DefaultAgentConfig(
            agentType: .codex,
            customCommand: "",
            model: "",
            extraArgs: "--yolo",
            initialPrompt: "",
            cwdMode: .inherit,
            fixedCwd: "",
            envOverrides: [:]
        )
        try JSONEncoder().encode(cfg).write(to: dotDir.appendingPathComponent("agents.json"))
        XCTAssertEqual(DefaultAgentProjectConfig.find(from: nested.path), cfg)
    }

    func testProjectConfigFindIgnoresMalformedFile() throws {
        let tmp = try makeTempDir()
        defer { try? FileManager.default.removeItem(at: tmp) }
        let dotDir = tmp.appendingPathComponent(".c11", isDirectory: true)
        try FileManager.default.createDirectory(at: dotDir, withIntermediateDirectories: true)
        try Data("not json".utf8).write(to: dotDir.appendingPathComponent("agents.json"))
        XCTAssertNil(DefaultAgentProjectConfig.find(from: tmp.path))
    }

    func testProjectConfigFindReturnsNilForEmptyCwd() {
        XCTAssertNil(DefaultAgentProjectConfig.find(from: nil))
        XCTAssertNil(DefaultAgentProjectConfig.find(from: ""))
    }

    private func makeTempDir() throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("DefaultAgentConfigTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        // Resolve symlinks so .c11 lookups match what `find` standardizes.
        return URL(fileURLWithPath: url.resolvingSymlinksInPath().path, isDirectory: true)
    }
}
