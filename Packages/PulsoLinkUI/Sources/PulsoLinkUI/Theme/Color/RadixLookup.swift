import PulsoLinkCore
import SwiftUI

extension RadixColorScales {
    /** 强调色的 Radix 色阶（按明暗）。 */
    public static func accent(_ accent: ThemeAccentColor, dark: Bool) -> RadixScale {
        switch accent {
        case .gray: dark ? grayDark : grayLight
        case .gold: dark ? goldDark : goldLight
        case .bronze: dark ? bronzeDark : bronzeLight
        case .brown: dark ? brownDark : brownLight
        case .yellow: dark ? yellowDark : yellowLight
        case .amber: dark ? amberDark : amberLight
        case .orange: dark ? orangeDark : orangeLight
        case .tomato: dark ? tomatoDark : tomatoLight
        case .red: dark ? redDark : redLight
        case .ruby: dark ? rubyDark : rubyLight
        case .crimson: dark ? crimsonDark : crimsonLight
        case .pink: dark ? pinkDark : pinkLight
        case .plum: dark ? plumDark : plumLight
        case .purple: dark ? purpleDark : purpleLight
        case .violet: dark ? violetDark : violetLight
        case .iris: dark ? irisDark : irisLight
        case .indigo: dark ? indigoDark : indigoLight
        case .blue: dark ? blueDark : blueLight
        case .cyan: dark ? cyanDark : cyanLight
        case .teal: dark ? tealDark : tealLight
        case .jade: dark ? jadeDark : jadeLight
        case .green: dark ? greenDark : greenLight
        case .grass: dark ? grassDark : grassLight
        case .lime: dark ? limeDark : limeLight
        case .mint: dark ? mintDark : mintLight
        case .sky: dark ? skyDark : skyLight
        }
    }

    /** [gray] 必须是已经过 [resolveGrayColor] 的具体灰（auto 不合法）。 */
    public static func gray(_ gray: ThemeGrayColor, dark: Bool) -> RadixScale {
        switch gray {
        case .gray: dark ? grayDark : grayLight
        case .mauve: dark ? mauveDark : mauveLight
        case .slate: dark ? slateDark : slateLight
        case .sage: dark ? sageDark : sageLight
        case .olive: dark ? oliveDark : oliveLight
        case .sand: dark ? sandDark : sandLight
        case .auto: preconditionFailure("gray=auto must be resolved via resolveGrayColor before use")
        }
    }
}

/**
 * gray=auto 时按 accent 自动配对中性灰——与 @radix-ui/themes `getMatchingGrayColor` 官方映射逐一对齐。
 */
public func resolveGrayColor(_ gray: ThemeGrayColor, accent: ThemeAccentColor) -> ThemeGrayColor {
    guard gray == .auto else { return gray }
    switch accent {
    case .tomato, .red, .ruby, .crimson, .pink, .plum, .purple, .violet: return .mauve
    case .iris, .indigo, .blue, .sky, .cyan: return .slate
    case .teal, .jade, .mint, .green: return .sage
    case .grass, .lime: return .olive
    case .yellow, .amber, .orange, .brown, .gold, .bronze: return .sand
    case .gray: return .gray
    }
}
