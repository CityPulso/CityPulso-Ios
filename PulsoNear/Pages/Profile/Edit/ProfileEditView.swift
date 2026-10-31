import PulsoLinkCore
import PulsoLinkUI
import SwiftUI

/** 点开编辑的一个文字字段（Android `EditField`）；性别的自定义原文也走这里。 */
private enum EditField: String, Identifiable {
    case citypulsoId, displayName, gender, firstName, lastName, city, country, timezone, website, bio

    var id: String { rawValue }

    var title: LocalizedStringKey {
        switch self {
        case .citypulsoId: "profile_identities_citypulso_id_label"
        case .displayName: "profile_field_display_name"
        case .gender: "profile_edit_gender_custom"
        case .firstName: "profile_field_first_name"
        case .lastName: "profile_field_last_name"
        case .city: "profile_field_city"
        case .country: "profile_field_country"
        case .timezone: "profile_field_timezone"
        case .website: "profile_field_website"
        case .bio: "profile_field_bio"
        }
    }

    var path: WritableKeyPath<ProfileEditForm, String> {
        switch self {
        case .citypulsoId: \.citypulsoId
        case .displayName: \.displayName
        case .gender: \.gender
        case .firstName: \.firstName
        case .lastName: \.lastName
        case .city: \.city
        case .country: \.country
        case .timezone: \.timezone
        case .website: \.website
        case .bio: \.bio
        }
    }

    var limit: Int {
        switch self {
        case .citypulsoId: 64
        case .displayName: 150
        case .bio: 5000
        default: ProfileEditModel.shortFieldMax
        }
    }

    /** 草稿哪里不对（Android `fieldError`）；没问题 nil。 */
    func error(_ draft: String) -> String? {
        let trimmed = draft.trimmingCharacters(in: .whitespaces)
        switch self {
        case .citypulsoId:
            return (try? citypulsoIdPattern.wholeMatch(in: trimmed)) == nil ? String(localized: "profile_identities_citypulso_id_rule") : nil
        case .website where !trimmed.isEmpty && !trimmed.hasPrefix("http://") && !trimmed.hasPrefix("https://"):
            return String(localized: "profile_edit_website_invalid")
        default:
            return draft.count > limit ? localizedFormat("profile_edit_max_len", limit) : nil
        }
    }
}

/**
 * 编辑资料（对应 Android `ProfileEditScreen`）：分组卡片里一行一项（图标、标签、当前值、箭头），点开再改；
 * 文字字段弹一个小面板，性别和语言是菜单，生日是滚轮。离开时自动保存。
 */
struct ProfileEditView: View {
    @State private var model = ProfileEditModel()
    @State private var pickingActivities = false
    @State private var editing: EditField?
    @State private var draft = ""
    @State private var pickingBirthday = false
    @State private var birthdayDraft = Date.now
    @Environment(\.dismiss) private var dismiss
    @Environment(\.pulsoPalette) private var palette
    @Environment(\.locale) private var locale

    var body: some View {
        Group {
            if model.loaded {
                content
            } else if let error = model.loadError {
                PulsoLoadErrorView(error) { Task { await model.refresh() } }
            } else {
                ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .navigationTitle("profile_edit_title")
        .navigationBarTitleDisplayMode(.inline)
        // 改了但无效时不能返回（Android 同样留在页面上），先改对；有效的修改在离开时自动保存。
        .navigationBarBackButtonHidden(model.isDirty && !model.canSave)
        .sheet(isPresented: $pickingActivities) {
            FavoriteActivityPicker(selected: $model.form.favoriteActivities) { pickingActivities = false }
        }
        .sheet(item: $editing) { field in fieldSheet(field) }
        .sheet(isPresented: $pickingBirthday) { birthdaySheet }
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                NavigationLink(value: NearRoute.identities) {
                    Label("profile_identities_title", systemImage: "person.text.rectangle")
                }
            }
            if model.isDirty {
                ToolbarItem(placement: .confirmationAction) {
                    Button(model.saving ? "profile_edit_saving" : "profile_edit_save", role: .confirm) {
                        Task { if await model.saveIfNeeded() { dismiss() } }
                    }
                    .disabled(model.saving || !model.canSave)
                }
            }
        }
        .task { await model.observe() }
        .task { await model.refresh() }
        .avatarUploadSheet(model.avatar)
    }

    private var content: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: PulsoSpace.s4) {
                Text("profile_edit_hint")
                    .font(.footnote)
                    .foregroundStyle(palette.secondaryText)
                    .padding(.horizontal, PulsoSpace.s1)
                PulsoSection {
                    Button { model.avatar.open() } label: {
                        PulsoSectionRow("profile_edit_avatar_label", systemImage: "camera") {
                            PulsoAvatar(url: model.avatarURL, size: 40, systemImage: "person", fallbackText: model.form.displayName)
                        }
                    }
                    .buttonStyle(.pulsoRow)
                    valueRow(.bio, systemImage: "text.alignleft", placeholder: "profile_edit_placeholder_bio", multiline: true)
                }
                // 喜欢的活动：选了的显示成小标签（还没选显示提示），点这一行打开选择面板。
                PulsoSection {
                    Button { pickingActivities = true } label: {
                        HStack(spacing: PulsoSpace.s3) {
                            VStack(alignment: .leading, spacing: PulsoSpace.s2) {
                                Text("profile_field_favorite_activities").font(.subheadline.weight(.semibold)).foregroundStyle(palette.text)
                                if model.form.favoriteActivities.isEmpty {
                                    Text("profile_favorite_activities_empty").font(.subheadline).foregroundStyle(palette.secondaryText)
                                } else {
                                    FavoriteActivityChips(activities: model.form.favoriteActivities)
                                }
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                            chevron
                        }
                        .padding(PulsoSpace.s4)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.pulsoRow)
                }
                PulsoSection {
                    valueRow(.citypulsoId, systemImage: "at")
                    valueRow(.displayName, systemImage: "person.text.rectangle")
                    genderRow
                    Button {
                        birthdayDraft = Birthday.date(model.form.birthday) ?? Calendar.current.date(byAdding: .year, value: -25, to: .now) ?? .now
                        pickingBirthday = true
                    } label: {
                        row(
                            "profile_field_birthday",
                            systemImage: "birthday.cake",
                            value: Birthday.date(model.form.birthday).map { $0.formatted(Date.FormatStyle(date: .abbreviated, time: .omitted, locale: locale, timeZone: .gmt)) },
                            placeholder: "profile_edit_placeholder_birthday"
                        )
                    }
                    .buttonStyle(.pulsoRow)
                    languageRow
                }
                PulsoSection {
                    valueRow(.firstName, systemImage: "person")
                    valueRow(.lastName, systemImage: "person.fill")
                }
                PulsoSection {
                    valueRow(.city, systemImage: "mappin.and.ellipse")
                    valueRow(.country, systemImage: "globe")
                    valueRow(.timezone, systemImage: "clock")
                    valueRow(.website, systemImage: "link")
                }
                PulsoSection {
                    NavigationLink(value: NearRoute.backgrounds) {
                        row("profile_backgrounds_title", systemImage: "photo.on.rectangle", value: String(localized: "profile_edit_manage_backgrounds"))
                    }
                    .buttonStyle(.pulsoRow)
                }
            }
            .padding(PulsoSpace.s4)
        }
        .disabled(model.saving)
        .onDisappear {
            // 系统返回手势也会走到这里：改了就在后台保存，不丢用户的修改。
            Task { await model.saveIfNeeded() }
        }
    }

    private var chevron: some View {
        Image(systemName: "chevron.right")
            .font(.footnote.weight(.semibold))
            .foregroundStyle(palette.secondaryText)
            .accessibilityHidden(true)
    }

    /** 一行：图标、固定宽的标签、当前值（没填是灰色提示）、箭头（Android `EditValueRow`）。 */
    private func row(
        _ label: LocalizedStringKey,
        systemImage: String,
        value: String?,
        placeholder: LocalizedStringKey = "profile_edit_placeholder_unset",
        multiline: Bool = false
    ) -> some View {
        HStack(alignment: multiline ? .top : .center, spacing: PulsoSpace.s3) {
            Image(systemName: systemImage)
                .font(.system(size: 17))
                .foregroundStyle(palette.secondaryText)
                .frame(width: 20, height: 20)
            Text(label)
                .foregroundStyle(palette.text)
                .lineLimit(1)
                .frame(width: 92, alignment: .leading)
            Group {
                if let value, !value.isEmpty {
                    Text(verbatim: value).foregroundStyle(palette.text)
                } else {
                    Text(placeholder).foregroundStyle(palette.secondaryText)
                }
            }
            .lineLimit(multiline ? 3 : 1)
            .frame(maxWidth: .infinity, alignment: .leading)
            chevron
        }
        .font(.body)
        .padding(PulsoSpace.s4)
        .contentShape(Rectangle())
    }

    private func valueRow(_ field: EditField, systemImage: String, placeholder: LocalizedStringKey = "profile_edit_placeholder_unset", multiline: Bool = false) -> some View {
        Button {
            draft = model.form[keyPath: field.path]
            editing = field
        } label: {
            row(field.title, systemImage: systemImage, value: model.form[keyPath: field.path], placeholder: placeholder, multiline: multiline)
        }
        .buttonStyle(.pulsoRow)
    }

    /** 预设四项 + 自定义；自定义打开输入面板，输入的原文直接保存。 */
    private var genderRow: some View {
        let gender = model.form.gender.trimmingCharacters(in: .whitespaces)
        let preset = GenderOption.preset(gender)
        return Menu {
            Picker("profile_field_gender", selection: Binding<String>(
                get: { preset?.rawValue ?? (gender.isEmpty ? "" : "custom") },
                set: { value in
                    if value == "custom" {
                        draft = preset == nil ? model.form.gender : ""
                        editing = .gender
                    } else {
                        model.form.gender = value
                    }
                }
            )) {
                ForEach(GenderOption.allCases) { Text($0.labelKey).tag($0.rawValue) }
                Text("profile_edit_gender_custom").tag("custom")
            }
        } label: {
            row("profile_field_gender", systemImage: "figure.stand.dress.line.vertical.figure", value: preset.map { String(localized: $0.labelResource) } ?? gender)
        }
        .buttonStyle(.pulsoRow)
    }

    private var languageRow: some View {
        Menu {
            Picker("profile_field_language", selection: $model.form.profileLanguage) {
                ForEach(PulsoLanguage.allCases, id: \.self) { Text($0.profileLabelKey).tag($0) }
            }
        } label: {
            row("profile_field_language", systemImage: "translate", value: String(localized: model.form.profileLanguage.profileLabelResource))
        }
        .buttonStyle(.pulsoRow)
    }

    /** 改一个文字字段（Android `ProfileEditFieldDialog`）：输入框 + 错误，确定写回表单，离开页面时一起保存。 */
    private func fieldSheet(_ field: EditField) -> some View {
        let error = field.error(draft)
        return NavigationStack {
            VStack(alignment: .leading, spacing: PulsoSpace.s3) {
                if field == .bio {
                    TextField(field.title, text: $draft, prompt: Text("profile_edit_placeholder_bio"), axis: .vertical)
                        .lineLimit(4...10)
                        .padding(PulsoSpace.s3)
                        .overlay { palette.textAreaShape.stroke(error == nil ? palette.outline : palette.error, lineWidth: pulsoHairline) }
                    if let error { Text(verbatim: error).font(.caption).foregroundStyle(palette.error) }
                } else {
                    PulsoTextField(
                        field.title,
                        text: $draft,
                        prompt: field == .gender ? String(localized: "profile_edit_gender_custom_placeholder") : nil,
                        errorText: error
                    )
                    .textInputAutocapitalization(field == .citypulsoId || field == .website ? .never : .sentences)
                    .autocorrectionDisabled(field == .citypulsoId || field == .website)
                    .keyboardType(field == .website ? .URL : .default)
                }
                Spacer(minLength: 0)
            }
            .padding(PulsoSpace.s4)
            .navigationTitle(field.title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(role: .cancel) { editing = nil }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(role: .confirm) {
                        model.form[keyPath: field.path] = field == .citypulsoId ? draft.trimmingCharacters(in: .whitespaces) : draft
                        editing = nil
                    } label: {
                        Image(systemName: "checkmark")
                    }
                    .disabled(error != nil)
                }
            }
        }
        .presentationDetents(field == .bio ? [.medium, .large] : [.height(220)])
    }

    private var birthdaySheet: some View {
        NavigationStack {
            DatePicker(selection: $birthdayDraft, in: ...Date.now, displayedComponents: .date) { EmptyView() }
                .datePickerStyle(.wheel)
                .labelsHidden()
                .environment(\.timeZone, .gmt)
                .frame(maxWidth: .infinity)
                .navigationTitle("profile_field_birthday")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button(role: .cancel) { pickingBirthday = false }
                    }
                    ToolbarItem(placement: .confirmationAction) {
                        Button(role: .confirm) {
                            model.form.birthday = Birthday.day(birthdayDraft)
                            pickingBirthday = false
                        } label: {
                            Image(systemName: "checkmark")
                        }
                    }
                }
        }
        .presentationDetents([.height(320)])
    }
}
