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

/** 球馆 / 建筑上的收藏心形（Android `FavoriteHeartAction`）；没登录时不显示。[overlay] 画在封面照片上。 */
struct FavoriteHeart: View {
    let name: String
    var overlay = false
    @State private var model: FavoriteHeartModel

    init(target: FavoriteTarget, id: String, name: String, overlay: Bool = false) {
        self.name = name
        self.overlay = overlay
        _model = State(initialValue: FavoriteHeartModel(target: target, id: id))
    }

    var body: some View {
        Group {
            if model.visible {
                Button {
                    Task { await model.toggle() }
                } label: {
                    Image(systemName: model.favorited ? "heart.fill" : "heart")
                        .pulsoToggleBurst(active: model.favorited, color: .accentColor)
                        .foregroundStyle(model.favorited ? Color.accentColor : (overlay ? Color.white : Color.primary))
                        .frame(width: 36, height: 36)
                }
                .buttonStyle(.plain)
                .modifier(OverlayGlass(enabled: overlay))
                .disabled(model.pending)
                .accessibilityLabel(Text(verbatim: localizedFormat(model.favorited ? "favorites_remove_named" : "favorites_add_named", name)))
            }
        }
        .task { await model.observe() }
    }
}

private struct OverlayGlass: ViewModifier {
    let enabled: Bool

    func body(content: Content) -> some View {
        if enabled {
            content.glassEffect(.regular.interactive(), in: .circle)
        } else {
            content
        }
    }
}
