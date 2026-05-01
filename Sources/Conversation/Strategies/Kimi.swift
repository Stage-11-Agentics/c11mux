import Foundation

/// Fresh-launch-only strategy for Kimi. Same shape as Opencode in v1.
struct KimiStrategy: ConversationStrategy {
    let kind: String = "kimi"

    init() {}

    func capture(inputs: ConversationStrategyInputs) -> ConversationRef? {
        if let push = inputs.push, !push.placeholder {
            return push
        }
        return inputs.wrapperClaim
    }

    func resume(ref: ConversationRef) -> ResumeAction {
        if ref.placeholder {
            return .skip(reason: "fresh-launch-only")
        }
        switch ref.state {
        case .alive, .suspended:
            return .typeCommand(text: conversationShellQuote("kimi"), submitWithReturn: true)
        default:
            return .skip(reason: "state=\(ref.state.rawValue) not auto-resumable")
        }
    }
}
