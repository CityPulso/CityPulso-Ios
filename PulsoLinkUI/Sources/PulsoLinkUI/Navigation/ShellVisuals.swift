import PulsoLinkCore
import SwiftUI

/* 底栏图标与文案：图标是 SF Symbols（Tab 选中时系统自动换成 .fill），文案 key 在各 App 的 Localizable.xcstrings。 */

extension ShellNavIconPack {
    public var systemImage: String {
        switch self {
        case .home: "house"
        case .map: "map"
        case .calendar: "calendar"
        case .explore: "location.magnifyingglass"
        case .search: "magnifyingglass"
        case .social: "person.2"
        case .create: "plus"
        case .settings: "gearshape"
        case .billing: "list.bullet.rectangle.portrait"
        case .notifications: "bell"
        case .chat: "bubble.left.and.bubble.right"
        case .profile: "person"
        case .event: "ticket"
        case .place: "building.2"
        case .sports: "tennis.racket"
        case .wallet: "wallet.bifold"
        case .school: "graduationcap"
        case .book: "book"
        case .trophy: "trophy"
        case .booking: "calendar.badge.checkmark"
        case .favorite: "heart"
        case .forum: "text.bubble"
        }
    }
}

extension ShellNavIconPack {
    /** 图标组名（导航栏编辑里选图标组用；Android `ShellVisuals` 的 labelRes）。 */
    public var labelKey: LocalizedStringKey {
        switch self {
        case .home: "shell_icon_home"
        case .map: "shell_dest_map"
        case .calendar: "shell_dest_calendar"
        case .explore: "shell_dest_explore"
        case .search: "shell_dest_search"
        case .social: "shell_dest_social"
        case .create: "shell_dest_create"
        case .settings: "shell_dest_settings"
        case .billing: "shell_dest_billing"
        case .notifications: "shell_dest_notifications"
        case .chat: "shell_dest_chat_hub"
        case .profile: "shell_dest_profile"
        case .event: "shell_icon_event"
        case .place: "shell_icon_place"
        case .sports: "shell_icon_sports"
        case .wallet: "shell_dest_wallet"
        case .school: "shell_icon_school"
        case .book: "shell_icon_book"
        case .trophy: "shell_icon_trophy"
        case .booking: "shell_icon_booking"
        case .favorite: "shell_icon_favorite"
        case .forum: "shell_icon_forum"
        }
    }
}

extension ShellDestination {
    /** 页面名（Android `ShellVisuals` 的 labelRes）。 */
    public var labelKey: LocalizedStringKey {
        switch self {
        case .explore: "shell_dest_explore"
        case .calendar: "shell_dest_calendar"
        case .search: "shell_dest_search"
        case .venueSearch: "shell_dest_venue_search"
        case .create: "shell_dest_create"
        case .settings: "shell_dest_settings"
        case .billing: "shell_dest_billing"
        case .chatHub: "shell_dest_chat_hub"
        case .profile: "shell_dest_profile"
        case .wallet: "shell_dest_wallet"
        case .courses: "shell_dest_courses"
        case .tournaments: "shell_dest_tournaments"
        case .favorites: "shell_dest_favorites"
        case .forum: "shell_dest_forum"
        case .placeRequests: "place_requests_title"
        }
    }
}
