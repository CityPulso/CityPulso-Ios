import PulsoLinkCore

/** 从向导草稿发起一场乒乓球活动，带乒乓球自己的选项（Android `toTableTennisRequest`）。 */
extension TableTennisService: SportCreateService {
    func createEvent(_ draft: CreateDraft, buildingId: String?, latitude: Double, longitude: Double) async throws -> String {
        let options = draft.tableTennisOptions
        let place = draft.place(buildingId: buildingId)
        let request = CreateTableTennisEventRequest(
            title: draft.trimmedTitle,
            description: draft.trimmedDescription,
            buildingId: buildingId,
            venueName: place.venueName,
            address: place.address,
            startsAt: draft.startsAt,
            endsAt: draft.endsAt,
            longitude: buildingId == nil ? longitude : nil,
            latitude: buildingId == nil ? latitude : nil,
            tableCount: options.tables,
            playersPerTable: options.playersAtTable,
            capacity: draft.capacityValue,
            waitlistCapacity: draft.waitlistValue,
            isFree: draft.isFree,
            priceAmount: draft.priceValue,
            paymentMethods: draft.isFree ? nil : draft.paymentMethods.map {
                TableTennisPaymentMethod(method: .fromWire($0.method.wire), account: $0.account.trimmingCharacters(in: .whitespacesAndNewlines))
            },
            payeePaymentAccountId: draft.payeeValue,
            equipment: draft.equipment.map { TableTennisEquipment(icon: $0.icon, name: $0.name) },
            matchFormat: options.matchFormat,
            eligibilityDivision: options.eligibilityDivision,
            allowsFreeExit: draft.allowsFreeExit,
            freeExitHoursBeforeStart: draft.freeExitHoursValue,
            images: draft.imageInputs.map { TableTennisEventImageInput(imageId: $0.imageId, sortOrder: $0.sortOrder) }
        )
        return try await create(request).eventId
    }
}
