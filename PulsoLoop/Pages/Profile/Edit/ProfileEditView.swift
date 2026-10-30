import PulsoLinkCore
import PulsoLinkUI
import SwiftUI

/** 编辑资料（对应 Android `ProfileEditScreen`）：系统表单，字段直接在行内编辑；离开时自动保存。 */
struct ProfileEditView: View {
    @State private var model = ProfileEditModel()
    /** 性别选了「自定义」（或服务端存的是自定义原文）。 */
    @State private var customGender = false
    @State private var pickingSports = false
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        Group {
            if model.loaded {
                form
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
        .sheet(isPresented: $pickingSports) {
            FavoriteSportPicker(selected: $model.form.favoriteSports) { pickingSports = false }
        }
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                NavigationLink(value: LoopRoute.identities) {
                    Label("profile_overview_open_identities", systemImage: "person.text.rectangle")
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
        .onChange(of: model.loaded, initial: true) { _, loaded in
            guard loaded else { return }
            let gender = model.form.gender.trimmingCharacters(in: .whitespaces)
            customGender = !gender.isEmpty && GenderOption.preset(gender) == nil
        }
        .avatarUploadSheet(model.avatar)
    }

    private var form: some View {
        Form {
            Section {
                Button { model.avatar.open() } label: {
                    HStack {
                        PulsoAvatar(url: model.avatarURL, size: 56, systemImage: "person", fallbackText: model.form.displayName)
                        VStack(alignment: .leading) {
                            Text("profile_edit_avatar_label").foregroundStyle(.primary)
                            Text("profile_edit_avatar_hint").font(.footnote).foregroundStyle(.secondary)
                        }
                    }
                }
                TextField("profile_field_bio", text: $model.form.bio, prompt: Text("profile_edit_placeholder_bio"), axis: .vertical)
                    .lineLimit(3...8)
            } footer: {
                Text("profile_edit_hint")
            }

            // 喜欢的运动：选了的显示成小标签（还没选显示提示），点这一行打开选择面板。
            Section {
                Button { pickingSports = true } label: {
                    HStack {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("profile_field_favorite_sports").font(.subheadline.weight(.semibold))
                            if model.form.favoriteSports.isEmpty {
                                Text("profile_favorite_sports_empty").foregroundStyle(.secondary)
                            } else {
                                FavoriteSportChips(sports: model.form.favoriteSports)
                            }
                        }
                        Spacer(minLength: 0)
                        Image(systemName: "chevron.right").font(.footnote.weight(.semibold)).foregroundStyle(.tertiary)
                    }
                }
                .foregroundStyle(.primary)
            }

            Section {
                field("profile_identities_citypulso_id_label", text: $model.form.citypulsoId, error: model.citypulsoIdError ? "profile_identities_citypulso_id_rule" : nil)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                field("profile_field_display_name", text: $model.form.displayName, error: model.displayNameError ? maxLength(150) : nil)
                genderPicker
                birthdayRow
                Picker("profile_field_language", selection: $model.form.profileLanguage) {
                    Text("profile_lang_zh").tag(PulsoLanguage.zh)
                    Text("profile_lang_zh_hant").tag(PulsoLanguage.zhHant)
                    Text("profile_lang_en").tag(PulsoLanguage.en)
                    Text("profile_lang_fr").tag(PulsoLanguage.fr)
                }
            }

            Section {
                field("profile_field_first_name", text: $model.form.firstName, error: shortError(model.form.firstName))
                    .textContentType(.givenName)
                field("profile_field_last_name", text: $model.form.lastName, error: shortError(model.form.lastName))
                    .textContentType(.familyName)
            }

            Section {
                field("profile_field_city", text: $model.form.city, error: shortError(model.form.city))
                    .textContentType(.addressCity)
                field("profile_field_country", text: $model.form.country, error: shortError(model.form.country))
                    .textContentType(.countryName)
                field("profile_field_timezone", text: $model.form.timezone, error: shortError(model.form.timezone))
                field("profile_field_website", text: $model.form.website, error: model.websiteError ? "profile_edit_website_invalid" : shortError(model.form.website))
                    .keyboardType(.URL)
                    .textContentType(.URL)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
            }

            Section {
                NavigationLink(value: LoopRoute.backgrounds) {
                    LabeledContent("profile_backgrounds_title") { Text("profile_edit_manage_backgrounds") }
                }
            }
        }
        .disabled(model.saving)
        .onDisappear {
            // 系统返回手势也会走到这里：改了就在后台保存，不丢用户的修改。
            Task { await model.saveIfNeeded() }
        }
    }

    private func field(_ label: LocalizedStringKey, text: Binding<String>, error: LocalizedStringKey?) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            LabeledContent(label) {
                TextField(label, text: text, prompt: Text("profile_edit_placeholder_unset"))
                    .multilineTextAlignment(.trailing)
            }
            if let error {
                Text(error).font(.footnote).foregroundStyle(.red)
            }
        }
    }

    private func shortError(_ value: String) -> LocalizedStringKey? {
        value.count > ProfileEditModel.shortFieldMax ? maxLength(ProfileEditModel.shortFieldMax) : nil
    }

    private func maxLength(_ count: Int) -> LocalizedStringKey {
        LocalizedStringKey(localizedFormat("profile_edit_max_len", count))
    }

    /** 预设四项 + 自定义；自定义时下面多一行输入框，输入的原文直接保存。 */
    @ViewBuilder
    private var genderPicker: some View {
        Picker("profile_field_gender", selection: Binding<String>(
            get: { customGender ? "custom" : GenderOption.preset(model.form.gender)?.rawValue ?? "" },
            set: { value in
                customGender = value == "custom"
                if !customGender { model.form.gender = value }
            }
        )) {
            Text("profile_edit_placeholder_unset").tag("")
            ForEach(GenderOption.allCases) { Text($0.labelKey).tag($0.rawValue) }
            Text("profile_edit_gender_custom").tag("custom")
        }
        if customGender {
            TextField("profile_edit_gender_custom", text: $model.form.gender, prompt: Text("profile_edit_gender_custom_placeholder"))
        }
    }

    @ViewBuilder
    private var birthdayRow: some View {
        if let date = Birthday.date(model.form.birthday) {
            DatePicker(
                "profile_field_birthday",
                selection: Binding(get: { date }, set: { model.form.birthday = Birthday.day($0) }),
                in: ...Date.now,
                displayedComponents: .date
            )
            .environment(\.timeZone, .gmt)
        } else {
            Button { model.form.birthday = Birthday.day(Calendar.current.date(byAdding: .year, value: -25, to: .now) ?? .now) } label: {
                LabeledContent("profile_field_birthday") { Text("profile_edit_placeholder_unset") }
            }
            .foregroundStyle(.primary)
        }
    }
}
