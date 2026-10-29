import Foundation
import Testing
@testable import PulsoLinkCore

/** 生成的 DTO 要和 Android `WireJson` 一样读写（Scripts/android_dtos.py）。 */
struct GeneratedDTOTests {
    @Test func missingAndNullFieldsTakeTheKotlinDefault() throws {
        let item = try decodeWire(PaymentAccountItem.self, #"{"id":"pa1","account_id":"a1","label":null,"status":"bogus"}"#)
        #expect(item.label == "")
        #expect(item.chargesEnabled == false)
        #expect(item.status == .fallback)
    }

    @Test func missingRequiredFieldThrows() {
        #expect(throws: DecodingError.self) {
            _ = try decodeWire(PaymentAccountItem.self, #"{"id":"pa1"}"#)
        }
    }

    @Test func alternateNamesDecode() throws {
        let region = try decodeWire(GeoRegionName.self, #"{"Code":"ON","Name":"Ontario"}"#)
        #expect(region.code == "ON")
        #expect(region.name == "Ontario")
    }

    @Test func encodingLeavesOutNilAndDefaults() throws {
        let item = PaymentAccountItem(id: "pa1", accountId: "a1", chargesEnabled: true)
        let json = String(decoding: try WireCoding.encoder.encode(item), as: UTF8.self)
        #expect(json.contains(#""account_id":"a1""#))
        #expect(json.contains(#""charges_enabled":true"#))
        #expect(!json.contains("label"))
        #expect(!json.contains("payouts_enabled"))
        #expect(!json.contains("null"))
    }

    @Test func roundTrip() throws {
        let viewport = GeoViewport(center: GeoPoint(longitude: -79.4, latitude: 43.7), radiusM: 2500)
        let data = try WireCoding.encoder.encode(viewport)
        #expect(String(decoding: data, as: UTF8.self).contains(#""radius_m":2500"#))
        #expect(try WireCoding.decoder.decode(GeoViewport.self, from: data) == viewport)
    }
}
