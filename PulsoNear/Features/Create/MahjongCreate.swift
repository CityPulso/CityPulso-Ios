import PulsoLinkCore

/* 麻将的请求多一个规则（`mahjongVariant`），手写，不从桌游分叉。 */

/** 从向导草稿发起一场麻将活动（Android `toMahjongRequest`）。 */
extension MahjongService: ActivityTypeCreateService {
    func createActivity(_ draft: CreateDraft, buildingId: String?, latitude: Double, longitude: Double) async throws -> String {
        let place = draft.place(buildingId: buildingId)
        let request = CreateMahjongActivityRequest(
            title: draft.trimmedTitle,
            mahjongVariant: draft.mahjongVariant.trimmingCharacters(in: .whitespacesAndNewlines),
            description: draft.trimmedDescription,
            buildingId: buildingId,
            venueName: place.venueName,
            address: place.address,
            startsAt: draft.startsAt,
            endsAt: draft.endsAt,
            longitude: buildingId == nil ? longitude : nil,
            latitude: buildingId == nil ? latitude : nil,
            minParticipants: draft.minParticipantsValue,
            capacity: draft.capacityValue,
            waitlistCapacity: draft.waitlistValue,
            isFree: draft.isFree,
            priceAmount: draft.priceValue,
            paymentMethods: draft.isFree ? nil : draft.paymentMethods.map {
                MahjongPaymentMethod(method: .fromWire($0.method.wire), account: $0.account.trimmingCharacters(in: .whitespacesAndNewlines))
            },
            payeePaymentAccountId: draft.payeeValue,
            allowsFreeExit: draft.allowsFreeExit,
            freeExitHoursBeforeStart: draft.freeExitHoursValue,
            images: draft.imageInputs.map { MahjongActivityImageInput(imageId: $0.imageId, sortOrder: $0.sortOrder) }
        )
        return try await create(request).activityId
    }
}
