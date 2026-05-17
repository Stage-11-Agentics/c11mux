import XCTest

#if canImport(c11_DEV)
@testable import c11_DEV
#elseif canImport(c11)
@testable import c11
#endif

final class DefaultAgentResolverTests: XCTestCase {

    // MARK: - fixtures

    private let claudeDefault = DefaultAgentConfig(
        agentType: .claudeCode,
        customCommand: "",
        model: "claude-opus-4-7",
        extraArgs: "--dangerously-skip-permissions",
        initialPrompt: "",
        cwdMode: .inherit,
        fixedCwd: "",
        envOverrides: [:]
    )

    private let codexProject = DefaultAgentConfig(
        agentType: .codex,
        customCommand: "",
        model: "",
        extraArgs: "--yolo",
        initialPrompt: "",
        cwdMode: .inherit,
        fixedCwd: "",
        envOverrides: ["CODEX_PROJECT": "1"]
    )

    // MARK: - precedence

    func testForceBashAlwaysWins() throws {
        let result = try DefaultAgentResolver.resolve(
            explicitAgent: nil,
            forceBash: true,
            workspaceOverride: .none,
            userDefault: claudeDefault,
            projectConfig: codexProject
        )
        XCTAssertEqual(result, .bash)
    }

    func testForceBashBeatsExplicitAgent() throws {
        let result = try DefaultAgentResolver.resolve(
            explicitAgent: "default",
            forceBash: true,
            workspaceOverride: WorkspaceAgentOverride(useBash: false, inlineConfig: codexProject),
            userDefault: claudeDefault,
            projectConfig: codexProject
        )
        XCTAssertEqual(result, .bash)
    }

    func testWorkspaceUseBashBeatsProjectAndUser() throws {
        let result = try DefaultAgentResolver.resolve(
            explicitAgent: nil,
            forceBash: false,
            workspaceOverride: WorkspaceAgentOverride(useBash: true, inlineConfig: nil),
            userDefault: claudeDefault,
            projectConfig: codexProject
        )
        XCTAssertEqual(result, .bash)
    }

    func testWorkspaceInlineBeatsProject() throws {
        // The resolver still accepts an inlineConfig override (reserved for a
        // follow-up that exposes per-workspace inline config via metadata or
        // workspace blueprint). C11-14 first PR only wires `useBash`.
        let inline = DefaultAgentConfig(
            agentType: .kimi,
            customCommand: "",
            model: "",
            extraArgs: "",
            initialPrompt: "",
            cwdMode: .inherit,
            fixedCwd: "",
            envOverrides: [:]
        )
        let result = try DefaultAgentResolver.resolve(
            explicitAgent: nil,
            forceBash: false,
            workspaceOverride: WorkspaceAgentOverride(useBash: false, inlineConfig: inline),
            userDefault: claudeDefault,
            projectConfig: codexProject
        )
        XCTAssertEqual(result.command, "kimi")
    }

    func testProjectBeatsUser() throws {
        let result = try DefaultAgentResolver.resolve(
            explicitAgent: nil,
            forceBash: false,
            workspaceOverride: .none,
            userDefault: claudeDefault,
            projectConfig: codexProject
        )
        XCTAssertEqual(result.command, "codex --yolo")
        XCTAssertEqual(result.envOverrides, ["CODEX_PROJECT": "1"])
    }

    func testUserDefaultUsedWhenNoOtherSource() throws {
        let result = try DefaultAgentResolver.resolve(
            explicitAgent: nil,
            forceBash: false,
            workspaceOverride: .none,
            userDefault: claudeDefault,
            projectConfig: nil
        )
        XCTAssertEqual(result.command, "claude --model 'claude-opus-4-7' --dangerously-skip-permissions")
    }

    func testBashAgentTypeInUserDefaultFallsThrough() throws {
        let result = try DefaultAgentResolver.resolve(
            explicitAgent: nil,
            forceBash: false,
            workspaceOverride: .none,
            userDefault: .bash,
            projectConfig: nil
        )
        XCTAssertEqual(result, .bash)
    }

    func testExplicitAgentDefaultIsAccepted() throws {
        let result = try DefaultAgentResolver.resolve(
            explicitAgent: "default",
            forceBash: false,
            workspaceOverride: .none,
            userDefault: claudeDefault,
            projectConfig: nil
        )
        XCTAssertEqual(result.command, "claude --model 'claude-opus-4-7' --dangerously-skip-permissions")
    }

    func testExplicitAgentDefaultTrimmedAndCaseInsensitive() throws {
        let result = try DefaultAgentResolver.resolve(
            explicitAgent: "  DEFAULT  ",
            forceBash: false,
            workspaceOverride: .none,
            userDefault: claudeDefault,
            projectConfig: nil
        )
        XCTAssertEqual(result.command, "claude --model 'claude-opus-4-7' --dangerously-skip-permissions")
    }

    func testUnknownExplicitAgentThrows() {
        XCTAssertThrowsError(
            try DefaultAgentResolver.resolve(
                explicitAgent: "claude-opus",
                forceBash: false,
                workspaceOverride: .none,
                userDefault: claudeDefault,
                projectConfig: nil
            )
        ) { error in
            XCTAssertEqual(error as? DefaultAgentResolverError, .unknownAgentName("claude-opus"))
        }
    }

    // MARK: - command builder

    func testBuildCommandClaudeWithModelAndArgs() {
        let cfg = DefaultAgentConfig(
            agentType: .claudeCode,
            customCommand: "",
            model: "claude-opus-4-7",
            extraArgs: "--dangerously-skip-permissions",
            initialPrompt: "",
            cwdMode: .inherit,
            fixedCwd: "",
            envOverrides: [:]
        )
        XCTAssertEqual(
            DefaultAgentResolver.buildCommand(for: cfg),
            "claude --model 'claude-opus-4-7' --dangerously-skip-permissions"
        )
    }

    func testBuildCommandCodexNoModel() {
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
        XCTAssertEqual(DefaultAgentResolver.buildCommand(for: cfg), "codex --yolo")
    }

    func testBuildCommandCustomBinary() {
        let cfg = DefaultAgentConfig(
            agentType: .custom,
            customCommand: "/usr/local/bin/myagent --foo",
            model: "",
            extraArgs: "--bar",
            initialPrompt: "",
            cwdMode: .inherit,
            fixedCwd: "",
            envOverrides: [:]
        )
        XCTAssertEqual(
            DefaultAgentResolver.buildCommand(for: cfg),
            "/usr/local/bin/myagent --foo --bar"
        )
    }

    func testBuildCommandClaudeWithInitialPromptAppendsPositional() {
        let cfg = DefaultAgentConfig(
            agentType: .claudeCode,
            customCommand: "",
            model: "claude-opus-4-7",
            extraArgs: "",
            initialPrompt: "read the plan and follow it",
            cwdMode: .inherit,
            fixedCwd: "",
            envOverrides: [:]
        )
        XCTAssertEqual(
            DefaultAgentResolver.buildCommand(for: cfg),
            "claude --model 'claude-opus-4-7' 'read the plan and follow it'"
        )
    }

    func testBuildCommandEscapesSingleQuoteInPrompt() {
        let cfg = DefaultAgentConfig(
            agentType: .claudeCode,
            customCommand: "",
            model: "",
            extraArgs: "",
            initialPrompt: "don't stop",
            cwdMode: .inherit,
            fixedCwd: "",
            envOverrides: [:]
        )
        // Standard sh single-quote escape: don't  → 'don'\''t'
        XCTAssertEqual(
            DefaultAgentResolver.buildCommand(for: cfg),
            #"claude 'don'\''t stop'"#
        )
    }

    func testBuildCommandCodexIgnoresInitialPrompt() {
        // Codex/kimi/opencode don't get auto-prompt — they have different
        // delivery contracts. Operators can put it in extraArgs if they want.
        let cfg = DefaultAgentConfig(
            agentType: .codex,
            customCommand: "",
            model: "",
            extraArgs: "--yolo",
            initialPrompt: "follow the plan",
            cwdMode: .inherit,
            fixedCwd: "",
            envOverrides: [:]
        )
        XCTAssertEqual(DefaultAgentResolver.buildCommand(for: cfg), "codex --yolo")
    }

    func testShellQuoteEmpty() {
        XCTAssertEqual(DefaultAgentResolver.shellQuote(""), "''")
    }

    // MARK: - cwd resolution

    func testCwdInheritReturnsNil() throws {
        let result = try DefaultAgentResolver.resolve(
            explicitAgent: nil,
            forceBash: false,
            workspaceOverride: .none,
            userDefault: claudeDefault,
            projectConfig: nil
        )
        XCTAssertNil(result.workingDirectory)
    }

    func testCwdFixedSetsWorkingDirectory() throws {
        let cfg = DefaultAgentConfig(
            agentType: .claudeCode,
            customCommand: "",
            model: "",
            extraArgs: "",
            initialPrompt: "",
            cwdMode: .fixed,
            fixedCwd: "/tmp/work",
            envOverrides: [:]
        )
        let result = try DefaultAgentResolver.resolve(
            explicitAgent: nil,
            forceBash: false,
            workspaceOverride: .none,
            userDefault: cfg,
            projectConfig: nil
        )
        XCTAssertEqual(result.workingDirectory, "/tmp/work")
    }

    func testCwdFixedWithEmptyPathFallsBackToNil() throws {
        let cfg = DefaultAgentConfig(
            agentType: .claudeCode,
            customCommand: "",
            model: "",
            extraArgs: "",
            initialPrompt: "",
            cwdMode: .fixed,
            fixedCwd: "   ",
            envOverrides: [:]
        )
        let result = try DefaultAgentResolver.resolve(
            explicitAgent: nil,
            forceBash: false,
            workspaceOverride: .none,
            userDefault: cfg,
            projectConfig: nil
        )
        XCTAssertNil(result.workingDirectory)
    }
}
