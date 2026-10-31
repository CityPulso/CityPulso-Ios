import Factory
import PulsoLinkCore
import PulsoLinkUI
import SwiftUI

/** 一个收藏心形的状态（Android `FavoriteHeartViewModel`）：登录且读到状态才显示；读不到就一直不显示。 */
@MainActor
@Observable
final class FavoriteHeartModel {
    let target: FavoriteTarget
    let id: String

    private(set) var visible = false
    private(set) var favorited = false
    private(set) var pending = false

    @ObservationIgnored @Injected(\.favoriteService) private var favorites
    @ObservationIgnored @Injected(\.authSessionStore) private var sessionStore

    init(target: FavoriteTarget, id: String) {
        self.target = target
        self.id = id
    }

    func observe() async {
        var signedIn: Bool?
        for await session in sessionStore.state.values() {
            let next = session.isAuthValid && !session.currentProfileId.isEmpty
            guard next != signedIn else { continue }
            signedIn = next
            if next {
                if let favorited = try? await favorites.isFavorite(target, id: id) {
                    self.favorited = favorited
                    visible = true
                } else {
                    visible = false
                }
            } else {
                visible = false
                favorited = false
            }
        }
    }

    func toggle() async {
        guard !pending else { return }
        pending = true
        defer { pending = false }
        do {
            try await favorites.setFavorite(target, id: id, favorite: !favorited)
            favorited.toggle()
        } catch {
            PulsoMessageCenter.shared.error(error, fallback: "favorites_toggle_failed")
        }
    }
}

/** 心形画在哪儿：普通图标、封面照片上的玻璃圆钮、详情页快捷操作那一排的方块加小字。 */
enum FavoriteHeartStyle {
    case plain
    case overlay
    case tile
}

/** 球馆 / 建筑上的收藏心形（Android `FavoriteHeartAction`）；没登录时不显示。 */
struct FavoriteHeart: View {
    let name: String
    var style = FavoriteHeartStyle.plain
    @State private var model: FavoriteHeartModel
    @Environment(\.pulsoPalette) private var palette

    init(target: FavoriteTarget, id: String, name: String, style: FavoriteHeartStyle = .plain) {
        self.name = name
        self.style = style
        _model = State(initialValue: FavoriteHeartModel(target: target, id: id))
    }

    var body: some View {
        Group {
            if model.visible {
                Button {
                    Task { await model.toggle() }
                } label: {
                    label
                }
                .buttonStyle(.plain)
                .disabled(model.pending)
                .accessibilityLabel(Text(verbatim: localizedFormat(model.favorited ? "favorites_remove_named" : "favorites_add_named", name)))
            }
        }
        .task { await model.observe() }
    }

    @ViewBuilder
    private var label: some View {
        let heart = Image(systemName: model.favorited ? "heart.fill" : "heart")
            .pulsoToggleBurst(active: model.favorited, color: palette.accent.step(9))
        switch style {
        case .plain:
            heart
                .foregroundStyle(model.favorited ? palette.accent.step(9) : palette.text)
                .frame(width: 36, height: 36)
        case .overlay:
            heart
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(model.favorited ? palette.accent.step(9) : Color.white)
                .frame(width: PulsoControlSize.small.height, height: PulsoControlSize.small.height)
                .background(.black.opacity(0.36), in: palette.controlShape)
        case .tile:
            VStack(spacing: PulsoSpace.s1) {
                heart
                    .font(.body.weight(.semibold))
                    .foregroundStyle(palette.accent.step(9))
                    .frame(width: 48, height: 48)
                    .background(palette.accent.step(3), in: palette.innerShape)
                Text("venue_detail_action_favorite").font(.caption2).foregroundStyle(palette.secondaryText)
            }
        }
    }
}
