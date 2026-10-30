import PulsoLinkCore
import PulsoLinkUI
import SwiftUI

/**
 * 发起活动页（Android `CreateScreen`）：先选活动类型，再走四步表单。进来时有草稿就问要不要接着填，离开时有没存的
 * 内容就问要不要存；发布成功后问要不要顺手发个帖子。不是球友身份时只说明原因。
 */
struct CreateActivityView: View {
    @State private var model = CreateActivityModel()
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
                Button("activity_detail_dialog_cancel", role: .cancel) {}
            } message: {
                Text("create_draft_leave_body")
            }
            .alert("create_post_prompt_title", isPresented: createdBinding, presenting: model.createdActivity) { created in
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
            Text("activity_create_pulser_required")
                .multilineTextAlignment(.center)
                .padding()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            switch model.step {
            case .activityType:
                CreateActivityTypePickView { activityType in model.selectActivityType(activityType) }
            case .form:
                CreateWizardView(model: model)
            }
        }
    }

    private var createdBinding: Binding<Bool> {
        Binding(get: { model.createdActivity != nil }, set: { if !$0 { model.createdActivity = nil } })
    }

    /** 「去看看」：直接打开刚发布的活动。 */
    private func open(_ created: CreatedActivityPrompt) {
        model.createdActivity = nil
        shell?.push(NearRoute.activity(activityType: created.activityType, activityId: created.activityId))
    }

    /** 「发个帖子」：论坛那组移植前先进占位页（Android `openPostCreate`）。 */
    private func postAbout(_ created: CreatedActivityPrompt) {
        model.createdActivity = nil
        shell?.push(NearRoute.comingSoon(title: "shell_dest_forum", systemImage: "text.bubble"))
    }
}
