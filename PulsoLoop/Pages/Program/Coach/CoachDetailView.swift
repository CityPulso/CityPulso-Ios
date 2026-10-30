import Factory
import PulsoLinkCore
import PulsoLinkUI
import SwiftUI

/** 教练主页（Android `CoachDetailViewModel`）：读一次教练公开资料。 */
@MainActor
@Observable
final class CoachDetailModel {
    let profileId: String
    private(set) var coach = Loadable<CoachProfile>()

    @ObservationIgnored @Injected(\.coachService) private var coachService
    @ObservationIgnored @Injected(\.pulsoCoreConfig) private var config

    init(profileId: String) {
        self.profileId = profileId
    }

    func load() async {
        coach.isLoading = true
        do {
            coach = try await Loadable(data: coachService.coachPage(profileId), isLoading: false)
        } catch {
            coach = Loadable(data: coach.data, isLoading: false, error: UiError(error))
        }
    }

    func avatarURL(_ imageId: String?) -> URL? {
        ImageURLs.image(imageId, base: config.apiBaseURL)
    }
}

/** 教练主页（Android `CoachDetailScreen`）：头像和简介、资质、私教服务、合作球馆。 */
struct CoachDetailView: View {
    @State private var model: CoachDetailModel
    @Environment(\.locale) private var locale

    init(profileId: String) {
        _model = State(initialValue: CoachDetailModel(profileId: profileId))
    }

    var body: some View {
        content
            .navigationTitle(Text(verbatim: model.coach.data?.displayName ?? ""))
            .navigationBarTitleDisplayMode(.inline)
            .task { await model.load() }
    }

    @ViewBuilder
    private var content: some View {
        if let coach = model.coach.data {
            List {
                Section {
                    HStack(spacing: 16) {
                        PulsoAvatar(url: model.avatarURL(coach.avatarImageId), size: 64, fallbackText: coach.displayName.map { String($0.prefix(1)) })
                        VStack(alignment: .leading, spacing: 2) {
                            Text(verbatim: coach.displayName ?? coach.coachProfileId).font(.title3.bold())
                            if let headline = coach.headline { Text(verbatim: headline).foregroundStyle(.secondary) }
                            if let years = coach.yearsExperience { Text(verbatim: localizedFormat("coach_detail_years", years)).font(.caption) }
                        }
                    }
                    if let bio = coach.bio, !bio.trimmingCharacters(in: .whitespaces).isEmpty {
                        Text(verbatim: bio)
                    }
                }
                if let certifications = coach.certifications, !certifications.trimmingCharacters(in: .whitespaces).isEmpty {
                    Section("coach_detail_certifications") { Text(verbatim: certifications) }
                }
                Section("coach_detail_services") {
                    ForEach(coach.services ?? [], id: \.id) { service in
                        VStack(alignment: .leading) {
                            Text(verbatim: service.title)
                            Text(verbatim: "\(String(localized: service.format.labelResource)) · \(localizedFormat("coach_detail_per_hour", formatMoney(service.hourlyPriceAmount, currency: service.currency, locale: locale)))")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                Section("coach_detail_venues") {
                    ForEach(coach.partnerVenues ?? [], id: \.venueCoachId) { venue in
                        NavigationLink(value: LoopRoute.venue(venueId: venue.venueId, sheet: nil)) {
                            Text(verbatim: venue.certified ? "\(venue.venueName) · \(String(localized: "coach_detail_certified"))" : venue.venueName)
                        }
                    }
                }
            }
            .refreshable { await model.load() }
        } else if let error = model.coach.error {
            PulsoLoadErrorView(error) { Task { await model.load() } }
        } else if model.coach.isLoading {
            ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            ContentUnavailableView("coach_detail_not_found", systemImage: "person.crop.circle.badge.questionmark")
        }
    }
}
