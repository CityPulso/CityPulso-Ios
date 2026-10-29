import PulsoLinkCore
import PulsoLinkUI
import SwiftUI

/* ------------------------------ 1. 活动信息 ------------------------------ */

/** 第 1 步：标题、运动（在这里换，或回到完整列表）、介绍、封面和照片。 */
struct CreateStepBasics: View {
    let model: CreateEventModel

    var body: some View {
        if let sport = model.draft.sport {
            Section {
                WizardField(label: "create_title_label", required: true) {
                    TextField("create_flow_title_placeholder", text: binding(\.title))
                }
                WizardField(label: "create_sport_label", required: true) {
                    CreateSportTiles(
                        selected: sport,
                        enabled: !model.isSubmitting,
                        onSelect: { model.selectSport($0, defaultEquipment: defaultEquipmentDrafts($0)) },
                        onMore: { model.backToSportPick() }
                    )
                }
                WizardField(label: "create_description_label", optional: true) {
                    TextField("create_flow_description_placeholder", text: binding(\.description), axis: .vertical).lineLimit(4 ... 10)
                }
            }
            Section {
                WizardField(label: "create_photo_section", required: true) {
                    EventPhotoPicker(
                        photos: model.draft.photos,
                        localData: model.photoData,
                        imageURL: { model.imageURL($0) },
                        onAdd: { model.addPhotos($0) },
                        onRemove: { model.removePhoto($0) },
                        onSetCover: { model.setCover($0) },
                        onRetry: { model.retryPhoto($0) },
                        enabled: !model.isSubmitting
                    )
                }
            }
        }
    }

    private func binding(_ path: WritableKeyPath<CreateDraft, String>) -> Binding<String> {
        Binding(get: { model.draft[keyPath: path] }, set: { value in model.update { $0[keyPath: path] = value } })
    }
}

/* ------------------------------ 2. 时间地点 ------------------------------ */

/** 第 2 步：地点（在地图上选，带附近场馆建筑），然后开始时间、时长、结束时间。 */
struct CreateStepWhenWhere: View {
    let model: CreateEventModel
    let onPickLocation: () -> Void

    private var draft: CreateDraft { model.draft }
    private var sport: LoopSport { draft.sport ?? .badminton }

    var body: some View {
        Section {
            WizardField(label: "create_section_location", required: true, systemImage: "mappin.and.ellipse") {
                VStack(alignment: .leading, spacing: 12) {
                    Button(action: onPickLocation) { locationRow }.buttonStyle(.plain)
                    if draft.hasLocation {
                        TextField("create_flow_venue_placeholder", text: venueBinding)
                            .disabled(draft.buildingId != nil)
                            .textFieldStyle(.roundedBorder)
                        if draft.buildingId == nil {
                            TextField("create_address_label", text: Binding(get: { draft.address }, set: { value in model.update { $0.address = value } }), axis: .vertical)
                                .lineLimit(2 ... 4)
                                .textFieldStyle(.roundedBorder)
                        }
                    }
                }
            }
            if draft.hasLocation { buildingSuggest }
        }
        Section {
            WizardField(
                label: "create_starts_at_label",
                required: true,
                hint: Text(verbatim: localizedFormat("create_flow_timezone", TimeZone.current.identifier)),
                systemImage: "calendar"
            ) {
                DatePicker(selection: startBinding, in: Date.now..., displayedComponents: [.date, .hourAndMinute]) { EmptyView() }
                    .labelsHidden()
            }
            durationChips
            WizardField(label: "create_ends_at_label", hint: Text("create_ends_at_hint"), systemImage: "clock") {
                DatePicker(selection: endBinding, in: (DateTimeFormatters.parseInstant(draft.startsAt) ?? .now)..., displayedComponents: [.date, .hourAndMinute]) { EmptyView() }
                    .labelsHidden()
            }
        }
    }

    /** 选好的地点一行（名称在上、地址在下），没选时是「选择地点」；点开地图。 */
    private var locationRow: some View {
        HStack(spacing: 12) {
            Image(systemName: "location.fill").foregroundStyle(Color.accentColor)
            VStack(alignment: .leading, spacing: 2) {
                if draft.hasLocation {
                    Text(verbatim: draft.venueName.isEmpty ? String(localized: "create_flow_location_selected") : draft.venueName)
                        .font(.body.weight(.medium))
                        .lineLimit(1)
                    Text(verbatim: draft.address.isEmpty ? "\(draft.latitude), \(draft.longitude)" : draft.address)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                } else {
                    Text("create_flow_pick_location").font(.body.weight(.medium))
                    Text("create_flow_location_help").font(.caption).foregroundStyle(.secondary)
                }
            }
            Spacer(minLength: 0)
            Image(systemName: "chevron.right").font(.footnote).foregroundStyle(.tertiary)
        }
        .padding(12)
        .background(.background.secondary, in: .rect(cornerRadius: 12))
        .contentShape(.rect)
    }

    /** 选点后找到的附近建筑：关联一个，或取消自动关联的那个。 */
    @ViewBuilder
    private var buildingSuggest: some View {
        let selected = model.nearbyBuildings.first { $0.id == draft.buildingId }
        if selected != nil || !model.nearbyBuildings.isEmpty {
            WizardField(label: "create_building_link_title", hint: Text(verbatim: localizedFormat("create_building_link_hint", "100"))) {
                VStack(alignment: .leading, spacing: 8) {
                    if let selected {
                        buildingRow(selected, action: "create_building_unlink") { model.unlinkBuilding() }
                    } else {
                        ForEach(model.nearbyBuildings, id: \.id) { building in
                            buildingRow(building, action: "create_building_link") { model.link(building) }
                        }
                    }
                }
            }
        }
    }

    private func buildingRow(_ building: BuildingItem, action: LocalizedStringKey, onAction: @escaping () -> Void) -> some View {
        HStack(spacing: 12) {
            Image(systemName: "building.2").foregroundStyle(.secondary)
            VStack(alignment: .leading, spacing: 2) {
                Text(verbatim: building.name).font(.subheadline.weight(.medium))
                if !building.address.isEmpty { Text(verbatim: building.address).font(.caption).foregroundStyle(.secondary) }
            }
            Spacer(minLength: 0)
            Button(action, action: onAction).buttonStyle(.bordered).controlSize(.small)
        }
    }

    private var durationChips: some View {
        let start = DateTimeFormatters.parseInstant(draft.startsAt)
        let end = DateTimeFormatters.parseInstant(draft.endsAt)
        let selected = start.flatMap { start in end.flatMap { matchingDurationMinutes(start: start, end: $0, sport: sport) } }
        return WizardField(label: "create_flow_duration_label", systemImage: "clock") {
            PulsoFlowLayout(spacing: 8) {
                ForEach(sport.durationPresetsMinutes, id: \.self) { preset in
                    Button {
                        if let start { model.update { $0.endsAt = isoInstant(endsAt(after: start, minutes: preset)) } }
                    } label: {
                        Text(verbatim: localizedFormat("create_flow_duration_hours", durationHoursText(preset)))
                            .font(.subheadline.weight(.medium))
                            .padding(.horizontal, 12)
                            .padding(.vertical, 6)
                            .foregroundStyle(selected == preset ? Color.white : Color.primary)
                            .background(selected == preset ? AnyShapeStyle(Color.accentColor) : AnyShapeStyle(.fill.tertiary), in: .capsule)
                    }
                    .buttonStyle(.plain)
                    .disabled(start == nil)
                }
            }
        }
    }

    private var venueBinding: Binding<String> {
        Binding(get: { draft.venueName }, set: { value in
            model.update {
                $0.venueName = value
                $0.buildingId = nil
            }
        })
    }

    /** 开始时间：没选过时默认一小时后的整点。改开始时间时结束时间跟着走（Android `endsAtAfterStartChange`）。 */
    private var startBinding: Binding<Date> {
        Binding(get: {
            DateTimeFormatters.parseInstant(draft.startsAt) ?? Calendar.current.nextDate(after: .now.addingTimeInterval(3600), matching: DateComponents(minute: 0), matchingPolicy: .nextTime) ?? .now
        }, set: { start in
            model.update {
                $0.endsAt = isoInstant(endsAtAfterStartChange(previousStart: $0.startsAt, previousEnd: $0.endsAt, nextStart: start, sport: sport))
                $0.startsAt = isoInstant(start)
            }
        })
    }

    private var endBinding: Binding<Date> {
        Binding(get: {
            DateTimeFormatters.parseInstant(draft.endsAt) ?? DateTimeFormatters.parseInstant(draft.startsAt) ?? .now
        }, set: { end in
            model.update { $0.endsAt = isoInstant(end) }
        })
    }
}

/* ------------------------------ 3. 活动设置 ------------------------------ */

/** 第 3 步：这项运动自己的名额和选项，然后免费 / 收费（价格、收款方式），最后退出规则。 */
struct CreateStepSettings: View {
    let model: CreateEventModel

    private var draft: CreateDraft { model.draft }
    private static let offlineKinds: [CreatePaymentMethodKind] = [.etransfer, .wechat, .cash]

    var body: some View {
        if let sport = draft.sport {
            SportSettingsDetails(model: model, sport: sport)
        }
        Section {
            Picker(selection: Binding(get: { draft.isFree }, set: { value in model.update { $0.isFree = value } })) {
                Text("create_free").tag(true)
                Text("create_paid").tag(false)
            } label: {
                Label("create_flow_cost", systemImage: "wallet.bifold")
            }
            .pickerStyle(.segmented)
            Text((draft.isFree ? "create_pricing_free_body" : "create_pricing_paid_body") as LocalizedStringKey)
                .font(.footnote)
                .foregroundStyle(.secondary)
            if !draft.isFree {
                WizardField(label: "create_price_amount_label", required: true) {
                    TextField("create_pricing_price_placeholder", text: Binding(get: { draft.priceAmount }, set: { value in model.update { $0.priceAmount = value } }))
                        .keyboardType(.decimalPad)
                }
                Label("create_pricing_price_warning", systemImage: "info.circle").font(.footnote).foregroundStyle(.secondary)
            }
        } header: {
            Text("create_flow_cost")
        }
        if !draft.isFree {
            Section {
                paymentGroup(title: "create_payment_online_title", hint: "create_payment_online_hint", isOn: draft.acceptsStripe) { on in
                    toggle(.stripe, on)
                } content: {
                    PaymentAccountPicker(selectedId: Binding(get: { draft.payeePaymentAccountId }, set: { value in model.update { $0.payeePaymentAccountId = value } }))
                }
                paymentGroup(title: "create_payment_offline_title", hint: "create_payment_offline_hint", isOn: offlineOn) { on in
                    model.update { draft in
                        if on {
                            draft.paymentMethods.append(CreatePaymentMethodDraft(method: .etransfer))
                        } else {
                            draft.paymentMethods.removeAll { Self.offlineKinds.contains($0.method) }
                        }
                    }
                } content: {
                    ForEach(Self.offlineKinds, id: \.self) { kind in
                        offlineMethod(kind)
                    }
                }
            } header: {
                Text("create_payment_title")
            } footer: {
                Text("create_payment_section_hint")
            }
        }
        Section {
            Toggle(isOn: Binding(get: { draft.allowsFreeExit }, set: { value in model.update { $0.allowsFreeExit = value } })) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("create_allows_free_exit_label")
                    Text((draft.allowsFreeExit ? "create_exit_enabled_hint" : "create_exit_disabled_hint") as LocalizedStringKey)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            if draft.allowsFreeExit {
                Picker(selection: Binding(get: { draft.freeExitHours }, set: { value in model.update { $0.freeExitHours = value } })) {
                    ForEach(ExitDeadlineHours.allCases, id: \.self) { option in
                        Text(verbatim: localizedFormat("create_exit_deadline_option", option.hours)).tag(option)
                    }
                } label: {
                    Text("create_exit_deadline_label")
                }
                Text("create_exit_deadline_hint").font(.caption).foregroundStyle(.secondary)
            }
        } header: {
            Label("create_exit_section", systemImage: "rectangle.portrait.and.arrow.right")
        }
    }

    private var offlineOn: Bool { draft.paymentMethods.contains { Self.offlineKinds.contains($0.method) } }

    private func toggle(_ kind: CreatePaymentMethodKind, _ on: Bool) {
        model.update { draft in
            if on {
                if !draft.paymentMethods.contains(where: { $0.method == kind }) { draft.paymentMethods.append(CreatePaymentMethodDraft(method: kind)) }
            } else {
                draft.paymentMethods.removeAll { $0.method == kind }
            }
        }
    }

    private func paymentGroup(
        title: LocalizedStringKey,
        hint: LocalizedStringKey,
        isOn: Bool,
        onToggle: @escaping (Bool) -> Void,
        @ViewBuilder content: () -> some View
    ) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Toggle(isOn: Binding(get: { isOn }, set: onToggle)) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                    Text(hint).font(.caption).foregroundStyle(.secondary)
                }
            }
            if isOn {
                VStack(alignment: .leading, spacing: 8) { content() }.padding(.leading, 8)
            }
        }
    }

    @ViewBuilder
    private func offlineMethod(_ kind: CreatePaymentMethodKind) -> some View {
        let entry = draft.paymentMethods.first { $0.method == kind }
        Toggle(isOn: Binding(get: { entry != nil }, set: { toggle(kind, $0) })) {
            Text(kind.methodLabelKey)
        }
        .toggleStyle(.switch)
        if let entry, kind != .cash {
            TextField(
                (kind == .etransfer ? "create_payment_account_etransfer_placeholder" : "create_payment_account_wechat_placeholder") as LocalizedStringKey,
                text: Binding(get: { entry.account }, set: { value in
                    model.update { draft in
                        if let index = draft.paymentMethods.firstIndex(where: { $0.method == kind }) { draft.paymentMethods[index].account = value }
                    }
                })
            )
            .keyboardType(kind == .etransfer ? .emailAddress : .default)
            .textInputAutocapitalization(.never)
            .textFieldStyle(.roundedBorder)
            .accessibilityLabel(Text((kind == .etransfer ? "create_payment_account_etransfer" : "create_payment_account_wechat") as LocalizedStringKey))
        }
    }
}

extension CreatePaymentMethodKind {
    var methodLabelKey: LocalizedStringKey {
        switch self {
        case .etransfer: "create_payment_method_etransfer"
        case .wechat: "create_payment_method_wechat"
        case .cash: "create_payment_method_cash"
        case .stripe: "create_payment_method_stripe"
        }
    }
}

/* ------------------------------ 4. 预览并发布 ------------------------------ */

/** 第 4 步：球友会看到的样子，每项都能点回对应步骤，还没填好的列在最上面。 */
struct CreateStepPublish: View {
    let model: CreateEventModel

    @Environment(\.locale) private var locale

    private var draft: CreateDraft { model.draft }
    private var sport: LoopSport { draft.sport ?? .badminton }

    var body: some View {
        let time = DateTimeFormatters.sessionDayClockRange(draft.startsAt, draft.endsAt, locale: locale)
        let place = draft.venueName.isEmpty ? draft.address : draft.venueName
        let price = draft.isFree
            ? String(localized: "create_free")
            : localizedFormat("create_detail_price", formatMoney(Double(draft.priceAmount) ?? 0, currency: "CAD", locale: locale))
        let problems = CreateWizardStep.allCases.compactMap { step in draft.validationError(step).map { (step, $0) } }

        if !problems.isEmpty {
            Section("create_publish_checks_title") {
                ForEach(problems.indices, id: \.self) { index in
                    let step = problems[index].0
                    let error = problems[index].1
                    Button { model.goToStep(step) } label: {
                        HStack(spacing: 12) {
                            Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.red)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(step.labelKey).font(.subheadline.weight(.medium)).foregroundStyle(.primary)
                                Text(verbatim: error.text).font(.caption).foregroundStyle(.red)
                            }
                            Spacer(minLength: 0)
                            Image(systemName: "chevron.right").font(.footnote).foregroundStyle(.tertiary)
                        }
                    }
                }
            }
        }
        Section("create_publish_preview_title") {
            VStack(alignment: .leading, spacing: 0) {
                SportCover(url: cover, sport: sport, iconSize: 56)
                    .frame(height: 168)
                    .clipped()
                    .overlay(alignment: .topTrailing) {
                        Button { model.goToStep(.basics) } label: { Label("create_publish_edit", systemImage: "pencil") }
                            .buttonStyle(.bordered)
                            .controlSize(.small)
                            .padding(8)
                    }
                VStack(alignment: .leading, spacing: 8) {
                    EventTag(Text(sport.labelKey), accent: true)
                    Text(verbatim: draft.title).font(.headline)
                    if !time.isEmpty { previewLine("calendar", time) }
                    if !place.isEmpty { previewLine("mappin.and.ellipse", place, secondary: draft.venueName.isEmpty || draft.address.isEmpty ? nil : draft.address) }
                    previewLine("person.3", localizedFormat("create_detail_people", draft.capacity))
                    previewLine("wallet.bifold", price)
                    if !draft.description.isEmpty {
                        Text(verbatim: draft.description).font(.footnote).foregroundStyle(.secondary).lineLimit(4)
                    }
                }
                .padding()
            }
            .listRowInsets(EdgeInsets())
        }
        Section("create_publish_details_title") {
            row("square.grid.2x2", "create_sport_label", Text(sport.labelKey), step: .basics)
            row("calendar", "create_starts_at_label", Text(verbatim: time), step: .whenWhere)
            row("mappin.and.ellipse", "create_section_location", Text(verbatim: place), step: .whenWhere)
            row("person.3", "create_capacity_label", Text(verbatim: localizedFormat("create_detail_people", draft.capacity)), step: .settings)
            row("hourglass", "create_waitlist_capacity_label", Text(verbatim: localizedFormat("create_detail_people", draft.waitlistCapacity)), step: .settings)
            row("wallet.bifold", "create_flow_cost", Text(verbatim: price), step: .settings)
            row(
                "rectangle.portrait.and.arrow.right",
                "create_allows_free_exit_label",
                draft.allowsFreeExit ? Text(verbatim: localizedFormat("create_exit_deadline_option", draft.freeExitHours.hours)) : Text("create_detail_exit_off"),
                step: .settings
            )
        }
    }

    private var cover: URL? { model.imageURL(draft.photos.first?.imageId) }

    private func previewLine(_ systemImage: String, _ text: String, secondary: String? = nil) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: systemImage).foregroundStyle(.secondary).frame(width: 20)
            VStack(alignment: .leading, spacing: 2) {
                Text(verbatim: text).font(.subheadline)
                if let secondary { Text(verbatim: secondary).font(.caption).foregroundStyle(.secondary) }
            }
        }
    }

    private func row(_ systemImage: String, _ label: LocalizedStringKey, _ value: Text, step: CreateWizardStep) -> some View {
        Button { model.goToStep(step) } label: {
            LabeledContent {
                value.multilineTextAlignment(.trailing)
            } label: {
                Label(label, systemImage: systemImage)
            }
        }
        .foregroundStyle(.primary)
    }
}
