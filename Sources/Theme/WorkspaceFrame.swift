import Foundation
import SwiftUI

public struct SurfaceId: Hashable, Sendable {
    public let rawValue: UUID

    public init(_ rawValue: UUID) {
        self.rawValue = rawValue
    }
}

public struct WindowId: Hashable, Sendable {
    public let rawValue: UUID

    public init(_ rawValue: UUID) {
        self.rawValue = rawValue
    }
}

public enum WorkspaceFrameUrgency: String, Sendable, Equatable {
    case low
    case medium
    case high
}

public enum WorkspaceFrameState: Sendable, Equatable {
    case idle
    case dropTarget(source: SurfaceId? = nil)
    case notifying(WorkspaceFrameUrgency, source: SurfaceId? = nil)
    case mirroring(peer: WindowId? = nil)
}

struct WorkspaceFrame: View {
    let workspace: Workspace
    let theme: C11muxTheme
    let isWorkspaceActive: Bool
    let isWindowFocused: Bool
    var state: WorkspaceFrameState = .idle

    var body: some View {
        EmptyView()
    }
}
