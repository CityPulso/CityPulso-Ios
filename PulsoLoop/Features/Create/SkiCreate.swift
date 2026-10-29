import PulsoLinkCore

/** 从向导草稿发起一场滑雪活动，带滑雪自己的选项（Android `toSkiRequest`）。 */
extension SkiService: SportCreateService {
    func createEvent(_ draft: CreateDraft, buildingId: String?, latitude: Double, longitude: Double) async throws -> String {
        let options = draft.skiOptions
        let place = draft.place(buildingId: buildingId)
        let request = CreateSkiEventRequest(
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
                SkiPaymentMethod(method: .fromWire($0.method.wire), account: $0.account.trimmingCharacters(in: .whitespacesAndNewlines))
            },
            payeePaymentAccountId: draft.payeeValue,
            equipment: draft.equipment.map { SkiEquipment(icon: $0.icon, name: $0.name) },
            skiDiscipline: options.skiDiscipline,
            skiSkillLevel: options.skiSkillLevel,
            includesLiftTicket: options.includesLiftTicket,
            allowsFreeExit: draft.allowsFreeExit,
            freeExitHoursBeforeStart: draft.freeExitHoursValue,
            images: draft.imageInputs.map { SkiEventImageInput(imageId: $0.imageId, sortOrder: $0.sortOrder) }
        )
        return try await create(request).eventId
    }
}
