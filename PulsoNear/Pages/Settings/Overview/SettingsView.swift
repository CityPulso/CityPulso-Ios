import Factory
import PulsoLinkCore
import PulsoLinkUI
import SwiftUI
import UIKit

/** 设置首页（对应 Android `SettingsScreen`）：系统分组列表，每一项推进对应页面。 */
struct SettingsView: View {
    @Environment(PulsoSessionModel.self) private var session
    @State private var favorite = Container.shared.preferenceService().preference.value.favorite
    @State private var confirmLogout = false

    var body: some View {
        Form {
            Section("settings_section_appearance") {
                NavigationLink(value: NearRoute.theme) {
                    Label("settings_theme", systemImage: "paintpalette")
                }
                NavigationLink(value: NearRoute.appIcon) {
                    Label("app_icon_title", systemImage: "app.badge")
                }
                Button {
                    UIApplication.shared.open(URL(string: UIApplication.openSettingsURLString)!)
                } label: {
                    LabeledContent {
                        HStack(spacing: 6) {
                            Text(verbatim: AppLanguageSync.appLanguage.nativeName)
                            Image(systemName: "arrow.up.forward.app")
                        }
                    } label: {
                        Label {
                            Text("pulso_ui_language_title", bundle: .pulsoLinkUI)
                        } icon: {
                            Image(systemName: "character.bubble")
                        }
                    }
                }
                .foregroundStyle(.primary)
                NavigationLink(value: NearRoute.navEdit) {
                    Label("settings_nav_edit", systemImage: "dock.rectangle")
                }
            }

            Section("settings_section_account") {
                NavigationLink(value: NearRoute.comingSoon(title: "profile_edit_title", systemImage: "pencil")) {
                    Label("profile_edit_title", systemImage: "pencil")
                }
                NavigationLink(value: NearRoute.comingSoon(title: "profile_identities_title", systemImage: "person.text.rectangle")) {
                    Label("profile_identities_title", systemImage: "person.text.rectangle")
                }
                NavigationLink(value: NearRoute.accountSecurity) {
                    Label("account_security_title", systemImage: "lock.shield")
                }
                NavigationLink(value: NearRoute.comingSoon(title: "place_requests_title", systemImage: "mappin.and.ellipse")) {
                    Label("place_requests_title", systemImage: "mappin.and.ellipse")
                }
            }

            Section("settings_section_privacy") {
                NavigationLink(value: NearRoute.privacy) {
                    Label("shell_privacy_title", systemImage: "hand.raised")
                }
                NavigationLink(value: NearRoute.permissions) {
                    Label("settings_permissions_title", systemImage: "checkmark.shield")
                }
            }

            Section("settings_section_preferences") {
                NavigationLink(value: NearRoute.comingSoon(title: "settings_map_defaults", systemImage: "map")) {
                    Label("settings_map_defaults", systemImage: "map")
                }
                NavigationLink(value: NearRoute.activityPreferences) {
                    Label("settings_activity_preferences", systemImage: "calendar")
                }
            }

            if session.session.currentProfileKind == .community {
                Section("settings_favorites") {
                    Toggle("favorites_auto_on_venue_action", isOn: favoriteBinding(\.autoOnVenueAction))
                    Toggle("favorites_with_venue_when_building", isOn: favoriteBinding(\.withVenueWhenBuilding))
                    Toggle("favorites_with_building_when_venue", isOn: favoriteBinding(\.withBuildingWhenVenue))
                    Toggle("favorites_without_venue_when_building", isOn: favoriteBinding(\.withoutVenueWhenBuilding))
                    Toggle("favorites_without_building_when_venue", isOn: favoriteBinding(\.withoutBuildingWhenVenue))
                }
            }

            Section("settings_section_activity") {
                Button("settings_logout", systemImage: "rectangle.portrait.and.arrow.right", role: .destructive) {
                    confirmLogout = true
                }
            }
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
