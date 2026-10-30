import PulsoLinkCore
import PulsoLinkUI
import SwiftUI

/**
 * 详情正文（Android `<ActivityType>Body`）：照片、标题、活动提示、事实卡、我的报名、参与者、介绍、详情、收费方式。
 * 操作在底栏。
 */
struct ActivityDetailBody: View {
    let model: ActivityDetailModel
    let activity: any ActivityTypeFullActivity
    let onOpenMap: (() -> Void)?
    let onOpenHost: () -> Void

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                ActivityHero(urls: model.imageURLs, activityType: model.activityType)
                ActivityTitleBlock(activity: activity, isHost: model.isHost).padding(.horizontal)
                if let notice = model.activityType.notice {
                    ActivityNoticeCallout(notice: notice).padding(.horizontal)
                }
                ActivityInfoCard(model: model, activity: activity, onOpenMap: onOpenMap, onOpenHost: onOpenHost).padding(.horizontal)
                if let registration = model.myRegistration, registration.status != .exited {
                    MyStatusCard(model: model, activity: activity, registration: registration).padding(.horizontal)
                }
                if let error = model.actionError, !model.isActionInProgress {
                    Text(verbatim: error).font(.footnote).foregroundStyle(.red).padding(.horizontal)
                }
                ParticipantsEntry(model: model, capacity: activity.capacity).padding(.horizontal)
                AboutSection(activity: activity).padding(.horizontal)
                if !activity.facts.isEmpty {
                    DetailsSection(facts: activity.facts).padding(.horizontal)
                }
                if !activity.isFree, !activity.paymentMethodList.isEmpty {
                    PaymentMethodsSection(methods: activity.paymentMethodList).padding(.horizontal)
                }
            }
            .padding(.bottom, 24)
        }
        .ignoresSafeArea(edges: .top)
    }
}

/** 照片轮播；没有照片就显示活动类型封面（Android `PulsoHeroPager`）。 */
private struct ActivityHero: View {
    let urls: [URL]
    let activityType: NearActivityKind

    @State private var page = 0

    var body: some View {
        Group {
            if urls.isEmpty {
                ActivityTypeCover(url: nil, activityType: activityType, iconSize: 72)
            } else {
                TabView(selection: $page) {
                    ForEach(urls.indices, id: \.self) { index in
                        PulsoRemoteImage(url: urls[index]).tag(index)
                    }
                }
                .tabViewStyle(.page(indexDisplayMode: .never))
                .overlay(alignment: .bottomTrailing) {
                    if urls.count > 1 {
                        Text(verbatim: localizedFormat("activity_detail_photo_counter", page + 1, urls.count))
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

/** 标题、标签行（活动类型、已结束 / 我发起）、浏览数。 */
private struct ActivityTitleBlock: View {
    let activity: any ActivityTypeFullActivity
    let isHost: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            ActivityTitle(title: activity.title).font(.title2.bold())
            PulsoFlowLayout(spacing: 8) {
                ActivityTag(Text(activity.activityType.labelKey), accent: true, image: Image(activity.activityType.iconAsset))
                ForEach(activity.optionLabels.indices, id: \.self) { ActivityTag(activity.optionLabels[$0]) }
                if activity.isEnded { ActivityTag(Text("activity_detail_ended_badge")) }
                if isHost { ActivityTag(Text("activity_detail_host_badge"), accent: true) }
            }
            Label { Text(verbatim: localizedFormat("shell_views_count", activity.view)) } icon: { Image(systemName: "eye") }
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
    }
}

/** 活动页的小标签（Android `ActivityTagChip`）。 */
struct ActivityTag: View {
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
private struct ActivityInfoCard: View {
    let model: ActivityDetailModel
    let activity: any ActivityTypeFullActivity
    let onOpenMap: (() -> Void)?
    let onOpenHost: () -> Void

    @Environment(\.locale) private var locale

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .top, spacing: 16) {
                cell("calendar", title: timeLabel, subtitle: Text("activity_detail_field_time"))
                cell("person.3", title: localizedFormat("activity_detail_capacity_value", model.activeSeats, activity.capacity), subtitle: seatsLine)
            }
            row(onOpenMap) {
                FactMarker(systemImage: "mappin.and.ellipse")
            } title: {
                Text(verbatim: venue ?? String(localized: "activity_detail_space_tbd"))
            } subtitle: {
                if let address = activity.address, !address.isEmpty, address != venue { Text(verbatim: address) }
            }
            row(onOpenHost) {
                PulsoAvatar(url: model.imageURL(model.hostAvatarImageId), size: 36, fallbackText: hostName)
            } title: {
                Text(verbatim: hostName)
            } subtitle: {
                Text("activity_detail_section_host")
            }
        }
        .padding()
        .background(.background.secondary, in: .rect(cornerRadius: 16))
    }

    private var timeLabel: String {
        let label = DateTimeFormatters.sessionDayClockRange(activity.startsAt, activity.endsAt, locale: locale)
        return label.isEmpty ? activity.startsAt : label
    }

    private var venue: String? {
        [activity.venueName, activity.address].compactMap { $0 }.first { !$0.isEmpty }
    }

    private var hostName: String {
        model.hostDisplayName.flatMap { $0.isEmpty ? nil : $0 } ?? String(localized: "activity_detail_host_organizer")
    }

    private var seatsLine: Text {
        if activity.isEnded { return Text("activity_detail_ended_badge") }
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
func seatsLeftLabel(_ model: ActivityDetailModel) -> String {
    model.leavingSeats > 0
        ? localizedFormat("activity_detail_seats_left_leaving", model.remainingSeats, model.leavingSeats)
        : localizedFormat("activity_detail_seats_left", model.remainingSeats)
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
    let model: ActivityDetailModel
    let capacity: Int

    var body: some View {
        Button { model.sheet = .participants } label: {
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 8) {
                    Text(verbatim: localizedFormat("activity_detail_participants_title", model.activeSeats, capacity))
                        .font(.subheadline.weight(.semibold))
                    if !model.rosterReady {
                        ProgressView()
                    } else if model.seatedRegistrations.isEmpty {
                        Text("activity_detail_roster_empty_participating").font(.footnote).foregroundStyle(.secondary)
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
    let activity: any ActivityTypeFullActivity

    @State private var expanded = false

    private var description: String? {
        activity.description.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.flatMap { $0.isEmpty ? nil : $0 }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            SectionTitle("activity_detail_about_title")
            if let description {
                Text(verbatim: description).font(.body).lineLimit(expanded ? nil : 4)
                if description.count > 120 || description.contains("\n") {
                    Button((expanded ? "activity_detail_show_less" : "activity_detail_show_more") as LocalizedStringKey) { expanded.toggle() }
                        .font(.subheadline)
                }
            } else {
                Text("activity_detail_no_description").font(.body).foregroundStyle(.secondary)
            }
        }
    }
}

/** 各活动类型自己的事实格子（人数；麻将还有规则），两列。 */
private struct DetailsSection: View {
    let facts: [OptionFact]

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            SectionTitle("activity_detail_details_title")
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

/** 发起人怎么收钱：每种方式一个标签，转账类附账户。 */
private struct PaymentMethodsSection: View {
    let methods: [ActivityPaymentMethod]

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            SectionTitle("activity_detail_section_payment")
            VStack(alignment: .leading, spacing: 8) {
                ForEach(methods, id: \.self) { method in
                    HStack(spacing: 8) {
                        ActivityTag(Text(method.kind.labelKey), accent: true)
                        switch method.kind {
                        case .cash: EmptyView()
                        case .stripe: Text("activity_detail_payment_stripe_note").font(.footnote).foregroundStyle(.secondary)
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
