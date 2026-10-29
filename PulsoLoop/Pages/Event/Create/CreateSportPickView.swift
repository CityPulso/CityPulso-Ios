import PulsoLinkUI
import SwiftUI

/**
 * 第 0 步选运动（Android `SportPickStep`）：一句引导，然后每项能发起的运动一张带运动色的海报卡（名字、一句介绍、
 * 箭头、插画），还没开放的运动在底部变暗显示。
 */
struct CreateSportPickView: View {
    let onSelect: (LoopSport) -> Void

    var body: some View {
        let available = LoopSport.allCases.filter(\.available)
        let comingSoon = LoopSport.allCases.filter { !$0.available }
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("create_flow_hero_title").font(.title2.bold())
                    Text("create_flow_hero_body").font(.body).foregroundStyle(.secondary)
                }
                .padding(.bottom, 8)
                ForEach(available) { sport in
                    Button { onSelect(sport) } label: { poster(sport) }
                        .buttonStyle(.plain)
                }
                if !comingSoon.isEmpty {
                    Text("create_flow_more_sports").font(.subheadline.weight(.medium)).foregroundStyle(.secondary).padding(.top, 12)
                    HStack(spacing: 8) {
                        ForEach(comingSoon) { comingSoonTile($0) }
                    }
                }
                Text("create_flow_intro_hint").font(.footnote).foregroundStyle(.secondary).padding(.top, 8)
            }
            .padding()
        }
    }

    private func poster(_ sport: LoopSport) -> some View {
        let scale = sport.colorScale
        return HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text(sport.labelKey).font(.title3.bold()).foregroundStyle(.primary)
                Text(sport.createBodyKey).font(.subheadline).foregroundStyle(scale.step(11)).lineLimit(2)
                Image(systemName: "arrow.right")
                    .font(.subheadline.bold())
                    .foregroundStyle(.white)
                    .frame(width: 32, height: 32)
                    .background(scale.step(9), in: .circle)
                    .padding(.top, 8)
            }
            Spacer(minLength: 0)
            Image(sport.iconAsset)
                .resizable()
                .scaledToFit()
                .frame(width: 72, height: 72)
                .frame(width: 104, height: 104)
                .background(scale.step(5), in: .circle)
        }
        .padding(.leading, 20)
        .padding([.trailing, .vertical], 16)
        .background(LinearGradient(colors: [scale.step(3), scale.step(4)], startPoint: .leading, endPoint: .trailing), in: .rect(cornerRadius: 20))
        .contentShape(.rect(cornerRadius: 20))
    }

    private func comingSoonTile(_ sport: LoopSport) -> some View {
        VStack(spacing: 4) {
            Image(sport.iconAsset).resizable().scaledToFit().frame(width: 32, height: 32)
            Text(sport.labelKey).font(.caption.weight(.semibold)).lineLimit(1)
            Text("create_flow_coming_soon")
                .font(.caption2)
                .foregroundStyle(sport.colorScale.step(11))
                .padding(.horizontal, 8)
                .padding(.vertical, 2)
                .background(sport.colorScale.step(3), in: .capsule)
        }
        .padding(.vertical, 12)
        .padding(.horizontal, 8)
        .frame(maxWidth: .infinity)
        .background(.background.secondary, in: .rect(cornerRadius: 16))
        .opacity(0.7)
    }
}

/**
 * 基本信息步的运动行（Android `CreateSportTiles`）：当前运动在前，再是其他能发起的运动，最后「更多」回到选运动页。
 * 换运动保留已填的内容。
 */
struct CreateSportTiles: View {
    let selected: LoopSport
    let enabled: Bool
    let onSelect: (LoopSport) -> Void
    let onMore: () -> Void

    private static let shown = 7

    var body: some View {
        let sports = Array(([selected] + LoopSport.allCases.filter { $0.available && $0 != selected }).prefix(Self.shown))
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(sports) { sport in
                    tile(selected: sport == selected) {
                        Image(sport.iconAsset).resizable().scaledToFit().frame(width: 32, height: 32)
                        Text(sport.labelKey)
                    } action: {
                        if sport != selected { onSelect(sport) }
                    }
                }
                tile(selected: false) {
                    Image(systemName: "ellipsis").font(.title2).frame(width: 32, height: 32)
                    Text("create_sport_more")
                } action: {
                    onMore()
                }
            }
        }
        .disabled(!enabled)
    }

    private func tile(selected: Bool, @ViewBuilder content: () -> some View, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: 6) { content() }
                .font(.caption.weight(.medium))
                .frame(width: 76, height: 76)
                .background(selected ? Color.accentColor.opacity(0.12) : Color.clear, in: .rect(cornerRadius: 14))
                .overlay(RoundedRectangle(cornerRadius: 14).stroke(selected ? Color.accentColor : Color(.separator)))
        }
        .buttonStyle(.plain)
    }
}

extension LoopSport {
    /** 选运动海报上的一句介绍。 */
    var createBodyKey: LocalizedStringKey {
        switch self {
        case .badminton: "create_flow_badminton_body"
        case .tennis: "create_flow_tennis_body"
        case .pickleball: "create_flow_pickleball_body"
        case .basketball: "create_flow_basketball_body"
        case .football: "create_flow_football_body"
        case .baseball: "create_flow_baseball_body"
        case .golf: "create_flow_golf_body"
        case .hiking: "create_flow_hiking_body"
        case .fishing: "create_flow_fishing_body"
        case .ski: "create_flow_ski_body"
        case .tableTennis: "create_flow_table_tennis_body"
        }
    }
}
