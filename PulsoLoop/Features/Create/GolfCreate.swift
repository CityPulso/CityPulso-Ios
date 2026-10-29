import PulsoLinkCore

/** 从向导草稿发起一场高尔夫活动，带高尔夫自己的选项（Android `toGolfRequest`）。 */
extension GolfService: SportCreateService {
    func createEvent(_ draft: CreateDraft, buildingId: String?, latitude: Double, longitude: Double) async throws -> String {
        let options = draft.golfOptions
        let place = draft.place(buildingId: buildingId)
        let request = CreateGolfEventRequest(
            title: draft.trimmedTitle,
            description: draft.trimmedDescription,
            buildingId: buildingId,
            venueName: place.venueName,
            address: place.address,
            startsAt: draft.startsAt,
            endsAt: draft.endsAt,
            longitude: buildingId == nil ? longitude : nil,
            latitude: buildingId == nil ? latitude : nil,
            groupCount: options.groups,
            playersPerGroup: options.playersInGroup,
            capacity: draft.capacityValue,
            waitlistCapacity: draft.waitlistValue,
            isFree: draft.isFree,
            priceAmount: draft.priceValue,
            paymentMethods: draft.isFree ? nil : draft.paymentMethods.map {
                GolfPaymentMethod(method: .fromWire($0.method.wire), account: $0.account.trimmingCharacters(in: .whitespacesAndNewlines))
            },
            payeePaymentAccountId: draft.payeeValue,
            equipment: draft.equipment.map { GolfEquipment(icon: $0.icon, name: $0.name) },
            golfHoles: options.golfHoles,
            allowsFreeExit: draft.allowsFreeExit,
            freeExitHoursBeforeStart: draft.freeExitHoursValue,
            images: draft.imageInputs.map { GolfEventImageInput(imageId: $0.imageId, sortOrder: $0.sortOrder) }
        )
        return try await create(request).eventId
    }
}
