import PulsoLinkCore
import PulsoLinkUI
import SwiftUI

/**
 * 喜欢的运动选择面板（Android `FavoriteSportPicker`）：每个运动一行，可以多选，点完成收起。
 * 资料编辑页每点一下就进表单；资料页在本地选好，点完成才保存（[onDone] 收到最终选择）。
 */
struct FavoriteSportPicker: View {
    @Binding var selected: [FavoriteSport]
    let onDone: () -> Void

    var body: some View {
        NavigationStack {
            List {
                Section {
                    ForEach(FavoriteSport.allCases, id: \.self) { sport in
                        Button {
                            selected = toggled(selected, sport, order: FavoriteSport.allCases)
                        } label: {
                            HStack {
                                Label {
                                    Text(sport.loopSport.labelKey)
                                } icon: {
                                    Image(sport.loopSport.iconAsset).resizable().frame(width: 22, height: 22)
                                }
                                Spacer()
                                if selected.contains(sport) { Image(systemName: "checkmark").foregroundStyle(.tint) }
                            }
                        }
                        .foregroundStyle(.primary)
                    }
                } footer: {
                    Text("profile_favorite_sports_hint")
                }
            }
            .navigationTitle("profile_field_favorite_sports")
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
