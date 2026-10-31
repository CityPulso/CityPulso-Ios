import SwiftUI
import UIKit

/**
 * 系统控件的外观跟主题走（SwiftUI 的分段 Picker、开关底层是 UIKit）：分段控件画成 Pulso 分段的样子
 * （gray2 轨道、页面底色滑块、选中半粗正文色、其余次要字色），开关打开是强调色。
 * 主题变了重新套一次；UIAppearance 只影响之后新建的控件。
 */
@MainActor
enum PulsoUIKitAppearance {
    static func apply(_ palette: PulsoPalette) {
        let segmented = UISegmentedControl.appearance()
        segmented.backgroundColor = UIColor(palette.gray.step(2))
        segmented.selectedSegmentTintColor = UIColor(palette.background)
        segmented.setTitleTextAttributes([
            .foregroundColor: UIColor(palette.secondaryText),
            .font: UIFont.preferredFont(forTextStyle: .subheadline),
        ], for: .normal)
        segmented.setTitleTextAttributes([
            .foregroundColor: UIColor(palette.text),
            .font: UIFont.systemFont(ofSize: UIFont.preferredFont(forTextStyle: .subheadline).pointSize, weight: .semibold),
        ], for: .selected)
        UISwitch.appearance().onTintColor = UIColor(palette.accent.step(9))
    }
}
