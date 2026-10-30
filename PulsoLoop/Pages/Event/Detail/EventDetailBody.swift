import PulsoLinkCore
import PulsoLinkUI
import SwiftUI

/**
 * 详情正文（Android `<Sport>Body`）：照片、标题、事实卡、我的报名、参与者、介绍、详情、装备、收费方式。
 * 操作在底栏。
 */
struct EventDetailBody: View {
    let model: EventDetailModel
    let event: any SportFullEvent
    let onOpenMap: (() -> Void)?
    let onOpenHost: () -> Void

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                EventHero(urls: model.imageURLs, sport: model.sport)
                EventTitleBlock(event: event, isHost: model.isHost).padding(.horizontal)
                EventInfoCard(model: model, event: event, onOpenMap: onOpenMap, onOpenHost: onOpenHost).padding(.horizontal)
                if let registration = model.myRegistration, registration.status != .exited {
                    MyStatusCard(model: model, event: event, registration: registration).padding(.horizontal)
                }
                if let error = model.actionError, !model.isActionInProgress {
                    Text(verbatim: error).font(.footnote).foregroundStyle(.red).padding(.horizontal)
                }
                ParticipantsEntry(model: model, capacity: event.capacity).padding(.horizontal)
                AboutSection(event: event).padding(.horizontal)
                if !event.facts.isEmpty {
                    DetailsSection(facts: event.facts).padding(.horizontal)
                }
                GearSection(equipment: event.equipmentList).padding(.horizontal)
                if !event.isFree, !event.paymentMethodList.isEmpty {
                    PaymentMethodsSection(methods: event.paymentMethodList).padding(.horizontal)
                }
            }
            .padding(.bottom, 24)
        }
        .ignoresSafeArea(edges: .top)
    }
}

/** 照片轮播；没有照片就显示运动封面（Android `PulsoHeroPager`）。 */
private struct EventHero: View {
    let urls: [URL]
    let sport: LoopSport

    @State private var page = 0

    var body: some View {
        Group {
            if urls.isEmpty {
                SportCover(url: nil, sport: sport, iconSize: 72)
            } else {
                TabView(selection: $page) {
                    ForEach(urls.indices, id: \.self) { index in
                        PulsoRemoteImage(url: urls[index]).tag(index)
                    }
                }
                .tabViewStyle(.page(indexDisplayMode: .never))
                .overlay(alignment: .bottomTrailing) {
                    if urls.count > 1 {
                        Text(verbatim: localizedFormat("event_detail_photo_counter", page + 1, urls.count))
                            .font(.caption.weight(.medium))
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .glassEffect(.regular, in: .capsule)
                            .padding(12)
                    }
                }
            }
        }
        .frame(height: 280)
        .clipped()
    }
}

/** 标题、标签行（运动、各运动的选项、已结束 / 我发起）、浏览数。 */
private struct EventTitleBlock: View {
    let event: any SportFullEvent
    let isHost: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            EventTitle(title: event.title).font(.title2.bold())
            PulsoFlowLayout(spacing: 8) {
                EventTag(Text(event.sport.labelKey), accent: true, image: Image(event.sport.iconAsset))
                ForEach(event.optionLabels.indices, id: \.self) { EventTag(event.optionLabels[$0]) }
                if event.isEnded { EventTag(Text("event_detail_ended_badge")) }
                if isHost { EventTag(Text("event_detail_host_badge"), accent: true) }
            }
            Label { Text(verbatim: localizedFormat("shell_views_count", event.view)) } icon: { Image(systemName: "eye") }
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
    }
}

/** 活动页的小标签（Android `EventTagChip`）。 */
struct EventTag: View {
    private let text: Text
    private let accent: Bool
    private let image: Image?

    init(_ text: Text, accent: Bool = false, image: Image? = nil) {
        self.text = text
        self.accent = accent
        self.image = image
    }

    var body: some View {
        HStack(spacing: 4) {
            if let image { image.resizable().scaledToFit().frame(width: 14, height: 14) }
            text
        }
        .font(.caption.weight(.medium))
        .foregroundStyle(accent ? Color.accentColor : Color.primary)
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .background(accent ? AnyShapeStyle(Color.accentColor.opacity(0.12)) : AnyShapeStyle(.fill.tertiary), in: .capsule)
    }
}

/** 事实卡：时间和名额并排，下面地点（有坐标可开地图）和发起人（开主页）。 */
private struct EventInfoCard: View {
    let model: EventDetailModel
    let event: any SportFullEvent
    let onOpenMap: (() -> Void)?
    let onOpenHost: () -> Void

    @Environment(\.locale) private var locale

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .top, spacing: 16) {
                cell("calendar", title: timeLabel, subtitle: Text("event_detail_field_time"))
                cell("person.3", title: localizedFormat("event_detail_capacity_value", model.activeSeats, event.capacity), subtitle: seatsLine)
            }
            row(onOpenMap) {
                FactMarker(systemImage: "mappin.and.ellipse")
            } title: {
                Text(verbatim: venue ?? String(localized: "event_detail_court_tbd"))
            } subtitle: {
                if let address = event.address, !address.isEmpty, address != venue { Text(verbatim: address) }
            }
            row(onOpenHost) {
                PulsoAvatar(url: model.imageURL(model.hostAvatarImageId), size: 36, fallbackText: hostName)
            } title: {
                Text(verbatim: hostName)
            } subtitle: {
                Text("event_detail_section_host")
            }
        }
        .padding()
        .background(.background.secondary, in: .rect(cornerRadius: 16))
    }

    private var timeLabel: String {
        let label = DateTimeFormatters.sessionDayClockRange(event.startsAt, event.endsAt, locale: locale)
        return label.isEmpty ? event.startsAt : label
    }

    private var venue: String? {
        [event.venueName, event.address].compactMap { $0 }.first { !$0.isEmpty }
    }

    private var hostName: String {
        model.hostDisplayName.flatMap { $0.isEmpty ? nil : $0 } ?? String(localized: "event_detail_host_organizer")
    }

    private var seatsLine: Text {
        if event.isEnded { return Text("event_detail_ended_badge") }
        return Text(verbatim: seatsLeftLabel(model))
    }

    private func cell(_ systemImage: String, title: String, subtitle: Text) -> some View {
        HStack(alignment: .top, spacing: 12) {
            FactMarker(systemImage: systemImage)
            VStack(alignment: .leading, spacing: 2) {
                Text(verbatim: title).font(.subheadline.weight(.semibold)).lineLimit(2)
                subtitle.font(.caption).foregroundStyle(.secondary).lineLimit(1)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func row(
        _ action: (() -> Void)?,
        @ViewBuilder leading: () -> some View,
        @ViewBuilder title: () -> some View,
        @ViewBuilder subtitle: () -> some View
    ) -> some View {
        let content = HStack(spacing: 12) {
            leading()
            VStack(alignment: .leading, spacing: 2) {
                title().font(.subheadline.weight(.semibold)).lineLimit(2)
                subtitle().font(.caption).foregroundStyle(.secondary).lineLimit(2)
            }
            Spacer(minLength: 0)
            if action != nil { Image(systemName: "chevron.right").font(.footnote).foregroundStyle(.tertiary) }
        }
        .contentShape(.rect)
        return Button { action?() } label: { content }
            .buttonStyle(.plain)
            .disabled(action == nil)
    }
}

/** 「还有 N 个名额」/「还有 N 个名额 · M 人待退出」。 */
@MainActor
func seatsLeftLabel(_ model: EventDetailModel) -> String {
    model.leavingSeats > 0
        ? localizedFormat("event_detail_seats_left_leaving", model.remainingSeats, model.leavingSeats)
        : localizedFormat("event_detail_seats_left", model.remainingSeats)
}

/** 每张卡上同样的「事实」圆标（Android `LeadingIcon`）。 */
struct FactMarker: View {
    let systemImage: String

    var body: some View {
        Image(systemName: systemImage)
            .font(.body)
            .foregroundStyle(Color.accentColor)
            .frame(width: 36, height: 36)
            .background(Color.accentColor.opacity(0.12), in: .circle)
    }
}

/** 「参与者（18 / 24）」和前几个人的头像；点开参与者弹层。 */
private struct ParticipantsEntry: View {
    let model: EventDetailModel
    let capacity: Int

    var body: some View {
        Button { model.sheet = .participants } label: {
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 8) {
                    Text(verbatim: localizedFormat("event_detail_participants_title", model.activeSeats, capacity))
                        .font(.subheadline.weight(.semibold))
                    if !model.rosterReady {
                        ProgressView()
                    } else if model.seatedRegistrations.isEmpty {
                        Text("event_detail_roster_empty_participating").font(.footnote).foregroundStyle(.secondary)
                    } else {
                        HStack(spacing: -8) {
                            ForEach(Array(model.seatedRegistrations.prefix(5).enumerated()), id: \.offset) { _, registration in
                                PulsoAvatar(url: model.imageURL(registration.avatarImageId), size: 32, systemImage: "person", fallbackText: registration.displayName)
                                    .padding(2)
                                    .background(.background, in: .circle)
                            }
                        }
                    }
                }
                Spacer(minLength: 0)
                Image(systemName: "chevron.right").font(.footnote).foregroundStyle(.tertiary)
            }
            .padding()
            .background(.background.secondary, in: .rect(cornerRadius: 16))
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
    }
}

/** 发起人的介绍，太长时折叠成 4 行，可展开。 */
private struct AboutSection: View {
    let event: any SportFullEvent

    @State private var expanded = false

    private var description: String? {
        event.description.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.flatMap { $0.isEmpty ? nil : $0 }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            SectionTitle("event_detail_about_title")
            if let description {
                Text(verbatim: description).font(.body).lineLimit(expanded ? nil : 4)
                if description.count > 120 || description.contains("\n") {
                    Button((expanded ? "event_detail_show_less" : "event_detail_show_more") as LocalizedStringKey) { expanded.toggle() }
                        .font(.subheadline)
                }
            } else {
                Text("event_detail_no_description").font(.body).foregroundStyle(.secondary)
            }
        }
    }
}

/** 各运动自己的事实格子（球拍类：赛制、组别、场地数、每场人数），两列。 */
private struct DetailsSection: View {
    let facts: [OptionFact]

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            SectionTitle("event_detail_details_title")
            LazyVGrid(columns: [GridItem(.flexible(), spacing: 8), GridItem(.flexible(), spacing: 8)], spacing: 8) {
                ForEach(facts.indices, id: \.self) { index in
                    let fact = facts[index]
                    HStack(spacing: 12) {
                        FactMarker(systemImage: fact.systemImage)
                        VStack(alignment: .leading, spacing: 2) {
                            fact.value.font(.subheadline.weight(.semibold)).lineLimit(1)
                            fact.label.font(.caption).foregroundStyle(.secondary).lineLimit(1)
                        }
                        Spacer(minLength: 0)
                    }
                    .padding(12)
                    .background(.background.secondary, in: .rect(cornerRadius: 14))
                }
            }
        }
    }
}

private struct GearSection: View {
    let equipment: [EventEquipment]

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            SectionTitle("event_detail_section_gear")
            if equipment.isEmpty {
                Text("event_detail_gear_empty").font(.body).foregroundStyle(.secondary)
            } else {
                PulsoFlowLayout(spacing: 8) {
                    ForEach(equipment, id: \.self) { item in
                        Label { Text(verbatim: item.name) } icon: { Image(systemName: item.systemImage) }
                            .font(.caption.weight(.medium))
                            .padding(.horizontal, 10)
                            .padding(.vertical, 5)
                            .background(.fill.tertiary, in: .capsule)
                    }
                }
            }
        }
    }
}

/** 发起人怎么收钱：每种方式一个标签，转账类附账户。 */
private struct PaymentMethodsSection: View {
    let methods: [EventPaymentMethod]

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            SectionTitle("event_detail_section_payment")
            VStack(alignment: .leading, spacing: 8) {
                ForEach(methods, id: \.self) { method in
                    HStack(spacing: 8) {
                        EventTag(Text(method.kind.labelKey), accent: true)
                        switch method.kind {
                        case .cash: EmptyView()
                        case .stripe: Text("event_detail_payment_stripe_note").font(.footnote).foregroundStyle(.secondary)
                        case .etransfer, .wechat: Text(verbatim: method.account.isEmpty ? "—" : method.account).font(.body)
                        }
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding()
            .background(.background.secondary, in: .rect(cornerRadius: 16))
        }
    }
}

struct SectionTitle: View {
    let key: LocalizedStringKey

    init(_ key: LocalizedStringKey) {
        self.key = key
    }

    var body: some View {
        Text(key).font(.headline)
    }
}
