# Android → iOS 迁移进度

Android（`CityPulso-Android`）是唯一来源。本文件是功能对齐清单，也是断点续做的依据：每组结束时更新。

## 下一步

- **2026-10-30 跟进 Android 新计划（壳 / 消息 / 社交 / 资料 / 订场 / 收藏 / 本地数据）**，iOS 同步改（用户要求）：
  - 已做：`ShellDestination` 去掉 SOCIAL / NOTIFICATIONS / COURT_BOOKINGS（非社区默认槽 6 → 设置）；
    「我的订场」并进日历（活动与订场，订场标签下即将开始 / 已结束，订场页的「我的订场」打开日历订场标签）；
    资料页头部改成 关注 / 粉丝 / 活动（未回来显示 `-`，关注 / 粉丝进社交对应标签）、去掉角色胶囊、创作者徽标、
    喜欢的运动 / 活动一行横滑 + 点开选择面板保存；编辑资料页喜欢的运动 / 活动改成一行 + 选择面板，不限个数，身份入口移到编辑页。
  - 等第 10 组：消息页（铃铛 → 通知、+ → 社交）、社交页（顶栏聊天图标，`social(tab:)` 路由现在是占位页）、不再有「新聊天」页。
  - 等 Android 做完：设置 → 清除本地数据（iOS 对应 GRDB 表、Nuke 缓存、聊天壁纸、草稿、筛选、内存查询缓存）。
  - Near 资料页的「活动」数要等 Near 活动移植后才有，现在一直是 `-`。
- 第 9 组写完：钱包、我的会员 / 会员购买记录 / 时长包详情、收款账户（Stripe Connect 开通）、付款方式、账单（我主持的 / 我的付款）。
- 第 10 组开始：GRDB 本地库（`PulsoDatabase`、`PersistedQuery`）、社交 DTO / API 改成生成、`SocialRepository` / `SocialLocalStore` /
  `SocialQueryStore` / `SocialService` 全量移植（Linux 测试通过）。还差：好友请求红点（`InboxIndicatorStore`）、聊天、通知、社交页面。
- 地图设置（样式、定位标记）写完。
- **iPad（用户要求，2026-10-30）**：三个 App 改成通用（`TARGETED_DEVICE_FAMILY = 1,2`，iPad 四个方向、分屏 / 台前调度）。
  页面用系统 List / Form / sheet，宽屏下自动加阅读边距、sheet 变表单弹窗；还要逐页看 iPad 截图，修固定宽度的地方，
  CI 截图加一台 iPad。苹果没有折叠屏 iPhone，不需要「折叠屏」适配；iPad 的窗口任意缩放就覆盖了大小屏切换。
- 第 12 组：课程详情、教练主页、我的课程、我的私教、赛事详情 / 报名（好友里选队友）/ 我的赛事都写完并接上路由；教练面板没写。
- 还差：深链 inbox；第 10 组页面；第 11 组论坛；教练面板；Near 全部分叉；最后 `screenshots/` 截图（iPhone + iPad）。

## 状态

| 标记 | 含义 |
|---|---|
| ⬜ | 未开始 |
| 🟨 | 进行中 |
| 🟦 | 已实现（代码写完，CI 还没过） |
| 🟩 | 编译验证（CI 全绿 + 截图看过） |
| ✅ | 功能验证（用户在 iPhone 上连真后端验收过） |
| ⛔ | 阻塞（写明原因） |

「编译验证」不等于功能对齐。截图测试用 StubProtocol 和固定 JSON，只说明页面能渲染。

## 阻塞

| 项 | 原因 | 需要谁 |
|---|---|---|
| Apple 登录真机 | Apple 开发者账号在申请；`PULSO_APPLE_SIGN_IN = NO`，后端 `APPLE_BUNDLE_IDS` 为空 | 用户 |
| 真机签名 | 同上 | 用户 |
| Apple 登录接口上线 | PulsoLink-API 新 Go 代码需要 `task run:rebuild` | 用户 |

## 平台差异（有意为之）

| Android | iOS | 原因 |
|---|---|---|
| Material 底栏 | 自己的 Liquid Glass 底栏（系统 `.glassEffect`），5 格 + 独立第 6 格 | 原生 TabView 放 6 格会折进 More（截图验证过），用户确认 |
| 应用内语言选择 | 跳 iOS 设置里的 per-app 语言，再把当前语言回写到账号 | iOS 系统管理 App 语言 |
| 字体 / 字号设置 | 不显示，用 Dynamic Type | iOS 系统设置 |
| 编辑资料逐项弹窗 | 行内直接编辑的系统表单；离开时自动保存，改错时不能返回 | iOS 表单习惯 |
| 日程侧栏（左侧滑出） | 系统 sheet，同样从栈底页面左边缘右滑打开 | iOS 没有原生的左侧抽屉 |
| 搜索页运动标签下划线 Tab | 横向胶囊 + 系统分页 TabView | iOS 习惯 |
| 换图标要重启 | 备用图标立即生效，不显示「需要重启」 | iOS 行为 |
| Firebase messaging | 不接 APNs | Android 只有 Gradle 依赖，Kotlin 里没有用到；通知走 Centrifugo + 通知列表 |
| Stripe Android | stripe-ios（PaymentSheet / Connect） | 都是线下服务（订场、课程、赛事、会员），App Store 3.1.3(e) 允许，不用 IAP |
| Room | GRDB（`PulsoDatabase`，登出清空） | |
| Explore 常驻底部面板（自己画的三段拖拽） | 系统 sheet：卡片高度 + 全屏两档，卡片高度以下地图仍可操作；推进别的页面时先收起，回来再弹出 | iOS 原生 sheet 已有分档和背景交互 |
| Explore 聚合针原地放大成面板 | 系统 popover（手机上也保持 popover） | iOS 原生 |
| Explore 筛选里的胶囊 / 滑杆 | 系统表单：Picker、Toggle、设施多选子页 | iOS 表单习惯 |

## 基础设施

| 功能 | Android | iOS | 状态 |
|---|---|---|---|
| HTTP + JSON | `pulsolink-core/base/network` | `PulsoLinkCore/Base/Network`（Alamofire） | 🟩 |
| 会话 / token 刷新 / Keychain | `base/auth/session` | `PulsoLinkCore/Base/Auth` | 🟩 |
| 身份 / 偏好同步 | `base/preferences`、`base/stores/ProfileStore` | `PulsoLinkCore/Core/Profile` | 🟩 |
| 查询缓存 / 分页 / invalidate | `core/query/*` | `PulsoLinkCore/Core/Query`（MemoryQuery、Loadable、PagedList） | 🟦 |
| 本地库（聊天、会话、通知、好友、请求、资料卡） | `base/data/local`（Room） | — | ⬜ 第 10 组（GRDB） |
| Asset 上传 | `base/data/asset`、`AssetService` | `PulsoLinkCore/Base/Data/Asset` | 🟦 |
| 图片加载 + 退出清缓存 | Coil、`ImageCacheLogoutClearable` | `PulsoLinkUI/Images`（Nuke） | 🟦 |
| 深链 `youloopy://open/panel/...` | `navigation/LoopDeepLinks.kt` | — | ⬜ 第 5 组 |
| 实时（Centrifugo） | `base/realtime/*` | — | ⬜ 第 10 组 |
| 设备定位 / 附近搜索中心 | `stores/DeviceLocationStore`、`NearbyQueryLocationStore`、`features/location` | `Stores/LocationStores`、`Features/Location`（CoreLocation + MapKit 反查地名） | 🟦 |
| 支付 | `base/data/payments`、`features/payments` | — | ⬜ 第 9 组 |
| 枚举（wire 值、选项） | `*/enums/*.kt` | `Scripts/android_enums.py` 生成 `Enums/Generated` | 🟦 |
| DTO / API | `*/dto/*.kt`、`*/api/*.kt`（Retrofit） | `Scripts/android_dtos.py`、`android_apis.py` 生成 `Data/Generated` | 🟩 |
| 各运动数据层（仓储 / 缓存 / Service） | `data/<sport>`、`query`、`services` | 羽毛球手写，`Scripts/fork_sport.py` 生成其余 10 种 | 🟦 |
| 全局消息条 | snackbar | `PulsoLinkUI/Messages` | 🟩 |
| 加载失败 + 重试 | | `PulsoLoadErrorView` | 🟩 |

## Loop：底栏目标（`ShellDestination` → `navigation/LoopPageLevel.kt`）

| 目标 | Android 页面 | iOS | 组 | 状态 |
|---|---|---|---|---|
| EXPLORE | `pages/event/explore` + `features/map` | `Pages/Event/Explore`、`Features/Map`（针是叠在 MapLibre 上的 SwiftUI 视图，按投影摆；底部面板用系统 sheet 的两个高度，聚合面板用 popover） | 7 | 🟦 |
| CALENDAR | `pages/event/calendar` + `features/activity` | `Pages/Event/Calendar`、`Features/Activity` | 4 | 🟦 |
| SEARCH | `pages/event/search` + `features/search` | `Pages/Event/Search`、`Features/Search` | 4 | 🟦 |
| VENUE_SEARCH | `pages/venue/search` | `Pages/Venue/Search`（每个运动一页、存着的球馆筛选、收藏星、左滑看地图） | 8 | 🟦 |
| SOCIAL | `pages/social/overview` | | 10 | ⬜ |
| CREATE | `pages/event/create` | `Pages/Event/Create`（一个向导给 11 种运动；各运动只差 `SportSettingsDetails` 和 `Features/Create/<Sport>Create.swift`） | 5 / 6 | 🟦 |
| SETTINGS | `pages/settings/overview` | `Pages/Settings/Overview` | 2 | 🟩 |
| BILLING | `pages/billing` | | 9 | ⬜ |
| NOTIFICATIONS | `pages/social/notifications` | | 10 | ⬜ |
| CHAT_HUB | `pages/social/chat/hub` | | 10 | ⬜ |
| PROFILE | `pages/profile/overview` | `Pages/Profile/Overview`（含活动中心、发起 / 参加数） | 3–4 | 🟦 |
| WALLET | `pages/wallet` | | 9 | ⬜ |
| COURSES | `pages/program/mine` | | 12 | ⬜ |
| COACHING | `pages/program/mine` | | 12 | ⬜ |
| TOURNAMENTS | `pages/tournament/mine` | | 12 | ⬜ |
| COURT_BOOKINGS | `pages/venue/bookings` | `Pages/Venue/Bookings` | 8 | 🟦 |
| FAVORITES | `pages/venue/favorites` | `Pages/Venue/Favorites`（球馆 / 建筑：搜索、排序、筛选带数量、左滑取消收藏；论坛 / 帖子 / 评论等第 11 组） | 8 | 🟨 |
| FORUM | `pages/discussion/feed` | | 11 | ⬜ |

## Loop：导航命令（`navigation/LoopNavCommand.kt`）

| 命令 | Android 页面 | iOS | 组 | 状态 |
|---|---|---|---|---|
| OpenSignup / ReplaceWithSignup | `pages/identities/signup` | `Pages/Identities/Signup` | 1 | 🟩 |
| OpenLogin / ReplaceWithLogin | `pages/identities/login` | `Pages/Identities/Login` | 1 | 🟩 |
| （欢迎页） | `pages/welcome` | `Pages/Welcome` | 1 | 🟩 |
| OpenAppearance | `pages/settings/theme` | `Pages/Settings/Theme` | 2 | 🟩 |
| OpenLauncherIcon | `pages/settings/appicon` | `Pages/Settings/AppIcon` | 2 | 🟩 |
| OpenLanguageText | `pages/settings/language` | 跳 iOS 设置 + `AppLanguageSync` | 2 | 🟩 |
| OpenNavEdit | `pages/settings/navedit` | `Pages/Settings/NavEdit` | 2 | 🟩 |
| OpenEventPreferences | `pages/settings/event` | `Pages/Settings/Event` | 2 | 🟩 |
| OpenPrivacy | `pages/settings/privacy` | `Pages/Settings/Privacy` | 2 | 🟩 |
| OpenPermissions | `pages/settings/permissions` | `Pages/Settings/Permissions` | 2 | 🟩 |
| OpenAccountSecurity | `pages/account/overview` | `Pages/Account/Overview` | 2 | 🟩 |
| OpenEmails | `pages/account/email` | `Pages/Account/Email` | 2 | 🟩 |
| OpenChangePassword | `pages/account/password` | `Pages/Account/Password` | 2 | 🟩 |
| OpenProfileEdit | `pages/profile/edit` | `Pages/Profile/Edit` | 3 | 🟦 |
| OpenIdentities | `pages/identities/overview` | `Pages/Identities/Overview`（社区身份、CityPulso ID、创作者 / 教练申请） | 3 | 🟦 |
| OpenBackgrounds | `pages/profile/backgrounds` | `Pages/Profile/Backgrounds` | 3 | 🟦 |
| OpenEvent | `pages/event/detail/<sport>` | `Pages/Event/Detail`（所有运动共用，差别在 `SportEventDetailService` / `SportFullEvent`） | 5 / 6 | 🟦 |
| OpenCreatedEvent | `pages/event/detail/<sport>` | `Pages/Event/Detail`（发起人视角：编辑、结束、收款清单入口） | 5 / 6 | 🟦 |
| OpenChecklist | `pages/event/checklist/<sport>` | `Pages/Event/Checklist`（所有运动共用，`SportChecklistService`） | 5 / 6 | 🟦 |
| OpenMapSettings | `pages/settings/map` | | 7 | ⬜ |
| OpenMapStyle | `pages/settings/map` | | 7 | ⬜ |
| OpenLocationMarker | `pages/settings/map` | | 7 | ⬜ |
| OpenLocationPick | `pages/location` | `Pages/Location`（`LoopMapView` + MapLibre；搜索 / 反查走核心 `LocationService`） | 7 | 🟦 |
| OpenPlaceRequests | `pages/place/requests` | `Pages/Place/Requests`（状态分段、按住撤回、重新提交、打开建筑） | 7 | 🟦 |
| OpenMarkPlace | `pages/place/mark` | `Pages/Place/Mark`（新标记 / 被拒的重新提交；地图预览 + 选点页、照片上传、联系方式） | 7 | 🟦 |
| OpenVenue | `pages/venue/detail` | `Pages/Venue/Detail`（9 个分段、会员 / 时长包购买走 connected account 的 PaymentSheet、收藏、导航 / 电话 / 分享；课程 / 教练 / 赛事详情等第 12 组） | 8 | 🟦 |
| OpenBuilding | `pages/venue/detail` | `Pages/Venue/Building` | 8 | 🟦 |
| OpenVenueBook | `pages/venue/book/<sport>` | `Pages/Venue/Book`（三种运动一页；`<Sport>VenueService` 由 `fork_sport.py` 从羽毛球生成） | 8 | 🟦 |
| OpenVenueConfirm | `pages/venue/confirm/<sport>` | `Pages/Venue/Confirm` | 8 | 🟦 |
| OpenCourtBooking | `pages/venue/booking/<sport>` | `Pages/Venue/Booking` | 8 | 🟦 |
| OpenWallet | `pages/wallet` | | 9 | ⬜ |
| OpenPaymentAccounts | `pages/billing/paymentaccounts` | | 9 | ⬜ |
| OpenPaymentMethods | `pages/billing/paymentmethods` | | 9 | ⬜ |
| OpenVenueMembership | `pages/membership/detail` | | 9 | ⬜ |
| OpenMyMembership | `pages/membership/list` | | 9 | ⬜ |
| OpenMyMembershipPurchase | `pages/membership` | | 9 | ⬜ |
| OpenVenueBundle | `pages/bundle/detail` | | 9 | ⬜ |
| OpenMyBundle | `pages/bundle/list` | | 9 | ⬜ |
| OpenAddFriend | `pages/social/addfriend` | | 10 | ⬜ |
| OpenFriendRequests | `pages/social/requests` | | 10 | ⬜ |
| OpenBlockedList | `pages/social/blocked` | | 10 | ⬜ |
| OpenSocialProfile | `pages/social/profile` | | 10 | ⬜ |
| OpenCreateChat | `pages/social/chat/create` | | 10 | ⬜ |
| OpenChatConversation | `pages/social/chat/room` | | 10 | ⬜ |
| OpenChatSettings | `pages/social/chat/settings` | | 10 | ⬜ |
| OpenGroupMembers / OpenGroupAddMembers | `pages/social/chat/settings` | | 10 | ⬜ |
| OpenChatLocationPick / OpenChatLocationView | `pages/social/chat/picker` | | 10 | ⬜ |
| OpenChatEventPicker / OpenChatFavoritePicker | `pages/social/chat/picker` | | 10 | ⬜ |
| OpenForum | `pages/discussion/detail` | | 11 | ⬜ |
| OpenForumManage | `pages/discussion/manage` | | 11 | ⬜ |
| OpenForumSearch | `pages/discussion/search` | | 11 | ⬜ |
| OpenForumCreate | `pages/discussion/create` | | 11 | ⬜ |
| OpenPost | `pages/discussion/post/detail` | | 11 | ⬜ |
| OpenPostCreate / OpenPostEdit | `pages/discussion/post/create`、`edit` | | 11 | ⬜ |
| OpenLikedPosts | `pages/discussion/liked` | | 11 | ⬜ |
| OpenMyForums | `pages/discussion/mine` | | 11 | ⬜ |
| OpenCourse | `pages/program/course` | | 12 | ⬜ |
| OpenCoach | `pages/program/coach` | | 12 | ⬜ |
| OpenCoachPanel | `pages/coach/panel` | | 12 | ⬜ |
| OpenTournament | `pages/tournament/detail` | | 12 | ⬜ |
| （日程，左边缘右滑） | `pages/agenda` | `Pages/Agenda`（系统 sheet） | 4 | 🟦 |
| OpenComingSoon | `navigation/ComingSoonRoute.kt` | `PulsoComingSoonView` | — | 🟩 |

运动（第 6 组从羽毛球生成）：badminton、baseball、basketball、fishing、football、golf、hiking、pickleball、ski、tabletennis、tennis。每种运动都有自己的 data / query / service / detail / checklist / 报名卡片；venue 的 book / booking / confirm 只有 badminton、pickleball、tennis。

## Near（`navigation/NearNavCommand.kt`）

Near 是 Loop 的分叉：活动换成 15 种 Near 活动，球馆换成门店。和 Loop 不同的地方：

| 命令 / 页面 | Android | 状态 |
|---|---|---|
| 设置 + 账号（同 Loop 第 2 组），活动偏好 | `pages/settings`、`pages/account` | 🟩 |
| 个人页 / 编辑资料（喜欢的活动，最多 3 个）/ 背景图 / 身份（无角色申请） | `pages/profile`、`pages/identities/overview` | 🟦 |
| 欢迎 / 登录 / 注册 | `pages/welcome`、`pages/identities` | 🟩 |
| OpenActivity / OpenCreatedActivity / OpenChecklist | `pages/activity/*` | ⬜ |
| OpenSessionConfirm（密室 / 剧本杀场次） | `pages/venue/confirm` | ⬜ |
| OpenSpaceBooking（桌台 / 包间 / 机位） | `pages/venue/booking` | ⬜ |
| OpenChatActivityPicker | `pages/social/chat/picker` | ⬜ |
| 其余命令 | 与 Loop 同名 | ⬜ 跟随 Loop 对应组 |

Near 没有：课程、私教、赛事、时长包。
