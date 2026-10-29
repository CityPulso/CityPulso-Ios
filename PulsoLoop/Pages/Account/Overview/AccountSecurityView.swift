import PulsoLinkCore
import PulsoLinkUI
import SwiftUI

/** 账户安全（对应 Android `AccountSecurityScreen`）：登录与恢复、安全、账户三组。 */
struct AccountSecurityView: View {
    @State private var emails = EmailListModel()

    var body: some View {
        Form {
            Section("account_security_section_access") {
                NavigationLink(value: LoopRoute.emails) {
                    LabeledContent("account_security_emails") {
                        Text(verbatim: emailSummary)
                    }
                }
                NavigationLink(value: LoopRoute.changePassword) {
                    LabeledContent("account_security_password") {
                        Text("account_security_password_enabled")
                    }
                }
                comingSoonRow("account_security_phone", value: "account_security_phone_not_added")
                LabeledContent("account_security_signin_methods") {
                    Text("account_security_signin_methods_password")
                }
            }

            Section("account_security_section_security") {
                comingSoonRow("account_security_two_step", value: "account_security_two_step_off")
                comingSoonRow("account_security_sessions", value: "account_security_sessions_placeholder")
            }

            Section("account_security_section_account") {
                Button("account_security_delete_account", role: .destructive) {
                    PulsoMessageCenter.shared.info("account_security_coming_soon")
                }
            }
        }
        .navigationTitle("account_security_title")
        .refreshable { await emails.load() }
        .task { await emails.observe() }
    }

    private var emailSummary: String {
        guard let primary = emails.primaryEmail else {
            return emails.emails == nil ? "" : String(localized: "account_security_emails_none")
        }
        return primary.isPrimary ? localizedFormat("account_security_emails_primary_summary", primary.email) : primary.email
    }

    private func comingSoonRow(_ label: LocalizedStringKey, value: LocalizedStringKey) -> some View {
        Button {
            PulsoMessageCenter.shared.info("account_security_coming_soon")
        } label: {
            LabeledContent(label) { Text(value) }
        }
        .foregroundStyle(.primary)
    }
}
