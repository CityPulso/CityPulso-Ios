import PulsoLinkCore
import PulsoLinkUI
import SwiftUI

/**
 * 确认预约（Android `SpaceConfirmPage`，所有门店类型共用）：门店和活动类型、预约详情（日期、几段桌台或一场主题 / 剧本、人数、合计）、
 * 联系信息、付款方式、退款政策、到店须知；底部按方式显示「去支付 / 提交预约」。
 */
struct VenueConfirmView: View {
    @State private var model: VenueConfirmModel
    @Environment(\.locale) private var locale
    @Environment(\.dismiss) private var dismiss
    @Environment(PulsoShellNavigator.self) private var shell: PulsoShellNavigator?

    init(venueId: String, activityType: VenueActivityType, dateKey: String, target: VenueConfirmTarget) {
        _model = State(initialValue: VenueConfirmModel(venueId: venueId, activityType: activityType, dateKey: dateKey, target: target))
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
                if model.dayLoading, model.lines.isEmpty {
                    ProgressView().frame(maxWidth: .infinity)
                } else if let error = model.dayError, model.lines.isEmpty {
                    PulsoLoadErrorView(error) { model.refresh() }
                } else if model.stale {
                    PulsoEmptyState(Text("venue_confirm_stale"), style: .calendar) {
                        Button("venue_confirm_back") { dismiss() }.buttonStyle(.pulso())
                    }
                } else if model.methods.isEmpty {
                    Text("venue_confirm_checkout_no_modes").foregroundStyle(.secondary)
                } else {
                    venueSection(venue)
                    detailsSection(venue)
                    contactSection
                    methodSection
                    if let refund = model.refundPolicy {
                        Section("venue_confirm_refund_title") {
                            SpaceRefundPolicySummary(policy: refund.policy, tiers: refund.tiers, note: refund.note)
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
                PulsoEmptyState(Text("venue_detail_not_found"), description: Text("venue_detail_not_found_body")) {
                    Button("venue_confirm_back") { dismiss() }.buttonStyle(.pulso())
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
                ActivityTypeCover(url: model.imageURL(venue.images.min { $0.sortOrder < $1.sortOrder }?.imageId), activityType: model.activityType.kind, iconSize: 28)
                    .frame(width: 64, height: 64)
                    .clipShape(.rect(cornerRadius: 12))
                VStack(alignment: .leading, spacing: 4) {
                    Text(verbatim: venue.displayName).font(.headline)
                    Label { Text(model.activityType.kind.labelKey) } icon: { Image(model.activityType.kind.iconAsset).resizable().scaledToFit().frame(width: 16, height: 16) }
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
                Text("venue_confirm_time_spaces").font(.caption).foregroundStyle(.secondary)
                ForEach(Array(model.lines.enumerated()), id: \.element.id) { index, line in
                    HStack(alignment: .firstTextBaseline) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(verbatim: line.spaceName).font(.subheadline.weight(.semibold))
                            Text(verbatim: "\(VenueTime.clock(line.startsAt, timezone: venue.timezone))–\(VenueTime.clock(line.endsAt, timezone: venue.timezone)) · \(localizedFormat("venue_confirm_summary_minutes", String(line.minutes)))")
                                .font(.caption.monospacedDigit())
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        PriceStack(listCents: line.priceCents, payCents: pricing.linePayCents[safe: index] ?? line.priceCents, struck: pricing.struck, currency: venue.currency)
                    }
                }
            }
            if let partySize = model.partySize {
                Label { Text(verbatim: localizedFormat("activity_detail_participants_exact", partySize)) } icon: { Image(systemName: "person.3") }
                    .font(.subheadline)
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
            if let level = model.upsellLevel, model.memberSaveCents > 0 {
                MemberSaveHint(level: level, amount: formatMoney(Double(model.memberSaveCents) / 100, currency: venue.currency, locale: locale)) {
                    shell?.push(NearRoute.venue(venueId: model.venueId, sheet: .membership))
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
        }
    }

    /** 底部：提示，然后按方式的提交按钮（和 WEB 一样）。 */
    private func submitBar(_ venue: VenueDetail) -> some View {
        VStack(spacing: 8) {
            if model.entryLoaded, !model.isPublished {
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
