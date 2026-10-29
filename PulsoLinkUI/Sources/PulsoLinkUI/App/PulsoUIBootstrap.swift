import Factory
import Nuke
import PulsoLinkCore

/** UI 层的启动项，宿主 App 在 [PulsoCoreBootstrap.start] 之后调用。 */
public enum PulsoUIBootstrap {
    @MainActor
    public static func start() {
        // 带磁盘缓存的默认管线（Coil 默认也有磁盘缓存）。
        ImagePipeline.shared = ImagePipeline(configuration: .withDataCache)
        Container.shared.sessionTerminator().register(ImageCacheLogoutClearable())
    }
}
