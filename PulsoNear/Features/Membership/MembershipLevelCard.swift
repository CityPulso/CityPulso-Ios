import PulsoLinkCore
import PulsoLinkUI
import SwiftUI

/**
 * 会员卡（Android `MembershipLevelCard`，WEB `MembershipLevelCard`）：等级金属 / 宝石配色的银行卡比例卡面，
 * 按住随手指倾斜，带跟随高光。[muted] 盖一层灰，用于门店还没确认的申请。
 */
struct MembershipLevelCard: View {
    let name: String
    let icon: String
    let color: String
    let discountPercent: Int
    var tag: String?
    var subtitle: String?
    var footer: String?
    var portraitURL: URL?
    var portraitFallback: String?
    var selected = false
    var muted = false

    @State private var tilt = CGSize.zero
    @State private var pressed = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        let theme = MembershipLevelColorPreset.fromWire(color)
        let ink = theme.inkColor
        GeometryReader { proxy in
            ZStack(alignment: .topLeading) {
                theme.gradient
                RadialGradient(colors: [.white.opacity(0.35), .clear], center: .topLeading, startRadius: 0, endRadius: proxy.size.width * 0.9)
                RadialGradient(
                    colors: [.white.opacity(pressed ? 0.4 : 0), .clear],
                    center: UnitPoint(x: 0.5 + tilt.width * 0.5, y: 0.5 + tilt.height * 0.5),
                    startRadius: 0,
                    endRadius: max(proxy.size.width, proxy.size.height) * 0.7
                )
                .blendMode(.screen)
                VStack(alignment: .leading, spacing: 0) {
                    HStack(alignment: .top) {
                        MembershipLevelBadge(icon: icon, color: color, size: 40)
                            .overlay(Circle().stroke(ink.opacity(0.3), lineWidth: 1))
                        Spacer()
                        if let tag {
                            Text(verbatim: tag)
                                .font(.caption2.weight(.semibold))
                                .foregroundStyle(ink)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 3)
                                .background(ink.opacity(0.14), in: .capsule)
                        }
                    }
                    Spacer()
                    HStack(alignment: .bottom) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(verbatim: name).font(.title3.bold()).foregroundStyle(ink).lineLimit(2)
                            if let subtitle, !subtitle.isEmpty {
                                Text(verbatim: subtitle).font(.caption).foregroundStyle(ink.opacity(0.75)).lineLimit(1)
                            }
                            Text(verbatim: discountPercent > 0
                                ? localizedFormat("membership_discount", name, bookingDiscountZhe(discountPercent), String(discountPercent))
                                : String(localized: "membership_no_discount"))
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(ink)
                            if let footer {
                                Text(verbatim: footer).font(.caption2.monospacedDigit()).foregroundStyle(ink.opacity(0.75)).lineLimit(1)
                            }
                        }
                        Spacer(minLength: 8)
                        if portraitURL != nil || portraitFallback != nil {
                            ZStack {
                                Circle().fill(ink.opacity(0.15))
                                if let portraitURL {
                                    PulsoRemoteImage(url: portraitURL).clipShape(.circle)
                                } else if let portraitFallback {
                                    Text(verbatim: portraitFallback).font(.title2.bold()).foregroundStyle(ink)
                                }
                            }
                            .frame(width: 64, height: 64)
                            .overlay(Circle().stroke(ink.opacity(0.4), lineWidth: 3))
                        }
                    }
                }
                .padding(16)
                if muted { Color(.systemGray).opacity(0.45) }
            }
        }
        .aspectRatio(1.586, contentMode: .fit)
        .clipShape(.rect(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(selected ? Color.accentColor : .clear, lineWidth: 2))
        .shadow(color: .black.opacity(pressed ? 0.55 : 0.4), radius: 12, y: pressed ? 14 : 8)
        .rotation3DEffect(.degrees(reduceMotion ? 0 : Double(-tilt.height) * 14), axis: (x: 1, y: 0, z: 0))
        .rotation3DEffect(.degrees(reduceMotion ? 0 : Double(tilt.width) * 14), axis: (x: 0, y: 1, z: 0))
        .scaleEffect(pressed && !reduceMotion ? 1.03 : 1)
        .gesture(
            DragGesture(minimumDistance: 0)
                .onChanged { value in
                    withAnimation(.interactiveSpring) {
                        pressed = true
                        tilt = CGSize(width: (value.translation.width / 150).clamped(to: -1 ... 1), height: (value.translation.height / 100).clamped(to: -1 ... 1))
                    }
                }
                .onEnded { _ in
                    withAnimation(.spring) {
                        pressed = false
                        tilt = .zero
                    }
                }
        )
    }
}
