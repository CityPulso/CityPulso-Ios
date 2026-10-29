import Factory
import PulsoLinkCore
import SwiftUI

/**
 * 会话状态的 SwiftUI 入口：订阅 [AuthSessionStore] 与 [StartupGate]，主线程上可观察。
 * 根视图据此在「开屏 / 登录 / 主界面」之间切换。
 */
@MainActor
@Observable
public final class PulsoSessionModel {
    public private(set) var session: AuthSession
    public private(set) var isReady: Bool

    @ObservationIgnored private nonisolated(unsafe) var tasks: [Task<Void, Never>] = []

    public init() {
        let store = Container.shared.authSessionStore()
        let gate = Container.shared.startupGate()
        session = store.state.value
        isReady = gate.isReady.value

        let sessions = store.state.values()
        let readiness = gate.isReady.values()
        tasks = [
            Task { [weak self] in
                for await value in sessions { self?.session = value }
            },
            Task { [weak self] in
                for await value in readiness { self?.isReady = value }
            },
        ]
    }

    deinit {
        tasks.forEach { $0.cancel() }
    }

    /** 已登录且选好身份，可以进主界面。 */
    public var isSignedIn: Bool { session.isCompleteSession }

    public func signOut() async {
        await Container.shared.sessionTerminator().terminate(.user)
    }
}
