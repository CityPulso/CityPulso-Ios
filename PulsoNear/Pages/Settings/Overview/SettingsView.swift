import Factory
import PulsoLinkCore
import PulsoLinkUI
import SwiftUI
import UIKit

/** 设置首页（对应 Android `SettingsScreen`）：分组区块，每一行推进对应页面；收藏联动是开关；最后退出登录。 */
struct SettingsView: View {
    @Environment(PulsoSessionModel.self) private var session
    @Environment(\.pulsoPalette) private var palette
    @State private var favorite = Container.shared.preferenceService().preference.value.favorite
    @State private var confirmLogout = false

    var body: some View {
        ScrollView {
            VStack(spacing: PulsoSpace.s4) {
                PulsoSection("settings_section_appearance") {
                    row("settings_theme", "paintpalette", .theme)
                    row("app_icon_title", "app.badge", .appIcon)
                    Button {
                        UIApplication.shared.open(URL(string: UIApplication.openSettingsURLString)!)
                    } label: {
                        PulsoSectionRow(
                            "settings_language_text",
                            systemImage: "character.bubble",
                            value: AppLanguageSync.appLanguage.nativeName,
                            showChevron: false
                        ) {
                            Image(systemName: "arrow.up.forward.app").foregroundStyle(palette.secondaryText)
                        }
                    }
                    .buttonStyle(.pulsoRow)
                    row("settings_nav_edit", "dock.rectangle", .navEdit)
                }

                PulsoSection("settings_section_account") {
                    row("profile_edit_title", "pencil", .profileEdit)
                    row("profile_identities_title", "person.text.rectangle", .identities)
                    row("account_security_title", "lock.shield", .accountSecurity)
                }

                PulsoSection("settings_section_privacy") {
                    row("shell_privacy_title", "hand.raised", .privacy)
                    row("settings_permissions_title", "checkmark.shield", .permissions)
                }

                PulsoSection("settings_section_preferences") {
                    row("settings_map_defaults", "map", .mapSettings)
                    row("settings_activity_preferences", "calendar", .activityPreferences)
                    row("settings_storage", "internaldrive", .storage)
                }

                if session.session.currentProfileKind == .community {
                    PulsoSection("settings_favorites") {
                        toggle("favorites_auto_on_venue_action", \.autoOnVenueAction)
                        toggle("favorites_with_venue_when_building", \.withVenueWhenBuilding)
                        toggle("favorites_with_building_when_venue", \.withBuildingWhenVenue)
                        toggle("favorites_without_venue_when_building", \.withoutVenueWhenBuilding)
                        toggle("favorites_without_building_when_venue", \.withoutBuildingWhenVenue)
                    }
                }

                PulsoSection("settings_section_activity") {
                    Button {
                        confirmLogout = true
                    } label: {
                        PulsoSectionRow("settings_logout", systemImage: "rectangle.portrait.and.arrow.right", tint: palette.error, showChevron: false)
                    }
                    .buttonStyle(.pulsoRow)
                }
            }
            .padding(PulsoSpace.s4)
        }
        .navigationTitle("settings_title")
        .alert("settings_logout_confirm_title", isPresented: $confirmLogout) {
            Button("settings_logout", role: .destructive) {
                Task { await session.signOut() }
            }
            Button("profile_dialog_cancel", role: .cancel) {}
        } message: {
            Text("settings_logout_confirm_body")
        }
    }

    private func row(_ title: LocalizedStringKey, _ systemImage: String, _ route: NearRoute) -> some View {
        NavigationLink(value: route) {
            PulsoSectionRow(title, systemImage: systemImage)
        }
        .buttonStyle(.pulsoRow)
    }

    /** 收藏联动开关：标题可换行，开关用强调色。 */
    private func toggle(_ title: LocalizedStringKey, _ keyPath: WritableKeyPath<ResolvedFavoritePreference, Bool>) -> some View {
        Toggle(isOn: favoriteBinding(keyPath)) {
            Text(title).font(.body).foregroundStyle(palette.text)
        }
        .tint(palette.accent.step(9))
        .padding(PulsoSpace.s4)
    }

    private func favoriteBinding(_ keyPath: WritableKeyPath<ResolvedFavoritePreference, Bool>) -> Binding<Bool> {
        Binding(
            get: { favorite[keyPath: keyPath] },
            set: { value in
                favorite[keyPath: keyPath] = value
                let next = favorite
                Container.shared.preferenceService().update { $0.favorite = next }
                PreferenceSync.pushSoon()
            }
        )
    }
}
