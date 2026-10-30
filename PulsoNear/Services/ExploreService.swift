import PulsoLinkCore

/** 所有活动类型的附近活动（对应 Android `ExploreService`、WEB `hooks/explore.ts`）；每个针打开自己活动类型的详情。 */
struct ExploreService: Sendable {
    let query: ExploreQueryStore
    /** 重试：让每种活动的列表和混合的针都重拉。 */
    let invalidateAll: @Sendable () -> Void

    func invalidate() {
        invalidateAll()
    }
}
