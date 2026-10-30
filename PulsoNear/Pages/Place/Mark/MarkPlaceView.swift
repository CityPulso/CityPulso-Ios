import PulsoLinkCore
import PulsoLinkUI
import SwiftUI

/**
 * 标记地图上缺的地点（Android `MarkPlaceScreen`，WEB `/panel/account/places/mark`）：名字、类型、位置（地图预览，
 * 点开选点页）、照片、备注、联系邮箱，可选电话。被拒的那条带着审核意见重新提交。
 */
struct MarkPlaceView: View {
    @State private var model: MarkPlaceModel
    @State private var pickingLocation = false
    @Environment(\.dismiss) private var dismiss

    init(requestId: String? = nil, latitude: Double? = nil, longitude: Double? = nil) {
        _model = State(initialValue: MarkPlaceModel(requestId: requestId, latitude: latitude, longitude: longitude))
    }

    var body: some View {
        content
            .navigationTitle(Text((model.resubmitting ? "place_mark_resubmit_title" : "place_mark_title") as LocalizedStringKey))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                if !model.unavailable, !model.loading {
                    ToolbarItem(placement: .confirmationAction) {
                        Button {
                            Task { if await model.submit() { dismiss() } }
                        } label: {
                            if model.submitting {
                                ProgressView()
                            } else {
                                Text((model.resubmitting ? "place_mark_resubmit" : "place_mark_submit") as LocalizedStringKey)
                            }
                        }
                        .disabled(model.submitting || model.photosUploading)
                    }
                }
            }
            .sheet(isPresented: $pickingLocation) {
                NavigationStack {
                    LocationPickView(
                        persistToExplore: false,
                        showsClose: true,
                        confirmText: "place_mark_location_confirm",
                        onPicked: { lat, lng, label in model.pickLocation(lat, lng, label: label) }
                    )
                }
            }
            .task { await model.observe() }
    }

    @ViewBuilder
    private var content: some View {
        if model.loading {
            ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if model.unavailable {
            ContentUnavailableView {
                Label("place_mark_unavailable", systemImage: "mappin.slash")
            } description: {
                Text("place_mark_unavailable_hint")
            }
        } else {
            form
        }
    }

    private var form: some View {
        let errors = model.showErrors ? model.errors : MarkPlaceErrors()
        let locked = model.submitting
        return Form {
            Section {
                Text(model.resubmitting ? "place_mark_resubmit_subtitle" : "place_mark_subtitle")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                if let note = model.reviewNote, !note.isEmpty {
                    Label { Text(verbatim: localizedFormat("place_mark_previous_note", note)) } icon: { Image(systemName: "exclamationmark.bubble") }
                        .font(.subheadline)
                        .foregroundStyle(.orange)
                }
            }
            Section {
                TextField("place_mark_name_placeholder", text: $model.name)
                FieldError(errors.name)
            } header: {
                RequiredHeader("place_mark_name")
            }
            Section {
                Picker(selection: $model.type) {
                    Text("place_mark_type_placeholder").tag(BuildingType?.none)
                    ForEach(model.placeTypes, id: \.self) { type in
                        Label(type.labelKey, systemImage: BuildingTypeVisual.of(type.rawValue).systemImage).tag(BuildingType?.some(type))
                    }
                } label: {
                    Text("place_mark_type")
                }
                if let type = model.type {
                    Text(type.placeHintKey).font(.caption).foregroundStyle(.secondary)
                }
                FieldError(errors.type)
            } header: {
                RequiredHeader("place_mark_type")
            }
            Section {
                if let lat = model.latitude, let lng = model.longitude {
                    NearMapView(map: model.map, initialCenter: (lat, lng), initialZoom: 15, camera: MapCameraRequest(id: 1, latitude: lat, longitude: lng, zoom: 15))
                        .allowsHitTesting(false)
                        .overlay {
                            Image(systemName: "mappin")
                                .font(.system(size: 32, weight: .semibold))
                                .foregroundStyle(Color.accentColor)
                                .offset(y: -16)
                        }
                        .frame(height: 160)
                        .clipShape(.rect(cornerRadius: 12))
                        .listRowInsets(EdgeInsets(top: 8, leading: 8, bottom: 8, trailing: 8))
                        .onTapGesture { pickingLocation = true }
                }
                Button { pickingLocation = true } label: {
                    LabeledContent {
                        Image(systemName: "chevron.right").foregroundStyle(.tertiary)
                    } label: {
                        Text(verbatim: model.address.isEmpty ? String(localized: "place_mark_location_empty") : model.address)
                            .foregroundStyle(model.address.isEmpty ? Color.secondary : Color.primary)
                    }
                }
                .disabled(locked)
                FieldError(errors.address)
            } header: {
                RequiredHeader("place_mark_location")
            }
            Section {
                ActivityPhotoPicker(
                    photos: model.photos,
                    localData: model.photoData,
                    imageURL: { model.imageURL($0) },
                    onAdd: { model.addPhotos($0) },
                    onRemove: { model.removePhoto($0) },
                    onSetCover: { model.setCover($0) },
                    onRetry: { model.retryPhoto($0) },
                    enabled: !locked,
                    max: placePhotosMax
                )
                .listRowInsets(EdgeInsets(top: 12, leading: 12, bottom: 12, trailing: 12))
                FieldError(errors.photos)
            } header: {
                RequiredHeader("place_mark_photos")
            } footer: {
                Text("place_mark_photos_hint")
            }
            Section {
                TextField("place_mark_note_placeholder", text: $model.note, axis: .vertical)
                    .lineLimit(3 ... 8)
                FieldError(errors.note)
            } header: {
                HStack {
                    Text("place_mark_note")
                    Spacer()
                    Text(verbatim: localizedFormat("place_mark_counter", model.note.count, placeNoteMax)).monospacedDigit()
                }
            } footer: {
                Text("place_mark_note_hint")
            }
            Section {
                TextField("place_mark_email_placeholder", text: $model.email)
                    .keyboardType(.emailAddress)
                    .textContentType(.emailAddress)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                FieldError(errors.email)
            } header: {
                RequiredHeader("place_mark_email")
            } footer: {
                Text("place_mark_email_hint")
            }
            Section {
                if model.showPhone {
                    HStack {
                        TextField("place_mark_phone_placeholder", text: $model.phone)
                            .keyboardType(.phonePad)
                            .textContentType(.telephoneNumber)
                        Button { model.removePhone() } label: { Image(systemName: "xmark.circle.fill").foregroundStyle(.tertiary) }
                            .buttonStyle(.borderless)
                            .disabled(locked)
                            .accessibilityLabel(Text("place_mark_remove_phone"))
                    }
                    FieldError(errors.phone)
                } else {
                    Button { model.addPhone() } label: { Label("place_mark_add_phone", systemImage: "plus") }
                        .disabled(locked)
                }
            } header: {
                Text("place_mark_other_info")
            } footer: {
                Text((model.showPhone ? "place_mark_phone_hint" : "place_mark_other_info_hint") as LocalizedStringKey)
            }
        }
        .disabled(locked)
        .scrollDismissesKeyboard(.interactively)
    }
}

/** 必填项的标题：后面一个红色 *。 */
private struct RequiredHeader: View {
    let key: LocalizedStringKey

    init(_ key: LocalizedStringKey) {
        self.key = key
    }

    var body: some View {
        Text(key) + Text(verbatim: " *").foregroundStyle(.red)
    }
}

private struct FieldError: View {
    let text: String?

    init(_ text: String?) {
        self.text = text
    }

    var body: some View {
        if let text {
            Text(verbatim: text).font(.footnote).foregroundStyle(.red)
        }
    }
}

extension BuildingType {
    /** 每种地点类型下面那一行说明（什么算这一类）。 */
    var placeHintKey: LocalizedStringKey {
        switch self {
        case .activityTypesVenue: "place_type_activity_types_venue_hint"
        case .outdoorSpace: "place_type_outdoor_space_hint"
        case .park: "place_type_park_hint"
        case .leisureVenue: "building_type_leisure_venue"
        }
    }
}
