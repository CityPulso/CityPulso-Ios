import PulsoLinkCore
import PulsoLinkUI
import SwiftUI

/**
 * 发起活动页（Android `CreateScreen`）：先选运动，再走四步表单。进来时有草稿就问要不要接着填，离开时有没存的
 * 内容就问要不要存；发布成功后问要不要顺手发个帖子。不是球友身份时只说明原因。
 */
struct CreateEventView: View {
    @State private var model = CreateEventModel()
    @Environment(\.dismiss) private var dismiss
    /** 被推进来的（不是底栏根页）才有离开页面这一步。 */
    @Environment(\.isPresented) private var isPresented
    @Environment(PulsoShellNavigator.self) private var shell: PulsoShellNavigator?

    var body: some View {
        content
            .navigationTitle(Text("shell_dest_create"))
            .navigationBarTitleDisplayMode(.inline)
            .navigationBarBackButtonHidden(true)
            .toolbar {
                if model.step == .form || isPresented {
                    ToolbarItem(placement: .topBarLeading) {
                        Button {
                            if model.back() { dismiss() }
                        } label: {
                            Image(systemName: "chevron.backward")
                        }
                        .disabled(model.isSubmitting)
                    }
                }
                if model.isPulser, model.step == .form {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button("create_draft_save") { model.saveDraft() }.disabled(model.isSubmitting)
                    }
                }
            }
            .task { await model.observe() }
            .alert("create_draft_restore_title", isPresented: $model.draftPrompt) {
                Button("create_draft_restore_confirm") { model.restoreDraft() }
                Button("create_draft_restore_discard", role: .destructive) { model.discardDraft() }
            } message: {
                Text("create_draft_restore_body")
            }
            .alert("create_draft_leave_title", isPresented: $model.leavePrompt) {
                Button("create_draft_save") {
                    model.saveDraftAndLeave()
                    dismiss()
                }
                Button("create_draft_leave_discard", role: .destructive) {
                    model.leavePrompt = false
                    dismiss()
                }
                Button("event_detail_dialog_cancel", role: .cancel) {}
            } message: {
                Text("create_draft_leave_body")
            }
            .alert("create_post_prompt_title", isPresented: createdBinding, presenting: model.createdEvent) { created in
                Button("create_post_prompt_confirm") { postAbout(created) }
                Button("create_post_prompt_skip", role: .cancel) { open(created) }
            } message: { _ in
                Text("create_post_prompt_body")
            }
    }

    @ViewBuilder
    private var content: some View {
        if !model.profileReady {
            Color.clear
        } else if !model.isPulser {
            Text("event_create_pulser_required")
                .multilineTextAlignment(.center)
                .padding()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            switch model.step {
            case .sport:
                CreateSportPickView { sport in model.selectSport(sport, defaultEquipment: defaultEquipmentDrafts(sport)) }
            case .form:
                CreateWizardView(model: model)
            }
        }
    }

    private var createdBinding: Binding<Bool> {
        Binding(get: { model.createdEvent != nil }, set: { if !$0 { model.createdEvent = nil } })
    }

    /** 「去看看」：直接打开刚发布的活动。 */
    private func open(_ created: CreatedEventPrompt) {
        model.createdEvent = nil
        shell?.push(LoopRoute.event(sport: created.sport, eventId: created.eventId))
    }

    /** 「发个帖子」：论坛发帖在第 11 组移植。 */
    private func postAbout(_ created: CreatedEventPrompt) {
        model.createdEvent = nil
        shell?.push(LoopRoute.comingSoon(title: "create_post_prompt_confirm", systemImage: "square.and.pencil"))
    }
}

/** 各运动的默认装备要求，用发起人的语言命名（WEB `*_EQUIPMENT_DEFAULTS`）。 */
func defaultEquipmentDrafts(_ sport: LoopSport) -> [EquipmentDraft] {
    equipmentPresets(sport, only: true)
}

/** 这项运动可点选的装备预设；[only] 为 true 时只要默认带上的那几条。 */
func equipmentPresets(_ sport: LoopSport, only defaults: Bool = false) -> [EquipmentDraft] {
    func drafts<P: CaseIterable>(_ all: [P], _ chosen: [P], icon: (P) -> String, label: (P) -> String.LocalizationValue) -> [EquipmentDraft] {
        (defaults ? chosen : all).map { EquipmentDraft(icon: icon($0), name: String(localized: label($0))) }
    }
    return switch sport {
    case .badminton: drafts(BadmintonEquipmentPreset.allCases, badmintonEquipmentDefaults, icon: \.icon, label: \.labelResource)
    case .tennis: drafts(TennisEquipmentPreset.allCases, tennisEquipmentDefaults, icon: \.icon, label: \.labelResource)
    case .pickleball: drafts(PickleballEquipmentPreset.allCases, pickleballEquipmentDefaults, icon: \.icon, label: \.labelResource)
    case .basketball: drafts(BasketballEquipmentPreset.allCases, basketballEquipmentDefaults, icon: \.icon, label: \.labelResource)
    case .football: drafts(FootballEquipmentPreset.allCases, footballEquipmentDefaults, icon: \.icon, label: \.labelResource)
    case .baseball: drafts(BaseballEquipmentPreset.allCases, baseballEquipmentDefaults, icon: \.icon, label: \.labelResource)
    case .golf: drafts(GolfEquipmentPreset.allCases, golfEquipmentDefaults, icon: \.icon, label: \.labelResource)
    case .hiking: drafts(HikingEquipmentPreset.allCases, hikingEquipmentDefaults, icon: \.icon, label: \.labelResource)
    case .fishing: drafts(FishingEquipmentPreset.allCases, fishingEquipmentDefaults, icon: \.icon, label: \.labelResource)
    case .ski: drafts(SkiEquipmentPreset.allCases, skiEquipmentDefaults, icon: \.icon, label: \.labelResource)
    case .tableTennis: drafts(TableTennisEquipmentPreset.allCases, tableTennisEquipmentDefaults, icon: \.icon, label: \.labelResource)
    }
}
