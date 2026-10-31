import PulsoLinkCore
import PulsoLinkUI
import SwiftUI

/**
 * 确认订场（Android `CourtConfirmPage`，所有球场类运动共用）：场馆和运动、预订详情（日期、几段场地、合计）、
 * 联系信息、订场方式（含时长包）、退款政策、到场须知；底部按方式显示「去支付 / 用时长包订场 / 提交订场」。
 */
struct VenueConfirmView: View {
    @State private var model: VenueConfirmModel
    @Environment(\.locale) private var locale
    @Environment(\.dismiss) private var dismiss
    @Environment(PulsoShellNavigator.self) private var shell: PulsoShellNavigator?

    init(venueId: String, sport: VenueSport, dateKey: String, ranges: [VenueConfirmRange]) {
        _model = State(initialValue: VenueConfirmModel(venueId: venueId, sport: sport, dateKey: dateKey, ranges: ranges))
    }

    var body: some View {
        content
            .navigationTitle("venue_confirm_title")
            .navigationBarTitleDisplayMode(.inline)
            .task { await model.observe() }
    }

    @ViewBuilder
    private var content: some View {
        if let venue = model.venue.data {
            Form {
                if model.day.isLoading, model.lines.isEmpty {
                    ProgressView().frame(maxWidth: .infinity)
                } else if let error = model.day.error, model.lines.isEmpty {
                    PulsoLoadErrorView(error) { model.refresh() }
                } else if model.stale {
                    ContentUnavailableView {
                        Label("venue_confirm_stale", systemImage: "calendar.badge.exclamationmark")
                    } actions: {
                        Button("venue_confirm_back") { dismiss() }
                    }
                } else if model.methods.isEmpty {
                    Text("venue_confirm_checkout_no_modes").foregroundStyle(.secondary)
                } else {
                    venueSection(venue)
                    detailsSection(venue)
                    contactSection
                    methodSection
                    if let entry = model.entry.data {
                        Section("venue_confirm_refund_title") {
                            CourtRefundPolicySummary(policy: entry.refundPolicy, tiers: entry.refundTiers, note: entry.refundPolicyNote)
                        }
                    }
                    if let instructions = venue.bookingInstructions, !instructions.trimmingCharacters(in: .whitespaces).isEmpty {
                        Section("venue_confirm_instructions") {
                            Text(verbatim: instructions).font(.subheadline)
                        }
                    }
                }
            }
            .scrollDismissesKeyboard(.interactively)
            .safeAreaInset(edge: .bottom) {
                if !model.stale, !model.methods.isEmpty, !model.lines.isEmpty { submitBar(venue) }
            }
        } else if let error = model.venue.error {
            if error.kind == .notFound {
                ContentUnavailableView {
                    Label("venue_detail_not_found", systemImage: "building.2")
                } description: {
                    Text("venue_detail_not_found_body")
                } actions: {
                    Button("venue_confirm_back") { dismiss() }
                }
            } else {
                PulsoLoadErrorView(error) { model.refresh() }
            }
        } else {
            ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private func venueSection(_ venue: VenueDetail) -> some View {
        Section("venue_confirm_venue_title") {
            HStack(spacing: 12) {
                SportCover(url: model.imageURL(venue.images.min { $0.sortOrder < $1.sortOrder }?.imageId), sport: model.sport.loopSport, iconSize: 28)
                    .frame(width: 64, height: 64)
                    .clipShape(.rect(cornerRadius: 12))
                VStack(alignment: .leading, spacing: 4) {
                    Text(verbatim: venue.displayName).font(.headline)
                    Label { Text(model.sport.loopSport.labelKey) } icon: { Image(model.sport.loopSport.iconAsset).resizable().scaledToFit().frame(width: 16, height: 16) }
                        .font(.subheadline)
                    if !venue.building.address.isEmpty {
                        Label { Text(verbatim: venue.building.address).lineLimit(2) } icon: { Image(systemName: "mappin.and.ellipse") }
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
    }

    private func detailsSection(_ venue: VenueDetail) -> some View {
        let pricing = model.pricing
        return Section("venue_confirm_details_title") {
            LabeledContent("venue_confirm_date") { Text(verbatim: VenueTime.dateKeyLabel(model.dateKey, locale: locale)) }
            VStack(alignment: .leading, spacing: 8) {
                Text("venue_confirm_time_courts").font(.caption).foregroundStyle(.secondary)
                ForEach(Array(model.lines.enumerated()), id: \.element.id) { index, line in
                    HStack(alignment: .firstTextBaseline) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(verbatim: line.courtName).font(.subheadline.weight(.semibold))
                            Text(verbatim: "\(VenueTime.clock(line.startsAt, timezone: venue.timezone))–\(VenueTime.clock(line.endsAt, timezone: venue.timezone)) · \(localizedFormat("venue_confirm_summary_minutes", String(line.minutes)))")
                                .font(.caption.monospacedDigit())
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        PriceStack(listCents: line.priceCents, payCents: pricing.linePayCents[safe: index] ?? line.priceCents, struck: pricing.struck, currency: venue.currency)
                    }
                }
            }
            if let member = pricing.member {
                Label {
                    Text(verbatim: localizedFormat("venue_confirm_member_applied", member.levelName, bookingDiscountZhe(member.discountPercent), String(member.discountPercent)))
                } icon: {
                    MembershipLevelBadge(icon: member.levelIcon, color: member.levelColor, size: 20)
                }
                .font(.subheadline)
            }
            HStack {
                Text("venue_confirm_summary_total").font(.headline)
                Spacer()
                PriceStack(listCents: pricing.totalListCents, payCents: pricing.totalPayCents, struck: pricing.struck, currency: venue.currency, emphasized: true)
            }
            if pricing.coveredByBundle, let bundle = model.selectedBundle {
                Text(verbatim: localizedFormat(
                    "venue_confirm_bundle_covers",
                    formatBundleHours(model.totalMinutes, locale: locale),
                    formatBundleHours(bundle.remainingMinutes - model.totalMinutes, locale: locale)
                ))
                .font(.footnote)
                .foregroundStyle(.secondary)
            }
            if let level = model.upsellLevel, model.memberSaveCents > 0, !pricing.coveredByBundle {
                MemberSaveHint(level: level, amount: formatMoney(Double(model.memberSaveCents) / 100, currency: venue.currency, locale: locale)) {
                    shell?.push(LoopRoute.venue(venueId: model.venueId, sheet: .membership))
                }
            }
        }
    }

    private var contactSection: some View {
        Section {
            TextField("venue_confirm_contact_name", text: $model.contactName)
                .textContentType(.name)
            TextField("venue_confirm_contact_phone", text: $model.contactPhone)
                .keyboardType(.phonePad)
                .textContentType(.telephoneNumber)
            TextField("venue_confirm_contact_note_placeholder", text: $model.note, axis: .vertical)
                .lineLimit(2 ... 5)
        } header: {
            Text("venue_confirm_contact_title")
        } footer: {
            Text("venue_confirm_contact_hint")
        }
    }

    private var methodSection: some View {
        Section("venue_confirm_method_title") {
            ForEach(model.methods, id: \.self) { method in
                Button { model.selectMethod(method) } label: {
                    HStack(alignment: .top) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(method.titleKey).font(.subheadline.weight(.semibold)).foregroundStyle(Color.primary)
                            Text(method.bookerBodyKey).font(.caption).foregroundStyle(.secondary)
                        }
                        Spacer()
                        if model.method == method { Image(systemName: "checkmark").foregroundStyle(Color.accentColor) }
                    }
                }
            }
            if model.method == .platform {
                Text("venue_confirm_method_platform_direct").font(.caption).foregroundStyle(.secondary)
            }
            if model.method == .bundle {
                bundlePicker
            }
        }
    }

    /** 用时长包付：选哪个包（余额不够的置灰）；按场地原价扣时长，不叠加会员折扣。 */
    @ViewBuilder
    private var bundlePicker: some View {
        Text("venue_confirm_bundle_pick").font(.subheadline.weight(.semibold))
        ForEach(model.usableBundles, id: \.id) { bundle in
            let enabled = bundle.canPayBooking(model.sport, minutes: model.totalMinutes)
            let left = formatBundleHours(bundle.remainingMinutes, locale: locale)
            Button { model.selectBundle(bundle.id) } label: {
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(verbatim: bundle.name).font(.subheadline).foregroundStyle(Color.primary)
                        Text(verbatim: localizedFormat(enabled ? "venue_confirm_bundle_left" : "venue_confirm_bundle_short", left))
                            .font(.caption)
                            .foregroundStyle(enabled ? Color.secondary : Color.red)
                    }
                    Spacer()
                    if model.bundleId == bundle.id { Image(systemName: "checkmark").foregroundStyle(Color.accentColor) }
                }
            }
            .disabled(!enabled)
        }
        Text("venue_confirm_bundle_regular_rate").font(.caption).foregroundStyle(.secondary)
    }

    /** 底部：提示，然后按方式的提交按钮（和 WEB 一样）。 */
    private func submitBar(_ venue: VenueDetail) -> some View {
        VStack(spacing: 8) {
            if model.entry.data != nil, !model.isPublished {
                Text("venue_confirm_checkout_unpublished").font(.footnote).foregroundStyle(.secondary)
            }
            if model.signedIn, !model.isPulser {
                Text("venue_confirm_checkout_pulser_required").font(.footnote).foregroundStyle(.secondary)
            }
            if model.signedIn {
                Button {
                    Task {
                        if let route = await model.submit() { shell?.push(route) }
                    }
                } label: {
                    Group {
                        if model.submitting {
                            ProgressView()
                        } else {
                            switch model.method {
                            case .platform:
                                Text(verbatim: localizedFormat("venue_confirm_checkout_pay", formatMoney(Double(model.pricing.totalPayCents) / 100, currency: venue.currency, locale: locale)))
                            case .bundle:
                                Text(verbatim: localizedFormat("venue_confirm_checkout_use_bundle", formatBundleHours(model.totalMinutes, locale: locale)))
                            default:
                                Text("venue_confirm_checkout_request")
                            }
                        }
                    }
                    .frame(maxWidth: .infinity)
                }
                .buttonStyle(.pulso())
                .controlSize(.large)
                .disabled(!model.canSubmit)
            } else {
                Text("venue_confirm_checkout_login").font(.footnote).foregroundStyle(.secondary)
            }
        }
        .padding(16)
        .background(.bar)
    }
}

extension Array {
    subscript(safe index: Int) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}
