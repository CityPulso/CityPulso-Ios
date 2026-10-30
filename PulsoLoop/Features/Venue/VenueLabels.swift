import SwiftUI

/* 球馆闭集 → 文案（Android `features/venue/VenueLabels.kt`，文案来自 WEB `features.venue`）。 */

extension CourtBookingStatus {
    var labelKey: LocalizedStringKey {
        switch self {
        case .pending: "venue_booking_status_pending"
        case .awaitingApproval: "venue_booking_status_awaiting_approval"
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

extension CourtBookingPaymentMethod {
    var titleKey: LocalizedStringKey {
        switch self {
        case .phone: "venue_payments_modes_phone_title"
        case .offline: "venue_payments_modes_offline_title"
        case .platform: "venue_payments_modes_platform_title"
        case .bundle: "venue_payments_modes_bundle_title"
        }
    }

    var bookerBodyKey: LocalizedStringKey {
        switch self {
        case .phone: "venue_payments_modes_phone_booker_body"
        case .offline: "venue_payments_modes_offline_booker_body"
        case .platform: "venue_payments_modes_platform_booker_body"
        case .bundle: "venue_payments_modes_bundle_booker_body"
        }
    }
}

extension CourtSurface {
    var labelKey: LocalizedStringKey {
        switch self {
        case .syntheticMat: "venue_surface_synthetic_mat"
        case .wood: "venue_surface_wood"
        case .pvc: "venue_surface_pvc"
        case .concrete: "venue_surface_concrete"
        case .other: "venue_surface_other"
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
