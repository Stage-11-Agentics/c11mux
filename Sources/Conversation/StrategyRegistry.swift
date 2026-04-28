import Foundation

/// Hardcoded enum-shaped registry of `ConversationStrategy`s. We are not
/// building a plugin system — adding a new kind is one Swift file in
/// `Sources/Conversation/Strategies/` plus an entry in `defaultStrategies`.
///
/// Stored as an immutable map keyed by `kind`; lookups are O(1).
public struct ConversationStrategyRegistry: Sendable {
    private let strategies: [String: any ConversationStrategy]

    public init(strategies: [any ConversationStrategy]) {
        var map: [String: any ConversationStrategy] = [:]
        for strategy in strategies {
            map[strategy.kind] = strategy
        }
        self.strategies = map
    }

    public func strategy(forKind kind: String) -> (any ConversationStrategy)? {
        strategies[kind]
    }

    public func contains(kind: String) -> Bool {
        strategies[kind] != nil
    }

    public var allKinds: [String] {
        Array(strategies.keys).sorted()
    }

    /// Default v1 registry. Lands the four strategies the plan specifies:
    /// claude-code (push-primary), codex (pull-primary, ambiguity-aware),
    /// opencode and kimi (fresh-launch only).
    public static let v1: ConversationStrategyRegistry = {
        ConversationStrategyRegistry(strategies: [
            ClaudeCodeStrategy(),
            CodexStrategy(),
            OpencodeStrategy(),
            KimiStrategy()
        ])
    }()
}
