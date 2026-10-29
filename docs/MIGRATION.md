# Android → iOS 迁移进度

Android（`CityPulso-Android`）是唯一来源。本文件是功能对齐清单，也是断点续做的依据：每组结束时更新。

## 下一步

- 第 0 组（地基）已写完，等 CI。
- 然后第 3 组（个人页）：profile/*、identities/overview、backgrounds。
- GRDB 本地库放到第 10 组（只有聊天 / 通知 / 好友用），深链 inbox 放到第 5 组（第一个深链目标是活动详情），不提前写没人用的代码。

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
| 换图标要重启 | 备用图标立即生效，不显示「需要重启」 | iOS 行为 |
| Firebase messaging | 不接 APNs | Android 只有 Gradle 依赖，Kotlin 里没有用到；通知走 Centrifugo + 通知列表 |
| Stripe Android | stripe-ios（PaymentSheet / Connect） | 都是线下服务（订场、课程、赛事、会员），App Store 3.1.3(e) 允许，不用 IAP |
| Room | GRDB | |

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
| 位置 | `base/stores/LocationStore`、`features/location` | — | ⬜ 第 7 组 |
| 支付 | `base/data/payments`、`features/payments` | — | ⬜ 第 9 组 |
| 枚举（wire 值、选项） | `*/enums/*.kt` | `Scripts/android_enums.py` 生成 `Enums/Generated` | 🟦 |
| 全局消息条 | snackbar | `PulsoLinkUI/Messages` | 🟩 |
| 加载失败 + 重试 | | `PulsoLoadErrorView` | 🟩 |

## Loop：底栏目标（`ShellDestination` → `navigation/LoopPageLevel.kt`）

| 目标 | Android 页面 | iOS | 组 | 状态 |
|---|---|---|---|---|
| EXPLORE | `pages/event/explore` | | 7 | ⬜ |
| CALENDAR | `pages/event/calendar` | | 4 | ⬜ |
| SEARCH | `pages/event/search` | | 4 | ⬜ |
| VENUE_SEARCH | `pages/venue/search` | | 8 | ⬜ |
| SOCIAL | `pages/social/overview` | | 10 | ⬜ |
| CREATE | `pages/event/create` | | 5 | ⬜ |
| SETTINGS | `pages/settings/overview` | `Pages/Settings/Overview` | 2 | 🟩 |
| BILLING | `pages/billing` | | 9 | ⬜ |
| NOTIFICATIONS | `pages/social/notifications` | | 10 | ⬜ |
| CHAT_HUB | `pages/social/chat/hub` | | 10 | ⬜ |
| PROFILE | `pages/profile/overview` | | 3 | ⬜ |
| WALLET | `pages/wallet` | | 9 | ⬜ |
| COURSES | `pages/program/mine` | | 12 | ⬜ |
| COACHING | `pages/program/mine` | | 12 | ⬜ |
| TOURNAMENTS | `pages/tournament/mine` | | 12 | ⬜ |
| COURT_BOOKINGS | `pages/venue/bookings` | | 8 | ⬜ |
| FAVORITES | `pages/venue/favorites` | | 8 | ⬜ |
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
| OpenProfileEdit | `pages/profile/edit` | | 3 | ⬜ |
| OpenIdentities | `pages/identities/overview` | | 3 | ⬜ |
| OpenBackgrounds | `pages/profile/backgrounds` | | 3 | ⬜ |
| OpenEvent | `pages/event/detail/<sport>` | | 5 / 6 | ⬜ |
| OpenCreatedEvent | `pages/event/detail/<sport>` | | 5 / 6 | ⬜ |
| OpenChecklist | `pages/event/checklist/<sport>` | | 5 / 6 | ⬜ |
| OpenMapSettings | `pages/settings/map` | | 7 | ⬜ |
| OpenMapStyle | `pages/settings/map` | | 7 | ⬜ |
| OpenLocationMarker | `pages/settings/map` | | 7 | ⬜ |
| OpenLocationPick | `pages/location` | | 7 | ⬜ |
| OpenPlaceRequests | `pages/place/requests` | | 7 | ⬜ |
| OpenMarkPlace | `pages/place/mark` | | 7 | ⬜ |
| OpenVenue | `pages/venue/detail` | | 8 | ⬜ |
| OpenBuilding | `pages/venue/detail` | | 8 | ⬜ |
| OpenVenueBook | `pages/venue/book/<sport>` | | 8 | ⬜ |
| OpenVenueConfirm | `pages/venue/confirm/<sport>` | | 8 | ⬜ |
| OpenCourtBooking | `pages/venue/booking/<sport>` | | 8 | ⬜ |
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
| （日程） | `pages/agenda` | | 4 | ⬜ |
| OpenComingSoon | `navigation/ComingSoonRoute.kt` | `PulsoComingSoonView` | — | 🟩 |

运动（第 6 组从羽毛球生成）：badminton、baseball、basketball、fishing、football、golf、hiking、pickleball、ski、tabletennis、tennis。每种运动都有自己的 data / query / service / detail / checklist / 报名卡片；venue 的 book / booking / confirm 只有 badminton、pickleball、tennis。

## Near（`navigation/NearNavCommand.kt`）

Near 是 Loop 的分叉：活动换成 15 种 Near 活动，球馆换成门店。和 Loop 不同的地方：

| 命令 / 页面 | Android | 状态 |
|---|---|---|
| 设置 + 账号（同 Loop 第 2 组），活动偏好 | `pages/settings`、`pages/account` | 🟩 |
| 欢迎 / 登录 / 注册 | `pages/welcome`、`pages/identities` | 🟩 |
| OpenActivity / OpenCreatedActivity / OpenChecklist | `pages/activity/*` | ⬜ |
| OpenSessionConfirm（密室 / 剧本杀场次） | `pages/venue/confirm` | ⬜ |
| OpenSpaceBooking（桌台 / 包间 / 机位） | `pages/venue/booking` | ⬜ |
| OpenChatActivityPicker | `pages/social/chat/picker` | ⬜ |
| 其余命令 | 与 Loop 同名 | ⬜ 跟随 Loop 对应组 |

Near 没有：课程、私教、赛事、时长包。
