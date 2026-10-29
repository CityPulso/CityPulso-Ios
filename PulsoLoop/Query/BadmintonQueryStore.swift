import PulsoLinkCore

/**
 * Loop 羽毛球全部读接口的缓存（对应 Android `BadmintonQueryStore`、WEB `hooks/badminton.ts`）。
 * 页面只订阅 stream；写操作后 [BadmintonEventBus.invalidate] → 全清，活跃订阅重拉。
 */
final class BadmintonQueryStore: LogoutClearable {
    static let rosterPageSize = 30

    let events: MemoryQuery<BadmintonListKey, BadmintonEventListResponse>
    let myRegistrations: MemoryQuery<MyBadmintonRegistrationsKey, BadmintonMyRegistrationsResponse>
    let profileRegistrations: MemoryQuery<BadmintonProfileRegistrationsKey, BadmintonProfileRegistrationsResponse>
    let full: MemoryQuery<String, BadmintonFullInformation>
    let regs: MemoryQuery<BadmintonRegsKey, BadmintonRegistrationsPage>
    let checklist: MemoryQuery<String, BadmintonPaymentChecklistResponse>

    init(repository: BadmintonRepository, eventBus: BadmintonEventBus) {
        let invalidates: @Sendable () -> AsyncStream<Void> = { eventBus.signals { _ in true } }
        events = MemoryQuery(invalidates: invalidates) { key in
            try await repository.listBadmintonEvents(ListBadmintonEventsRequest(
                offset: key.offset,
                limit: key.limit,
                includeEnded: key.includeEnded && !key.endedOnly ? true : nil,
                endedOnly: key.endedOnly ? true : nil,
                profileId: key.hostedProfileId,
                profileScope: key.hostedProfileScope,
                buildingId: key.buildingId
            ))
        }
        myRegistrations = MemoryQuery(invalidates: invalidates) { key in
            try await repository.listMyBadmintonRegistrations(ListMyBadmintonRegistrationsRequest(
                offset: key.offset,
                limit: key.limit,
                all: key.all ? true : nil,
                includeEnded: key.includeEnded ? true : nil,
                excludeHosted: key.excludeHosted ? true : nil
            ))
        }
        profileRegistrations = MemoryQuery(invalidates: invalidates) { key in
            try await repository.listBadmintonProfileRegistrations(ListBadmintonProfileRegistrationsRequest(
                profileId: key.profileId,
                profileScope: key.profileScope,
                limit: key.limit,
                includeEnded: key.includeEnded ? true : nil
            ))
        }
        full = MemoryQuery(invalidates: invalidates) { eventId in
            try await repository.getBadmintonEventFullInformation(eventId: eventId)
        }
        regs = MemoryQuery(invalidates: invalidates) { key in
            try await repository.listBadmintonRegistrations(eventId: key.eventId, offset: key.offset, limit: key.limit)
        }
        checklist = MemoryQuery(invalidates: invalidates) { eventId in
            try await repository.getOrCreatePaymentChecklist(eventId: eventId)
        }
    }

    /** 浏览数只增不减地叠到已缓存的列表和详情上（Android `overlayView`）。 */
    func overlayView(eventId: String, view: Int) async {
        guard !eventId.isEmpty, view >= 0 else { return }
        await events.updateAll { page in
            var page = page
            for index in page.items.indices where page.items[index].id == eventId && page.items[index].view < view {
                page.items[index].view = view
            }
            return page
        }
        await myRegistrations.updateAll { page in
            var page = page
            for index in page.items.indices where page.items[index].id == eventId && page.items[index].view < view {
                page.items[index].view = view
            }
            return page
        }
        await profileRegistrations.updateAll { page in
            var page = page
            for index in page.items.indices where page.items[index].id == eventId && page.items[index].view < view {
                page.items[index].view = view
            }
            return page
        }
        await full.updateAll { info in
            var info = info
            if info.event.id == eventId, info.event.view < view { info.event.view = view }
            return info
        }
    }

    /** 打开详情前预拉详情和名单首页（不随页面取消；失败由详情页自己报）。 */
    func prefetchDetail(eventId: String) {
        guard !eventId.isEmpty else { return }
        Task {
            _ = try? await full.get(eventId)
            _ = try? await regs.get(BadmintonRegsKey(eventId: eventId, offset: 0, limit: Self.rosterPageSize))
        }
    }

    /** 退出登录：清掉所有缓存，下一个账号看不到这个账号的数据。 */
    func onLogout() async throws {
        await events.clear()
        await myRegistrations.clear()
        await profileRegistrations.clear()
        await full.clear()
        await regs.clear()
        await checklist.clear()
    }
}
