import PulsoLinkCore

/** 从向导草稿发起一场足球活动，带足球自己的选项（Android `toFootballRequest`）。 */
extension FootballService: SportCreateService {
    func createEvent(_ draft: CreateDraft, buildingId: String?, latitude: Double, longitude: Double) async throws -> String {
        let options = draft.footballOptions
        let place = draft.place(buildingId: buildingId)
        let request = CreateFootballEventRequest(
            title: draft.trimmedTitle,
            description: draft.trimmedDescription,
            buildingId: buildingId,
            venueName: place.venueName,
            address: place.address,
            startsAt: draft.startsAt,
            endsAt: draft.endsAt,
            longitude: buildingId == nil ? longitude : nil,
            latitude: buildingId == nil ? latitude : nil,
            capacity: draft.capacityValue,
            waitlistCapacity: draft.waitlistValue,
            isFree: draft.isFree,
            priceAmount: draft.priceValue,
            paymentMethods: draft.isFree ? nil : draft.paymentMethods.map {
                FootballPaymentMethod(method: .fromWire($0.method.wire), account: $0.account.trimmingCharacters(in: .whitespacesAndNewlines))
            },
            payeePaymentAccountId: draft.payeeValue,
            equipment: draft.equipment.map { FootballEquipment(icon: $0.icon, name: $0.name) },
            footballFormat: options.footballFormat,
            pitchSurface: options.pitchSurface,
            eligibilityDivision: options.eligibilityDivision,
            allowsFreeExit: draft.allowsFreeExit,
            freeExitHoursBeforeStart: draft.freeExitHoursValue,
            images: draft.imageInputs.map { FootballEventImageInput(imageId: $0.imageId, sortOrder: $0.sortOrder) }
        )
        return try await create(request).eventId
    }
}
