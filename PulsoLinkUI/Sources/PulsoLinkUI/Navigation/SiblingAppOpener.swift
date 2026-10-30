import PulsoLinkCore
import UIKit

extension SiblingApp {
    /**
     * 装了就在那个 App 里打开 [path]（Info.plist 的 `LSApplicationQueriesSchemes` 列了它的 scheme），否则打开它的网站
     * （Android `openInSiblingApp`）。两样都打不开时返回 false。
     */
    @MainActor
    @discardableResult
    public func open(_ path: String) async -> Bool {
        if let link = deepLink(path), UIApplication.shared.canOpenURL(link), await UIApplication.shared.open(link) {
            return true
        }
        guard let web = webURL(path) else { return false }
        return await UIApplication.shared.open(web)
    }
}
