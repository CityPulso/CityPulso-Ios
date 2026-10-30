import Foundation
import PulsoLinkCore
import PulsoLinkUI

/**
 * 应用在聊天中间发的提示，按发出时写进来的名字拼成一句话。
 * `mine` = 读的人就是做这件事的人（系统消息以操作者身份发出），这时说「你退出了群聊」。
 */
func chatSystemNoticeText(_ system: ChatSystemContent?, mine: Bool) -> String {
    let actor = system?.actorName ?? ""
    let group = system?.groupName ?? ""
    let targets = system?.targetNames ?? []
    let names = ListFormatter.localizedString(byJoining: targets)
    switch ChatSystemMessageCode.fromWire(system?.code) {
    case .groupCreated:
        return mine
            ? localizedFormat("shell_chat_system_group_created_self", group)
            : localizedFormat("shell_chat_system_group_created", actor, group)
    case .groupMemberAdded:
        return localizedFormat(targets.count > 1 ? "shell_chat_system_group_members_added" : "shell_chat_system_group_member_added", names, group)
    case .groupMemberRemoved:
        return mine
            ? localizedFormat("shell_chat_system_group_member_removed_self", names)
            : localizedFormat("shell_chat_system_group_member_removed", actor, names)
    case .groupMemberLeft:
        return mine
            ? String(localized: "shell_chat_system_group_member_left_self")
            : localizedFormat("shell_chat_system_group_member_left", actor)
    case .groupInviteRejected:
        return localizedFormat(targets.count > 1 ? "shell_chat_system_group_invites_rejected" : "shell_chat_system_group_invite_rejected", names)
    case .directCreated:
        return String(localized: "shell_chat_system_direct_created")
    }
}
