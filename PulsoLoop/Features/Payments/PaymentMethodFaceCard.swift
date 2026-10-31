import PulsoLinkCore
import PulsoLinkUI
import SwiftUI

/**
 * 保存的卡画成实体卡（Android / WEB `PaymentMethodFaceCard`）：按卡组织配色的斜向渐变、右上角一团高光、
 * 金属芯片、遮住的卡号、昵称（没有就卡组织）、有效期和「默认」标签。比例是 ID-1 卡的 1.586。
 */
struct PaymentMethodFaceCard: View {
    let method: PaymentMethodItem

    @Environment(\.pulsoPalette) private var palette

    var body: some View {
        let network = method.brand.prefix(1).uppercased() + method.brand.dropFirst()
        let muted = Color.white.opacity(0.72)
        VStack(alignment: .leading) {
            HStack {
                Text(verbatim: network.uppercased()).font(.footnote.weight(.bold)).foregroundStyle(.white)
                Spacer()
                palette.innerShape
                    .fill(LinearGradient(colors: [.white.opacity(0.55), .white.opacity(0.18), .black.opacity(0.12)], startPoint: .topLeading, endPoint: .bottomTrailing))
                    .overlay { palette.innerShape.stroke(.white.opacity(0.28), lineWidth: pulsoStrokeEmphasis) }
                    .frame(width: 30, height: 22)
            }
            Spacer()
            Text(verbatim: "••••  ••••  ••••  \(method.last4.isEmpty ? "····" : method.last4)")
                .font(.headline.weight(.bold))
                .foregroundStyle(.white)
            Spacer()
            HStack(alignment: .bottom) {
                VStack(alignment: .leading, spacing: PulsoSpace.half) {
                    Text(verbatim: network.uppercased()).font(.caption2).foregroundStyle(muted)
                    Text(verbatim: method.nickname.flatMap { $0.trimmingCharacters(in: .whitespaces).isEmpty ? nil : $0 } ?? network)
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(.white)
                        .lineLimit(1)
                }
                Spacer()
                VStack(alignment: .trailing, spacing: PulsoSpace.half) {
                    Text(verbatim: localizedFormat("payment_methods_expires", method.expiry)).font(.caption2).foregroundStyle(muted)
                    if method.isDefault {
                        Text("payment_methods_default")
                            .font(.caption2.weight(.medium))
                            .foregroundStyle(.white)
                            .padding(.horizontal, PulsoSpace.s2)
                            .padding(.vertical, PulsoSpace.half)
                            .background(.white.opacity(0.2), in: palette.chipShape)
                    }
                }
            }
        }
        .padding(PulsoSpace.s4)
        .frame(maxWidth: .infinity)
        .aspectRatio(1.586, contentMode: .fit)
        .background {
            ZStack {
                LinearGradient(colors: Self.colors(method.brand), startPoint: .topLeading, endPoint: .bottomTrailing)
                // 右上角的一点光，像印刷卡面。
                GeometryReader { proxy in
                    RadialGradient(colors: [.white.opacity(0.22), .clear], center: UnitPoint(x: 0.85, y: 0.1), startRadius: 0, endRadius: proxy.size.width * 0.45)
                }
            }
        }
        .clipShape(palette.cardShape)
        .shadow(color: .black.opacity(0.2), radius: 6, y: 3)
        .accessibilityElement(children: .combine)
    }

    /** 卡组织配色（WEB `PaymentMethodFaceCard` themes）；Stripe 不给发卡行。 */
    private static func colors(_ brand: String) -> [Color] {
        let key = brand.trimmingCharacters(in: .whitespaces).lowercased()
        let hex: [UInt32] = if key.contains("visa") {
            [0x1B3A8F, 0x1A4DB8, 0x0B2A6E]
        } else if key.contains("master") {
            [0x1F1F1F, 0x3A1A12, 0x7A1F12]
        } else if key.contains("amex") || key.contains("american") {
            [0x016FD0, 0x0A4FA3, 0x003D7A]
        } else if key.contains("discover") {
            [0xFF6A00, 0xD9480F, 0x9A3412]
        } else if key.contains("union") {
            [0xE21836, 0x7A1230, 0x00447C]
        } else {
            [0x3F4654, 0x232833, 0x12151C]
        }
        return hex.map { Color(red: Double(($0 >> 16) & 0xFF) / 255, green: Double(($0 >> 8) & 0xFF) / 255, blue: Double($0 & 0xFF) / 255) }
    }
}
