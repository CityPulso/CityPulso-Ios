import PulsoLinkCore
import PulsoLinkUI
import SwiftUI

/**
 * 第 0 步（Android `ActivityTypePickStep`）：一句标题，然后按三组（牌桌与推理 / 场馆娱乐 / 交友与兴趣，WEB
 * `NEAR_ACTIVITY_TYPE_GROUPS`）列出活动类型，一行两张卡，用类型的颜色、图标、建议人数和提示标签。
 */
struct CreateActivityTypePickView: View {
    let onSelect: (NearActivityKind) -> Void

    private let columns = [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("create_flow_hero_title").font(.title2.bold())
                    Text("create_flow_hero_body").font(.subheadline).foregroundStyle(.secondary)
                }
                .padding(.bottom, 8)
                ForEach(NearActivityGroup.allCases, id: \.self) { group in
                    Text(group.labelKey).font(.headline).padding(.top, 8)
                    LazyVGrid(columns: columns, spacing: 12) {
                        ForEach(NearActivityKind.allCases.filter { $0.group == group }) { kind in
                            ActivityTypePickCard(kind: kind) { onSelect(kind) }
                        }
                    }
                }
                Text("create_flow_intro_hint").font(.footnote).foregroundStyle(.secondary).padding(.top, 8)
            }
            .padding()
        }
    }
}

/** 一种活动：类型色的渐变卡；还没开放的变淡、不能选。 */
private struct ActivityTypePickCard: View {
    let kind: NearActivityKind
    let onTap: () -> Void

    @Environment(\.pulsoPalette) private var palette

    var body: some View {
        let scale = kind.colorScale
        Button(action: onTap) {
            VStack(alignment: .leading, spacing: 8) {
                HStack(alignment: .top) {
                    Image(kind.iconAsset)
                        .resizable()
                        .scaledToFit()
                        .frame(width: 40, height: 40)
                        .frame(width: 56, height: 56)
                        .background(scale.step(5), in: palette.innerShape)
                    Spacer(minLength: 8)
                    // 标签在右上角、和图标同一行，有没有标签卡片都一样高。
                    VStack(alignment: .trailing, spacing: 4) {
                        if !kind.available { tag(Text("create_flow_coming_soon"), scale: scale) }
                        if let notice = kind.notice { tag(Text(notice.tagKey), scale: notice.scale) }
                    }
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text(kind.labelKey).font(.headline).lineLimit(1)
                    // 类型的默认人数只是建议，发起人在表单里可以改。
                    Text(verbatim: kind.defaultMinParticipants == kind.defaultMaxParticipants
                        ? localizedFormat("create_flow_suggested_participants_exact", kind.defaultMaxParticipants)
                        : localizedFormat("create_flow_suggested_participants_range", kind.defaultMinParticipants, kind.defaultMaxParticipants))
                        .font(.caption)
                        .foregroundStyle(scale.step(11))
                }
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(LinearGradient(colors: [scale.step(3), scale.step(4)], startPoint: .top, endPoint: .bottom), in: palette.cardShape)
            .foregroundStyle(.primary)
        }
        .buttonStyle(.plain)
        .disabled(!kind.available)
        .opacity(kind.available ? 1 : 0.7)
    }

    private func tag(_ text: Text, scale: RadixScale) -> some View {
        text
            .font(.caption2)
            .foregroundStyle(scale.step(11))
            .padding(.horizontal, 8)
            .padding(.vertical, 2)
            .background(scale.step(3), in: .capsule)
    }
}

extension NearActivityNotice {
    /** 类型卡上的短标签。 */
    var tagKey: LocalizedStringKey {
        switch self {
        case .noGambling: "create_activity_tag_no_gambling"
        case .adultsOnly: "create_activity_tag_adults_only"
        }
    }
}

/**
 * 基础步骤里的类型横排（Android `CreateActivityTypeTiles`）：选中的在最前，然后其他能发起的类型，最后「更多」回到选类型页。
 * 点一个就把表单换成那种类型，已填的保留。
 */
struct CreateActivityTypeTiles: View {
    let selected: NearActivityKind
    let enabled: Bool
    let onSelect: (NearActivityKind) -> Void
    let onMore: () -> Void

    private static let shown = 7

    var body: some View {
        let kinds = Array(([selected] + NearActivityKind.allCases.filter { $0.available && $0 != selected }).prefix(Self.shown))
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(kinds) { kind in
                    tile(selected: kind == selected) {
                        Image(kind.iconAsset).resizable().scaledToFit().frame(width: 32, height: 32)
                        Text(kind.labelKey).lineLimit(1).minimumScaleFactor(0.8)
                    } action: {
                        if kind != selected { onSelect(kind) }
                    }
                }
                tile(selected: false) {
                    Image(systemName: "ellipsis").font(.title2).frame(width: 32, height: 32)
                    Text("create_activity_type_more")
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
