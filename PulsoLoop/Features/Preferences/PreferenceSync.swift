import Factory
import PulsoLinkCore
import PulsoLinkUI

/**
 * 「改本地偏好，再推到 community 身份上」的唯一路径（对应 Android `PreferenceSync`）。
 * 本地先存好；同步失败只提示，不回滚。
 */
@MainActor
enum PreferenceSync {
    private static let settleDelay = Duration.milliseconds(800)
    private static var pending: Task<Void, Never>?

    /** 把当前本地偏好整份推到服务端。 */
    static func push() async {
        pending?.cancel()
        do {
            try await Container.shared.preferenceService().syncToServer(kind: .community)
        } catch {
            PulsoMessageCenter.shared.error(error, fallback: "preference_sync_failed")
        }
    }

    /** 本地改完立即生效，连续改动（连点、拖动）停下 0.8 秒后只推一次。 */
    static func pushSoon() {
        pending?.cancel()
        pending = Task {
            try? await Task.sleep(for: settleDelay)
            guard !Task.isCancelled else { return }
            await push()
        }
    }

    /** 改本地偏好并推送。 */
    static func save(_ edit: (inout ResolvedPreference) -> Void) async {
        Container.shared.preferenceService().update(edit)
        await push()
    }
}
