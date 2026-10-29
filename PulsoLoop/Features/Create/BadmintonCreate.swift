import PulsoLinkCore

/** 从向导草稿发起一场羽毛球活动（Android `toBadmintonRequest`）。 */
extension BadmintonService: SportCreateService {
    func createEvent(_ draft: CreateDraft, buildingId: String?, latitude: Double, longitude: Double) async throws -> String {
        let place = draft.place(buildingId: buildingId)
        let request = CreateBadmintonEventRequest(
            title: draft.trimmedTitle,
            description: draft.trimmedDescription,
            buildingId: buildingId,
            venueName: place.venueName,
            address: place.address,
            startsAt: draft.startsAt,
            endsAt: draft.endsAt,
            longitude: buildingId == nil ? longitude : nil,
            latitude: buildingId == nil ? latitude : nil,
            courtCount: Int(draft.courtCount) ?? 1,
            playersPerCourt: Int(draft.playersPerCourt) ?? 4,
            capacity: draft.capacityValue,
            waitlistCapacity: draft.waitlistValue,
            isFree: draft.isFree,
            priceAmount: draft.priceValue,
            paymentMethods: draft.isFree ? nil : draft.paymentMethods.map {
                BadmintonPaymentMethod(method: .fromWire($0.method.wire), account: $0.account.trimmingCharacters(in: .whitespacesAndNewlines))
            },
            payeePaymentAccountId: draft.payeeValue,
            equipment: draft.equipment.map { BadmintonEquipment(icon: $0.icon, name: $0.name) },
            eligibilityDivision: draft.eligibilityDivision,
            matchFormat: draft.matchFormat,
            allowsFreeExit: draft.allowsFreeExit,
            freeExitHoursBeforeStart: draft.freeExitHoursValue,
            images: draft.imageInputs.map { BadmintonEventImageInput(imageId: $0.imageId, sortOrder: $0.sortOrder) }
        )
        return try await create(request).eventId
    }
}
