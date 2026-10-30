import PulsoLinkCore
import PulsoLinkUI
import SwiftUI

/**
 * 喜欢的活动选择面板（Android `FavoriteActivityPicker`）：每种活动一行，可以多选，点完成收起。
 * 资料编辑页每点一下就进表单；资料页在本地选好，点完成才保存。
 */
struct FavoriteActivityPicker: View {
    @Binding var selected: [FavoriteActivity]
    let onDone: () -> Void

    var body: some View {
        NavigationStack {
            List {
                Section {
                    ForEach(FavoriteActivity.ordered, id: \.self) { activity in
                        Button {
                            selected = toggled(selected, activity, order: FavoriteActivity.ordered)
                        } label: {
                            HStack {
                                Label {
                                    Text(activity.kind.labelKey)
                                } icon: {
                                    Image(activity.kind.iconAsset).resizable().frame(width: 22, height: 22)
                                }
                                Spacer()
                                if selected.contains(activity) { Image(systemName: "checkmark").foregroundStyle(.tint) }
                            }
                        }
                        .foregroundStyle(.primary)
                    }
                } footer: {
                    Text("profile_favorite_activities_hint")
                }
            }
            .navigationTitle("profile_field_favorite_activities")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button(role: .confirm, action: onDone) { Text("pulso_ui_done", bundle: .pulsoLinkUI) }
                }
            }
        }
        .presentationDetents([.medium, .large])
    }
}
