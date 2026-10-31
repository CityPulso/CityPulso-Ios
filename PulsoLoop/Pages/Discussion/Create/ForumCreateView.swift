import Factory
import PhotosUI
import PulsoLinkCore
import PulsoLinkUI
import SwiftUI

/** 建论坛（Android `ForumCreateViewModel`）：名字、简介、运动、头像和背景、规则；组织身份还能从球馆团队里直接选管理员。 */
@MainActor
@Observable
final class ForumCreateModel {
    var name = ""
    var description = "" { didSet { if description.count > forumDescriptionMax { description = String(description.prefix(forumDescriptionMax)) } } }
    var sports: [ForumSport] = []
    var settings = ForumSettings()
    let canPickStaff: Bool
    var staffSearch = ""
    private(set) var venueStaff: [ForumVenueStaff] = []
    var staff: [String: ForumMemberRole] = [:]
    private(set) var submitting = false
    let pictures = ForumPictures()

    @ObservationIgnored @Injected(\.discussionService) private var discussion
    @ObservationIgnored @Injected(\.pulsoCoreConfig) private var config

    init() {
        canPickStaff = Container.shared.profileStore().current.value?.kind == .organization
    }

    var nameError: Bool { !name.isEmpty && name.trimmingCharacters(in: .whitespaces).count > forumNameMax }

    var ready: Bool {
        !name.trimmingCharacters(in: .whitespaces).isEmpty && !sports.isEmpty && !nameError && !submitting && pictures.ready
    }

    func imageURL(_ id: String?) -> URL? { ImageURLs.image(id, base: config.apiBaseURL) }

    /** 球馆团队里的人；搜索词停 300ms 再查。 */
    func loadStaff(debounce: Bool) async {
        guard canPickStaff else { return }
        if debounce { try? await Task.sleep(for: .milliseconds(300)) }
        guard !Task.isCancelled else { return }
        let search = staffSearch.trimmingCharacters(in: .whitespaces)
        venueStaff = (try? await discussion.venueStaff(search.isEmpty ? nil : search)) ?? []
    }

    func submit() async -> String? {
        guard ready, let avatarId = pictures.avatar?.imageId else { return nil }
        submitting = true
        do {
            let id = try await discussion.createForum(CreateForumRequest(
                name: name.trimmingCharacters(in: .whitespaces),
                description: description.trimmingCharacters(in: .whitespacesAndNewlines),
                sports: sports,
                avatarImageId: avatarId,
                backgrounds: pictures.backgroundInputs,
                settings: settings,
                staff: staff.map { ForumStaffAssignment(profileId: $0.key, role: $0.value) }
            ))
            PulsoMessageCenter.shared.success("discussion_forum_created")
            return id
        } catch {
            submitting = false
            PulsoMessageCenter.shared.error(error, fallback: "discussion_action_failed")
            return nil
        }
    }
}

/**
 * 建论坛页（Android `ForumCreateScreen`），排得像主页：最上面是封面，名字旁边是论坛头像，运动一排图块，简介，
 * 发帖方式两张卡，剩下的规则和管理员各是一行，点进去是子页。
 */
struct ForumCreateView: View {
    @State private var model = ForumCreateModel()
    @State private var coverItems: [PhotosPickerItem] = []
    @State private var avatarItem: PhotosPickerItem?
    @Environment(PulsoShellNavigator.self) private var shell: PulsoShellNavigator?

    var body: some View {
        Form {
            Section {
                cover
                if model.pictures.backgrounds.count > 1 {
                    EventPhotoPicker(
                        photos: model.pictures.backgrounds,
                        localData: model.pictures.localData,
                        imageURL: model.imageURL,
                        onAdd: { model.pictures.addBackgrounds($0) },
                        onRemove: { model.pictures.removeBackground($0) },
                        onSetCover: { model.pictures.coverBackground($0) },
                        onRetry: { model.pictures.retryBackground($0) },
                        enabled: !model.submitting,
                        max: forumBackgroundsMax
                    )
                }
            }
            .listRowInsets(EdgeInsets())
            .listRowBackground(Color.clear)
            Section {
                HStack(spacing: 12) {
                    let avatarURL = model.imageURL(model.pictures.avatar?.imageId)
                    PhotosPicker(selection: $avatarItem, matching: .images) {
                        ForumAvatarThumb(pictures: model.pictures, remoteURL: avatarURL)
                    }
                    .buttonStyle(.plain)
                    .disabled(model.submitting)
                    .accessibilityLabel(Text("discussion_forum_avatar_pick"))
                    TextField("discussion_forum_name_placeholder", text: $model.name)
                }
            } header: {
                requiredLabel("discussion_forum_name")
            } footer: {
                if model.nameError {
                    Text(verbatim: localizedFormat("discussion_forum_name_too_long", forumNameMax)).foregroundStyle(.red)
                } else {
                    Text(verbatim: "\(model.name.trimmingCharacters(in: .whitespaces).count)/\(forumNameMax)")
                }
            }
            Section {
                ForumTypePicker(selected: $model.sports)
                    .listRowInsets(EdgeInsets(top: 8, leading: 12, bottom: 8, trailing: 12))
            } header: {
                HStack {
                    requiredLabel("discussion_forum_sport_pick")
                    Spacer()
                    Text(verbatim: model.sports.isEmpty ? String(localized: "discussion_forum_types_hint") : localizedFormat("discussion_forum_types_picked", model.sports.count))
                }
            }
            Section {
                TextField("discussion_forum_description_placeholder", text: $model.description, axis: .vertical)
                    .lineLimit(4 ... 10)
            } header: {
                Text("discussion_forum_description")
            } footer: {
                Text(verbatim: "\(model.description.count)/\(forumDescriptionMax)")
            }
            Section("discussion_forum_posting") {
                HStack(spacing: 12) {
                    postingCard("person.3", "discussion_forum_posting_open", "discussion_forum_posting_open_body", selected: !model.settings.requiresPostReview) {
                        model.settings.requiresPostReview = false
                    }
                    postingCard("lock", "discussion_forum_posting_review", "discussion_forum_posting_review_body", selected: model.settings.requiresPostReview) {
                        model.settings.requiresPostReview = true
                    }
                }
                .listRowInsets(EdgeInsets())
                .listRowBackground(Color.clear)
            }
            Section {
                NavigationLink {
                    rulesPage
                } label: {
                    LabeledContent {
                        Text(verbatim: localizedFormat("discussion_rules_summary", model.settings.mainRules.filter { $0 }.count, model.settings.mainRules.count))
                    } label: {
                        Label("discussion_rules_title", systemImage: "slider.horizontal.3")
                    }
                }
                if model.canPickStaff {
                    NavigationLink {
                        staffPage
                    } label: {
                        LabeledContent {
                            Text(verbatim: model.staff.isEmpty ? String(localized: "discussion_staff_summary_none") : localizedFormat("discussion_staff_summary_count", model.staff.count))
                        } label: {
                            Label("discussion_staff_pick_title", systemImage: "person.2")
                        }
                    }
                }
            }
        }
        .navigationTitle("discussion_create_forum")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button {
                    Task { if let id = await model.submit() { shell?.replaceTop(with: LoopRoute.forum(forumId: id)) } }
                } label: {
                    if model.submitting { ProgressView() } else { Text("discussion_create") }
                }
                .buttonStyle(.pulso())
                .disabled(!model.ready)
            }
        }
        .onChange(of: avatarItem) { _, item in
            guard let item else { return }
            avatarItem = nil
            Task { if let photo = await item.loadPhoto() { model.pictures.pickAvatar(photo) } }
        }
        .onChange(of: coverItems) { _, items in
            guard !items.isEmpty else { return }
            coverItems = []
            Task {
                var picked: [(data: Data, mimeType: String)] = []
                for item in items {
                    if let photo = await item.loadPhoto() { picked.append(photo) }
                }
                model.pictures.addBackgrounds(picked)
            }
        }
    }

    /** 封面（第一张背景）铺满顶部，右下角相机；还没有时请作者加一张。 */
    private var cover: some View {
        let coverURL = model.imageURL(model.pictures.backgrounds.first?.imageId)
        return PhotosPicker(selection: $coverItems, maxSelectionCount: max(1, forumBackgroundsMax - model.pictures.backgrounds.count), matching: .images) {
            ZStack(alignment: .bottomTrailing) {
                ZStack {
                    Rectangle().fill(.fill.tertiary)
                    if let first = model.pictures.backgrounds.first {
                        if let data = model.pictures.localData[first.localId], let image = UIImage(data: data) {
                            Image(uiImage: image).resizable().scaledToFill()
                        } else {
                            PulsoRemoteImage(url: coverURL)
                        }
                        if first.status == .uploading { ProgressView() }
                    } else {
                        VStack(spacing: 4) {
                            Image(systemName: "photo.badge.plus").font(.largeTitle)
                            Text("discussion_forum_cover_add").font(.headline)
                            Text(verbatim: localizedFormat("discussion_forum_cover_hint", forumBackgroundsMax)).font(.caption).foregroundStyle(.secondary)
                        }
                        .foregroundStyle(Color.accentColor)
                    }
                }
                .aspectRatio(16 / 9, contentMode: .fit)
                .clipShape(.rect(cornerRadius: 16))
                if !model.pictures.backgrounds.isEmpty {
                    Image(systemName: "camera")
                        .foregroundStyle(.white)
                        .frame(width: 40, height: 40)
                        .background(.black.opacity(0.45), in: .rect(cornerRadius: 10))
                        .padding(12)
                }
            }
        }
        .buttonStyle(.plain)
        .disabled(model.submitting)
        .accessibilityLabel(Text("discussion_forum_cover_add"))
    }

    private func requiredLabel(_ key: LocalizedStringKey) -> some View {
        HStack(spacing: 0) {
            Text(key)
            Text(verbatim: " *").foregroundStyle(.red)
        }
        .textCase(nil)
    }

    private func postingCard(_ symbol: String, _ title: LocalizedStringKey, _ body: LocalizedStringKey, selected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 6) {
                Image(systemName: symbol).font(.title3)
                Text(title).font(.subheadline.weight(.semibold))
                Text(body).font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .padding(12)
            .background(.background.secondary, in: .rect(cornerRadius: 12))
            .overlay { RoundedRectangle(cornerRadius: 12).stroke(selected ? Color.accentColor : .clear, lineWidth: 2) }
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    private var rulesPage: some View {
        Form {
            Section {
                ForumSettingsEditor(settings: $model.settings)
            } footer: {
                Text("discussion_rules_pane_hint")
            }
        }
        .navigationTitle("discussion_rules_title")
    }

    private var staffPage: some View {
        List {
            Section {
                ForEach(model.venueStaff, id: \.profileId) { person in
                    staffRow(person)
                }
                if model.venueStaff.isEmpty {
                    Text("discussion_staff_pick_empty").font(.footnote).foregroundStyle(.secondary)
                }
            } footer: {
                Text("discussion_staff_pick_hint")
            }
        }
        .searchable(text: $model.staffSearch, prompt: Text("discussion_staff_search_placeholder"))
        .navigationTitle("discussion_staff_pick_title")
        .task(id: model.staffSearch) { await model.loadStaff(debounce: !model.staffSearch.isEmpty) }
    }

    private func staffRow(_ person: ForumVenueStaff) -> some View {
        HStack(spacing: 8) {
            PulsoAvatar(url: model.imageURL(person.avatarImageId), size: 36, fallbackText: person.displayName ?? person.profileId)
            VStack(alignment: .leading, spacing: 2) {
                Text(verbatim: person.displayName ?? String(localized: "discussion_unknown_member")).lineLimit(1)
                Text(verbatim: person.venueNames.joined(separator: " · ")).font(.caption2).foregroundStyle(.secondary).lineLimit(1)
            }
            Spacer()
            Picker("discussion_staff_pick_title", selection: Binding(
                get: { model.staff[person.profileId] },
                set: { model.staff[person.profileId] = $0 }
            )) {
                Text("discussion_staff_none").tag(ForumMemberRole?.none)
                ForEach(ForumMemberRole.grantable, id: \.self) { Text($0.labelKey).tag(Optional($0)) }
            }
            .labelsHidden()
        }
    }
}
