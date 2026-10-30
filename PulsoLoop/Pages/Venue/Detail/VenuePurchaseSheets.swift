import PulsoLinkCore
import PulsoLinkUI
import SwiftUI

/**
 * 选会员方案（Android `MembershipPurchaseSheet`）：等级、时长（回本场次、比按月省多少）、报价（原价 / 抵扣 / 应付 / 有效期）、
 * 付款方式；降级要等当前周期结束。按方式显示「支付 / 确认」。
 */
struct MembershipPurchaseSheet: View {
    let model: VenueDetailModel
    let timezone: String

    @Environment(\.locale) private var locale

    var body: some View {
        let purchase = model.purchase
        let levels = (model.offers.data?.levels ?? []).filter { level in model.shownOffers.contains { $0.levelId == level.id } }.sorted { $0.rank < $1.rank }
        let offers = model.offersForLevel(purchase.levelId)
        let selectedOffer = model.shownOffers.first { $0.id == purchase.offerId }
        let lowerTier = model.activeMembership.map { active in selectedOffer.map { $0.rank < active.rank } ?? false } ?? false
        NavigationStack {
            Form {
                Section {
                    Text("venue_membership_card_all_sports").font(.subheadline).foregroundStyle(.secondary)
                }
                Section("venue_membership_sheet_level") {
                    ForEach(levels, id: \.id) { level in
                        Button { model.selectLevel(level.id) } label: {
                            HStack(spacing: 10) {
                                MembershipLevelBadge(icon: level.icon, color: level.color, size: 32)
                                VStack(alignment: .leading, spacing: 2) {
                                    HStack {
                                        Text(verbatim: level.name).font(.subheadline.weight(.semibold)).foregroundStyle(Color.primary)
                                        if level.id == model.activeMembership?.levelId {
                                            VenueChip(text: String(localized: "venue_membership_current"), tone: Color.accentColor)
                                        }
                                    }
                                    Text(verbatim: level.discountPercent > 0
                                        ? localizedFormat("membership_discount", level.name, bookingDiscountZhe(level.discountPercent), String(level.discountPercent))
                                        : String(localized: "membership_no_discount"))
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                                Spacer()
                                if purchase.levelId == level.id { Image(systemName: "checkmark").foregroundStyle(Color.accentColor) }
                            }
                        }
                    }
                }
                if !offers.isEmpty {
                    Section("venue_membership_sheet_duration") {
                        ForEach(offers, id: \.id) { offer in
                            Button { model.selectOffer(offer.id) } label: {
                                HStack(alignment: .top) {
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(verbatim: membershipTermLabel(offer.durationMonths)).font(.subheadline.weight(.semibold)).foregroundStyle(Color.primary)
                                        if let sessions = offer.breakEvenSessions {
                                            Text(verbatim: localizedFormat("venue_membership_break_even", sessions)).font(.caption).foregroundStyle(.secondary)
                                        }
                                        if let save = offer.saveVersusMonthly, save > 0 {
                                            Text(verbatim: localizedFormat("venue_membership_save_vs_monthly", formatMoney(save, currency: offer.currency, locale: locale)))
                                                .font(.caption)
                                                .foregroundStyle(RadixScale.green.lightStep(9))
                                        }
                                    }
                                    Spacer()
                                    if let price = offer.priceAmount {
                                        Text(verbatim: formatMoney(price, currency: offer.currency, locale: locale)).font(.subheadline.monospacedDigit()).foregroundStyle(Color.primary)
                                    }
                                    if purchase.offerId == offer.id { Image(systemName: "checkmark").foregroundStyle(Color.accentColor) }
                                }
                            }
                        }
                    }
                }
                Section { quotePanel(purchase) }
                if lowerTier {
                    Section {
                        Text(verbatim: model.activeMembership?.endsAt.map { localizedFormat("venue_membership_lower_after", VenueTime.date($0, timezone: timezone, locale: locale)) }
                            ?? String(localized: "venue_membership_lower_open"))
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                } else if model.purchaseMethods.isEmpty {
                    Section { Text("venue_membership_no_modes").font(.footnote).foregroundStyle(.secondary) }
                } else {
                    Section("venue_membership_method_title") {
                        ForEach(model.purchaseMethods, id: \.self) { method in
                            Button { model.selectPaymentMethod(method) } label: {
                                MethodRow(title: method.titleKey, detail: method.bookerBodyKey, selected: purchase.paymentMethod == method)
                            }
                        }
                    }
                }
                Section { outcome(purchase, lowerTier: lowerTier) }
            }
            .navigationTitle("venue_membership_sheet_title")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button { model.closeMembershipSheet() } label: { Image(systemName: "xmark") }
                }
            }
        }
        .presentationDetents([.large])
    }

    @ViewBuilder
    private func quotePanel(_ purchase: MembershipPurchaseState) -> some View {
        if purchase.offerId == nil {
            Text("venue_membership_pick_offer").font(.subheadline).foregroundStyle(.secondary)
        } else if let quote = purchase.quote?.data {
            QuoteRow(label: Text("venue_membership_quote_list"), value: formatMoney(quote.listAmount, currency: quote.currency, locale: locale))
            if quote.creditAmount > 0 {
                QuoteRow(
                    label: quote.unusedDays > 0 ? Text(verbatim: localizedFormat("venue_membership_quote_credit_days", quote.unusedDays)) : Text("venue_membership_quote_credit"),
                    value: "−" + formatMoney(quote.creditAmount, currency: quote.currency, locale: locale)
                )
            }
            QuoteRow(label: Text("venue_membership_quote_charged"), value: formatMoney(quote.chargedAmount, currency: quote.currency, locale: locale), emphasized: true)
            Text(verbatim: quote.kind == .renew && quote.endsAt != nil
                ? localizedFormat("venue_membership_extends_until", VenueTime.date(quote.endsAt!, timezone: timezone, locale: locale))
                : localizedFormat("venue_membership_quote_period", VenueTime.date(quote.startsAt, timezone: timezone, locale: locale), quote.endsAt.map { VenueTime.date($0, timezone: timezone, locale: locale) } ?? String(localized: "membership_lifetime")))
                .font(.caption)
                .foregroundStyle(.secondary)
        } else if purchase.quote?.isLoading == true {
            ProgressView()
        }
    }

    @ViewBuilder
    private func outcome(_ purchase: MembershipPurchaseState, lowerTier: Bool) -> some View {
        if let error = purchase.error {
            Text(verbatim: error).font(.footnote).foregroundStyle(.red)
        }
        if purchase.processing {
            Label("venue_membership_processing", systemImage: "hourglass").font(.subheadline)
        } else if purchase.activated {
            Label("venue_membership_activated", systemImage: "checkmark.circle").font(.subheadline).foregroundStyle(RadixScale.green.lightStep(9))
        } else if purchase.awaitingVenue {
            Text((purchase.replacedPrevious ? "venue_membership_replaced" : "venue_membership_awaiting_venue") as LocalizedStringKey).font(.subheadline)
        } else if !model.signedIn {
            Text("venue_membership_login_cta").font(.subheadline).foregroundStyle(.secondary)
        } else if !lowerTier {
            let quote = purchase.quote?.data
            Button {
                Task { await model.purchaseMembership() }
            } label: {
                Group {
                    if purchase.purchasing {
                        ProgressView()
                    } else if quote == nil || quote!.chargedAmount <= 0 {
                        Text("venue_membership_confirm_free_cta")
                    } else if purchase.paymentMethod == .platform {
                        Text(verbatim: localizedFormat("venue_membership_pay_cta", formatMoney(quote!.chargedAmount, currency: quote!.currency, locale: locale)))
                    } else {
                        Text(verbatim: localizedFormat("venue_membership_confirm_amount_cta", formatMoney(quote!.chargedAmount, currency: quote!.currency, locale: locale)))
                    }
                }
                .frame(maxWidth: .infinity)
            }
            .buttonStyle(.glassProminent)
            .controlSize(.large)
            .disabled(purchase.purchasing || quote == nil || !model.canBuy || purchase.paymentMethod == nil)
            .listRowBackground(Color.clear)
        }
    }
}

/**
 * 买时长包（Android `BundlePurchaseSheet`）：在售的包、报价（时长 / 有效期 / 价格 / 会员价 / 实付）、付款方式；
 * 时长包按场地原价扣时长，不叠加会员折扣。
 */
struct BundlePurchaseSheet: View {
    let model: VenueBundleModel

    @Environment(\.locale) private var locale

    var body: some View {
        let purchase = model.purchase
        NavigationStack {
            Form {
                Section {
                    Text("venue_bundle_sheet_subtitle").font(.subheadline).foregroundStyle(.secondary)
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 10) {
                            ForEach(model.shownOffers, id: \.id) { offer in
                                BundleOfferTicket(offer: offer, hourlyPrice: model.hourlyPrice, selected: offer.id == purchase.offerId) { model.selectOffer(offer.id) }
                            }
                        }
                        .padding(.vertical, 4)
                    }
                    .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16))
                }
                Section {
                    if let offer = model.selectedOffer {
                        QuoteRow(label: Text("venue_bundle_quote_hours"), value: formatBundleHours(offer.includedMinutes, locale: locale))
                        QuoteRow(label: Text("venue_bundle_quote_validity"), value: offer.validDays.map { localizedFormat("venue_bundle_quote_validity_days", $0) } ?? String(localized: "bundle_offer_never_expires"))
                        let quote = purchase.quote?.data
                        QuoteRow(label: Text("venue_bundle_quote_list"), value: formatMoney(quote?.listAmount ?? offer.priceAmount, currency: quote?.currency ?? offer.currency, locale: locale))
                        if let quote, quote.memberPrice, quote.chargedAmount < quote.listAmount {
                            let level = offer.memberPrices.first { $0.levelId == quote.levelId }?.levelName
                            QuoteRow(
                                label: level.map { Text(verbatim: localizedFormat("venue_bundle_quote_member_price_of", $0)) } ?? Text("venue_bundle_quote_member_price"),
                                value: "−" + formatMoney(quote.listAmount - quote.chargedAmount, currency: quote.currency, locale: locale)
                            )
                        }
                        if let quote {
                            QuoteRow(label: Text("venue_bundle_quote_charged"), value: formatMoney(quote.chargedAmount, currency: quote.currency, locale: locale), emphasized: true)
                        } else if purchase.quote?.isLoading == true {
                            ProgressView()
                        }
                    } else {
                        Text("venue_bundle_pick").font(.subheadline).foregroundStyle(.secondary)
                    }
                } footer: {
                    Text("venue_bundle_no_stacking")
                }
                if model.purchaseMethods.isEmpty {
                    Section { Text("venue_bundle_no_modes").font(.footnote).foregroundStyle(.secondary) }
                } else {
                    Section("venue_bundle_method_title") {
                        ForEach(model.purchaseMethods, id: \.self) { method in
                            Button { model.selectPaymentMethod(method) } label: {
                                MethodRow(title: method.titleKey, detail: method.bookerBodyKey, selected: purchase.paymentMethod == method)
                            }
                        }
                    }
                }
                Section { outcome(purchase) }
            }
            .navigationTitle("venue_bundle_title")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button { model.closeSheet() } label: { Image(systemName: "xmark") }
                }
            }
        }
        .presentationDetents([.large])
    }

    @ViewBuilder
    private func outcome(_ purchase: BundlePurchaseState) -> some View {
        if let error = purchase.error {
            Text(verbatim: error).font(.footnote).foregroundStyle(.red)
        }
        if purchase.processing {
            Label("venue_bundle_processing", systemImage: "hourglass").font(.subheadline)
        } else if purchase.activated {
            Label("venue_bundle_activated", systemImage: "checkmark.circle").font(.subheadline).foregroundStyle(RadixScale.green.lightStep(9))
        } else if purchase.awaitingVenue {
            Text((purchase.replacedPrevious ? "venue_bundle_replaced" : "venue_bundle_awaiting_venue") as LocalizedStringKey).font(.subheadline)
        } else if !model.signedIn {
            Text("venue_bundle_login_cta").font(.subheadline).foregroundStyle(.secondary)
        } else {
            let quote = purchase.quote?.data
            Button {
                Task { await model.purchaseBundle() }
            } label: {
                Group {
                    if purchase.purchasing {
                        ProgressView()
                    } else if quote == nil || quote!.chargedAmount <= 0 {
                        Text("venue_bundle_confirm_free_cta")
                    } else if purchase.paymentMethod == .platform {
                        Text(verbatim: localizedFormat("venue_bundle_pay_cta", formatMoney(quote!.chargedAmount, currency: quote!.currency, locale: locale)))
                    } else {
                        Text(verbatim: localizedFormat("venue_bundle_confirm_amount_cta", formatMoney(quote!.chargedAmount, currency: quote!.currency, locale: locale)))
                    }
                }
                .frame(maxWidth: .infinity)
            }
            .buttonStyle(.glassProminent)
            .controlSize(.large)
            .disabled(purchase.purchasing || quote == nil || !model.canBuy || purchase.paymentMethod == nil)
            .listRowBackground(Color.clear)
        }
    }
}

private struct QuoteRow: View {
    let label: Text
    let value: String
    var emphasized = false

    var body: some View {
        LabeledContent {
            Text(verbatim: value).monospacedDigit().fontWeight(emphasized ? .bold : .regular)
        } label: {
            label
        }
        .font(emphasized ? .headline : .subheadline)
    }
}

/** 付款方式一行：标题、说明、选中勾。 */
struct MethodRow: View {
    let title: LocalizedStringKey
    let detail: LocalizedStringKey
    let selected: Bool

    var body: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.subheadline.weight(.semibold)).foregroundStyle(Color.primary)
                Text(detail).font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            if selected { Image(systemName: "checkmark").foregroundStyle(Color.accentColor) }
        }
    }
}
