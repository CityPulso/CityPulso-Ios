import SwiftUI

/* 门店闭集 → 文案（Android `features/venue/VenueLabels.kt`，文案来自 WEB `features.venue`）。 */

extension SpaceBookingStatus {
    var labelKey: LocalizedStringKey {
        switch self {
        case .pending: "venue_booking_status_pending"
        case .awaitingPayment: "venue_booking_status_awaiting_payment"
        case .confirmed: "venue_booking_status_confirmed"
        case .canceled: "venue_booking_status_canceled"
        case .expired: "venue_booking_status_expired"
        }
    }
}

extension PublicationStatus {
    var labelKey: LocalizedStringKey {
        switch self {
        case .draft: "venue_venue_status_draft"
        case .published: "venue_venue_status_published"
        case .suspended: "venue_venue_status_suspended"
        }
    }
}

extension SpaceBookingPaymentMethod {
    var titleKey: LocalizedStringKey {
        switch self {
        case .phone: "venue_payments_modes_phone_title"
        case .offline: "venue_payments_modes_offline_title"
        case .platform: "venue_payments_modes_platform_title"
        }
    }

    var bookerBodyKey: LocalizedStringKey {
        switch self {
        case .phone: "venue_payments_modes_phone_booker_body"
        case .offline: "venue_payments_modes_offline_booker_body"
        case .platform: "venue_payments_modes_platform_booker_body"
        }
    }
}

extension BoardGameTitleDifficulty {
    var labelKey: LocalizedStringKey {
        switch self {
        case .easy: "venue_board_game_title_difficulty_easy"
        case .normal: "venue_board_game_title_difficulty_normal"
        case .hard: "venue_board_game_title_difficulty_hard"
        case .expert: "venue_board_game_title_difficulty_expert"
        }
    }
}

extension KtvRoomSize {
    var labelResource: String.LocalizationValue {
        switch self {
        case .small: "venue_ktv_room_size_small"
        case .medium: "venue_ktv_room_size_medium"
        case .large: "venue_ktv_room_size_large"
        }
    }
}

extension BilliardsTableType {
    var labelResource: String.LocalizationValue {
        switch self {
        case .chineseEightBall: "venue_billiards_table_type_chinese_eight_ball"
        case .pool: "venue_billiards_table_type_pool"
        case .snooker: "venue_billiards_table_type_snooker"
        }
    }
}

extension SpaceKind {
    /** 桌台 / 包间 / 机位。 */
    var labelResource: String.LocalizationValue {
        switch self {
        case .table: "venue_space_kind_table"
        case .room: "venue_space_kind_room"
        case .seat: "venue_space_kind_seat"
        }
    }
}

extension OfferingType {
    var labelKey: LocalizedStringKey {
        switch self {
        case .product: "venue_offering_type_product"
        case .service: "venue_offering_type_service"
        }
    }
}

extension OfferingAvailability {
    var labelKey: LocalizedStringKey {
        switch self {
        case .available: "venue_availability_available"
        case .limited: "venue_availability_limited"
        case .outOfStock: "venue_availability_out_of_stock"
        case .onRequest: "venue_availability_on_request"
        }
    }
}

extension SessionDifficulty {
    var labelKey: LocalizedStringKey {
        switch self {
        case .easy: "venue_session_difficulty_easy"
        case .normal: "venue_session_difficulty_normal"
        case .hard: "venue_session_difficulty_hard"
        case .expert: "venue_session_difficulty_expert"
        }
    }
}
