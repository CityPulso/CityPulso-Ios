import Factory
import Foundation
import PulsoLinkCore

/**
 * iOS 的界面语言由系统「设置 → 本 App → 语言」决定（每个 App 单独选）。
 * 这里把实际在用的语言写回偏好并同步，邮件、推送等服务端发出的内容跟着用同一种语言。
 */
@MainActor
enum AppLanguageSync {
    /** 本 App 当前实际显示的语言。 */
    static var appLanguage: PulsoLanguage {
        PulsoLanguage(localization: Bundle.main.preferredLocalizations.first)
    }

    static func sync() async {
        let preferences = Container.shared.preferenceService()
        let language = appLanguage
        guard preferences.preference.value.language != language else { return }
        await PreferenceSync.save { $0.language = language }
    }
}

extension PulsoLanguage {
    /** lproj 名（zh-Hans / zh-Hant / en / fr）→ 偏好里的语言。 */
    init(localization: String?) {
        switch localization {
        case "zh-Hant": self = .zhHant
        case "en": self = .en
        case "fr": self = .fr
        default: self = .zh
        }
    }

    /** 语言名用各自的写法（不翻译）。 */
    var nativeName: String {
        switch self {
        case .zh: "简体中文"
        case .zhHant: "繁體中文"
        case .en: "English"
        case .fr: "Français"
        }
    }
}
