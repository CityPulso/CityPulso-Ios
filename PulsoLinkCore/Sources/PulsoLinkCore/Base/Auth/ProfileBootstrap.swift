import AsyncAlgorithms
import Foundation
import Semaphore

/**
 * 登录后档案引导（对应 WEB SharedDataBootstrap）：
 * - 会话「有效 + 已选 profile」（登录成功或启动恢复完整会话）→ 拉取
 *   GetCurrentFullAccountInformationWithProfile 填充 [ProfileStore]；
 * - 会话失效/登出 → 清空；
 * - 账号资料更新成功（updateAccountSuccess）→ 重拉。
 */
public final class ProfileBootstrap: @unchecked Sendable {
    private struct Key: Hashable, Sendable {
        let profileId: String
        let kind: ProfileKind
    }

    private let authService: AuthService
    private let sessionStore: AuthSessionStore
    private let profileStore: ProfileStore
    private let authEventBus: AuthEventBus
    private let fetchLock = AsyncSemaphore(value: 1)
    private let lock = NSLock()
    private var loadedKey: Key?
    private var watchers: [Task<Void, Never>] = []

    public init(authService: AuthService, sessionStore: AuthSessionStore, profileStore: ProfileStore, authEventBus: AuthEventBus) {
        self.authService = authService
        self.sessionStore = sessionStore
        self.profileStore = profileStore
        self.authEventBus = authEventBus
    }

    /** App 启动时调用一次。 */
    public func start() {
        let keys = combineLatest(sessionStore.state.values(), sessionStore.isRestored.values())
            .map { session, restored in restored ? Self.key(for: session) : nil }
            .removeDuplicates()
        let events = authEventBus.events()
        let tasks = [
            Task { [weak self] in
                for await key in keys {
                    guard let self else { return }
                    if let key {
                        await fetch(key)
                    } else {
                        await withLoadLock {
                            self.profileStore.clear()
                            self.setLoadedKey(nil)
                        }
                    }
                }
            },
            Task { [weak self] in
                for await event in events where event == .updateAccountSuccess {
                    guard let self, let key = Self.key(for: sessionStore.state.value) else { continue }
                    await fetch(key, force: true)
                }
            },
        ]
        lock.withLock { watchers = tasks }
    }

    /**
     * 登录：用刚选好的身份读到的档案先放进 [ProfileStore]，再把身份写进会话，App 一打开就是它而不是加载中；
     * 随后的会话变化不会再拉一遍。
     */
    public func adopt(_ info: CurrentFullAccountInformation, profileId: String, kind: ProfileKind) async {
        await withLoadLock {
            self.profileStore.set(info)
            self.setLoadedKey(Key(profileId: profileId, kind: kind))
        }
    }

    /** 冷启动 / 开屏：等到当前会话档案写入 [ProfileStore]（已加载则不重复打网）。 */
    public func ensureLoaded() async {
        guard let key = Self.key(for: sessionStore.state.value) else { return }
        await fetch(key)
    }

    /**
     * 下拉刷新个人页：重拉进 [ProfileStore] 并把失败抛给调用方报告；[ProfileStore] 仍是档案唯一真相。
     */
    public func refresh() async throws {
        guard let key = Self.key(for: sessionStore.state.value) else { return }
        try await withLoadLock {
            self.profileStore.set(try await self.authService.getCurrentFullAccountInformationWithProfile(kind: key.kind))
            self.setLoadedKey(key)
        }
    }

    private func fetch(_ key: Key, force: Bool = false) async {
        await withLoadLock {
            if !force, self.currentLoadedKey == key, self.profileStore.current.value != nil { return }
            do {
                let info = try await self.authService.getCurrentFullAccountInformationWithProfile(kind: key.kind)
                // 拉取期间切了身份 / 登出：这份结果已过期，交给下一次 key 变化处理。
                guard Self.key(for: self.sessionStore.state.value) == key else { return }
                self.profileStore.set(info)
                self.setLoadedKey(key)
            } catch {
                // 失败由下一次会话变化、refresh() 或 ensureLoaded() 重试。
                debugLog("Profile bootstrap failed: \(error)")
            }
        }
    }

    private func withLoadLock<T: Sendable>(_ body: @Sendable () async throws -> T) async rethrows -> T {
        await fetchLock.wait()
        defer { fetchLock.signal() }
        return try await body()
    }

    private var currentLoadedKey: Key? { lock.withLock { loadedKey } }

    private func setLoadedKey(_ key: Key?) {
        lock.withLock { loadedKey = key }
    }

    private static func key(for session: AuthSession) -> Key? {
        guard session.isAuthValid, session.hasSelectedProfile else { return nil }
        return Key(profileId: session.currentProfileId, kind: session.currentProfileKind)
    }

    deinit {
        watchers.forEach { $0.cancel() }
    }
}
