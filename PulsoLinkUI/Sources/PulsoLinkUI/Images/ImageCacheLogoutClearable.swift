import Nuke
import PulsoLinkCore

/** Nuke 的内存和磁盘缓存里可能有上一个账号的头像和私人图片，退出登录时清掉（Android `ImageCacheLogoutClearable`）。 */
struct ImageCacheLogoutClearable: LogoutClearable {
    func onLogout() async throws {
        ImagePipeline.shared.cache.removeAll()
    }
}
