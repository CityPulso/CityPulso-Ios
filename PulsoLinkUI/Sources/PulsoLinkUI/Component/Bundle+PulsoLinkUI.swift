import Foundation

extension Bundle {
    /** 共享 UI 的文案包（pulso_ui_* key），App 里用 `Text("…", bundle: .pulsoLinkUI)`。 */
    public static var pulsoLinkUI: Bundle { .module }
}
