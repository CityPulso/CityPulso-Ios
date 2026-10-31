# Android → iOS 迁移进度

Android（`CityPulso-Android`）是唯一来源。本文件是功能对齐清单，也是断点续做的依据：每组结束时更新。

## 下一步

- 迁移已完成：Loop 和 Near 的全部页面都已移植，CI 全绿，没有剩下的占位页（`PulsoComingSoonView` 只用于还没开放的运动 / 活动类型，
  和本 App 不支持的底栏项，与 Android `ComingSoonScaffold` 一致）。Android 已同步到 `ba36e7d`（`3226b65` 是 Paging 缓存，iOS 不需要）。
- 之后：Android 有新提交就照着同步；用户真机连后端验收后把对应行改成 ✅。

## 视觉对齐（2026-10-31，用户要求「细细打磨对齐所有页面」）

- 设计系统：`PulsoLinkUI/Theme/PulsoPalette`（Radix 色阶、圆角档位、间距、控件高度）+ Pulso 组件（按钮、输入框、卡片、区块、
  分段、下划线 / 高亮标签、选择胶囊、空状态、页面点阵背景、表情输入框）；UIKit 外观跟主题走。
- 参照图：`screenshots/android/*.png`（Pixel 9 模拟器，用户账号）；iOS 截图由 CI 连 dev 后端登录同一账号生成。
- 已逐页对齐：欢迎 / 登录 / 注册、底栏各页、设置及子页（主题、图标、导航、隐私、权限、地图、定位标记、本地数据、账号安全、
  改密码、邮箱、身份）、钱包 / 账单 / 收款账户 / 付款方式、收藏、日历 / 日程、消息 / 聊天室、社交、通知、论坛（信息流、发现、
  详情、帖子、我的论坛）、赛事、球馆详情 / 场馆建筑 / 订场（Loop + Near）。
- 没有 Android 参照、按同一套组件改的：发起流程、收款清单、活动详情 / 编辑（另一会话负责）、课程 / 教练面板。
- 截图测试不打开聊天会话（会把真账号的未读标成已读）。

## 过程记录

- **2026-10-30 跟进 Android 新计划（壳 / 消息 / 社交 / 资料 / 订场 / 收藏 / 本地数据）**，iOS 同步改（用户要求）：
  - 已做：`ShellDestination` 去掉 SOCIAL / NOTIFICATIONS / COURT_BOOKINGS（非社区默认槽 6 → 设置）；
    「我的订场」并进日历（活动与订场，订场标签下即将开始 / 已结束，订场页的「我的订场」打开日历订场标签）；
    资料页头部改成 关注 / 粉丝 / 活动（未回来显示 `-`，关注 / 粉丝进社交对应标签）、去掉角色胶囊、创作者徽标、
    喜欢的运动 / 活动一行横滑 + 点开选择面板保存；编辑资料页喜欢的运动 / 活动改成一行 + 选择面板，不限个数，身份入口移到编辑页。
  - 第 10 组随后做完：消息页（铃铛 → 通知、+ → 社交）、社交页（顶栏聊天图标，`social(tab:)` 路由现在是占位页）、不再有「新聊天」页。
  - 设置 → 清除本地数据（Android 已做）：GRDB 六张表、聊天壁纸、Nuke 图片缓存、发起草稿，每种显示占用，按住确认清除，可全部清除。
- 第 9 组写完：钱包、我的会员 / 会员购买记录 / 时长包详情、收款账户（Stripe Connect 开通）、付款方式、账单（我主持的 / 我的付款）。
- 第 10 组：
  - core：GRDB 本地库（`PulsoDatabase`：社交关系、好友请求、会话、通知、资料卡；登出清空）、`PersistedQuery`、`MediatedList`
    （本地库为准的分页，对应 Android RemoteMediator）、社交 / 通信 DTO 和 API 改成生成、`SocialService` / `CommunicationService` /
    `InboxIndicatorStore` 全量移植、实时推送（centrifuge-swift WebSocket，swift-eventsource SSE 兜底，`RealtimeConnectionManager`
    在 Loop / Near 启动时连）。Linux 测试 77 个全过。
  - Loop 页面：社交（好友 / 关注 / 粉丝、搜索、排序、心形、菜单、按住确认）、好友请求、黑名单、添加好友、公开主页、
    消息（私聊 / 群聊列表，铃铛红点 → 通知，+ → 社交）、通知收件箱（全部 / 未读、全部已读、点开对应页面）。
  - 聊天室、会话设置、群成员、聊天壁纸、分享卡片选择器都已写完；Near 的社交 / 消息页随 Near 分叉。
- 地图设置（样式、定位标记）写完。
- **iPad（用户要求，2026-10-30）**：三个 App 改成通用（`TARGETED_DEVICE_FAMILY = 1,2`，iPad 四个方向、分屏 / 台前调度）。
  页面用系统 List / Form / sheet，宽屏下自动加阅读边距、sheet 变表单弹窗；还要逐页看 iPad 截图，修固定宽度的地方，
  CI 截图加一台 iPad。苹果没有折叠屏 iPhone，不需要「折叠屏」适配；iPad 的窗口任意缩放就覆盖了大小屏切换。
- 第 12 组：课程详情、教练主页、我的课程、我的私教、赛事详情 / 报名（好友里选队友）/ 我的赛事、教练面板（课次 / 合作球馆 / 授课报酬 / 教练资料和服务、新建私教课）都写完并接上路由。
- **赛事页（用户要求，2026-10-30，跟 Android 同步）**：底栏「赛事」改成公开赛事列表（`Pages/Tournament/List/TournamentsView`）：
  搜索（停 300ms）、运动标签带图标、海报卡（封面 + 状态、日期、球馆、组别 · 报名 · 最低报名费）；右上角「我的赛事」。
  「我的赛事」改成三个标签：我的报名（进行中 / 已结束）、组队邀请（红色数字，卡片下两个等宽按钮）、获得的奖品。
  赛事详情改成：顶部照片轮播、标题和状态、日期 / 球馆 / 组别和报名费，关于 | 组别 | 赛程 | 场地四个标签（场地带编号地图、距离、导航），
  底部固定「立即报名」，已有报名时显示我的状态（回复邀请 / 付款 / 看我的报名）。
  Android 同一批还把「课程」和「私教」合成一页（去掉 COACHING），iOS 已跟着改。
- 第 11 组：论坛信息流、论坛详情、帖子详情（评论、点赞、收藏、举报）、发帖 / 编辑（段落编辑器：文字 / 照片 / 链接，
  上下移动、按住确认删除；链接选择器四个标签 + 粘贴链接；论坛最多 10 个、每个最多 3 个话题；城市按位置预填；照片最多 9 张）。
  发现论坛（搜索 / 类型 / 运动 / 排序、行内关注）、我的论坛（待处理数、管理入口）、我赞过的帖子也写完。
  建论坛（封面 / 头像 / 运动 / 简介 / 发帖方式 / 规则 / 组织身份选管理员）、论坛管理（设置、管理人员、待审、举报、公告、话题）也写完。
- 深链：`youloopy://open/panel/...`（活动 / 球馆 / 订场 / 场馆建筑 / 帖子 / 论坛）先进 inbox，登录后的主界面推进当前栈；
  聊天里娱邻的卡片交给娱邻（`youneary://`，没装就开 pulsonear.com）。Info.plist 加了 URL Types 和 LSApplicationQueriesSchemes。
- **Near 开始（2026-10-30）**：Android 的 Near 是 Loop 改名分叉的（event→activity、court→space、Badminton→BoardGame），
  对应文件只差活动专属字段（Near 没有场地数 / 每场人数 / 器材 / 组别 / 赛制，多了最少人数；15 种里只有麻将多一个规则）。
  iOS 照同样的路：先把 Loop 代码按改名规则转成 Near 的桌游模板，补上差异，再用 `Scripts/fork_activity.py`（同 fork_sport.py，
  带 `--check`）分叉出另外 14 种。已完成：数据层（仓储 / 事件总线 / 查询 / 服务 / 发起请求 / 行）15 种全部、发起草稿和校验
  （最少人数、麻将规则、禁赌提示勾选、快捷时长）、地图与位置 DI。
  活动页面已写完：详情（须知提示、麻将规则）、发起向导（类型分组卡片、快捷时长、发布前勾选须知）、收款清单、日历 / 活动中心、
  议程侧栏、活动搜索、地图（没有赛事图层）、选点、标记地点 / 我标记的地点、收款账户。
  门店已写完：门店搜索、门店详情（概览 / 桌台 / 会员 / 商品与服务 / 活动 / 须知；桌台类列桌台，KTV 包间大小和最低消费、台球桌型，
  桌游门店列游戏库，密室 / 剧本杀列主题 / 剧本）、会员购买、场馆建筑、收藏心形、预约页（顶部切换类型原地换内容：桌台类是时段表，
  密室 / 剧本杀选场次和人数）、确认页（桌台和场次共用）、我的一条预约。Near 没有时长包，相关代码都已去掉。
- **登录同步 Android（2026-10-30）**：手机一律记住登录（去掉「记住我」）；选身份后先用新身份的 token 读到档案、套上偏好再写进会话；
  登录中途失败结束半截会话（`LogoutReason.signInFailed`）；刷新被拒的若已不是会话里的票（登录 / 选身份作废了旧票），不登出；
  账号没有 community 身份时显示 `login_no_community_profile`。Linux 测试 84 个全过。
- Near 其余也写完（2026-10-30）：钱包（会员卡 / 等门店确认，没有时长包）、我的会员卡 / 会员申请、账单、收藏、地图设置、
  清除本地数据、论坛（信息流 / 详情 / 帖子 / 发帖编辑 / 管理 / 发现 / 我的 / 赞过）、社交 / 聊天 / 通知（按 Near 的资源类型跳转）、
  个人页活动数（15 种活动类型发起 + 参加）、`youneary://` 深链和聊天卡片交给跃圈。通用分页列表移到 PulsoLinkUI（`PulsoPagedList`）。
- **2026-10-30 CI 全绿**（Loop + Near 全部页面编译通过，核心测试 84 个）。Android 截至 `ba36e7d` 的提交都已同步
  （论坛卡片 / 帖子页改版、置顶聊天、群头像、收款清单滑动操作、底栏去掉私教加我的地点、即将开始筛选、地图筛选分组、活动中心订场筛选和滑动换标签）。
- 截图：`ScreenshotTests` 覆盖两个 App 的全部底栏页和不需要 id 的页面（iPhone + iPad），`gh workflow run iOS -f screenshots=true` 触发，
  下载到 `screenshots/iPhone`、`screenshots/iPad`。不连后端，只看布局。
- 截图逐页看过（124 张 × iPhone / iPad）：修了论坛分段贴边、钱包入口卡多出的箭头，以及所有 Radix 色阶都是透明的
  （`Scripts/android_colors.py` 把 Android 的 `0xFF` alpha 去掉了）。
- 还差：用户真机连后端验收（截图不连后端，只能看布局）。

## 状态

| 标记 | 含义 |
|---|---|
| ⬜ | 未开始 |
| 🟨 | 进行中 |
| 🟦 | 已实现（代码写完，CI 全绿，截图还没逐页看） |
| 🟩 | 编译验证（CI 全绿 + 截图看过） |
| ✅ | 功能验证（用户在 iPhone 上连真后端验收过） |
| ⛔ | 阻塞（写明原因） |

「编译验证」不等于功能对齐。截图测试用 StubProtocol 和固定 JSON，只说明页面能渲染。

## 阻塞

| 项 | 原因 | 需要谁 |
|---|---|---|
| Apple 登录真机 | Apple 开发者账号在申请；`PULSO_APPLE_SIGN_IN = NO`，后端 `APPLE_BUNDLE_IDS` 为空 | 用户 |
| 真机签名 | 同上 | 用户 |
| Apple 登录接口上线 | PulsoLink-API 新 Go 代码需要 `task app:rebuild` | 用户 |

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
| 本地库（聊天、会话、通知、好友、请求、资料卡） | `base/data/local`（Room） | `PulsoLinkCore/Base/Storage`（GRDB `PulsoDatabase`、`PersistedQuery`、`MediatedList`） | 🟦 |
| Asset 上传 | `base/data/asset`、`AssetService` | `PulsoLinkCore/Base/Data/Asset` | 🟦 |
| 图片加载 + 退出清缓存 | Coil、`ImageCacheLogoutClearable` | `PulsoLinkUI/Images`（Nuke） | 🟦 |
| 深链 `youloopy://` / `youneary://open/panel/...` | `navigation/LoopDeepLinks.kt`、`NearDeepLinks.kt` | `Navigation/LoopDeepLinks`、`NearDeepLinks`（inbox，登录后推进当前栈） | 🟦 |
| 实时（Centrifugo） | `base/realtime/*` | `PulsoLinkCore/Base/Realtime`（centrifuge-swift，SSE 兜底） | 🟦 |
| 设备定位 / 附近搜索中心 | `stores/DeviceLocationStore`、`NearbyQueryLocationStore`、`features/location` | `Stores/LocationStores`、`Features/Location`（CoreLocation + MapKit 反查地名） | 🟦 |
| 支付 | `base/data/payments`、`features/payments` | `Features/Payments`（stripe-ios PaymentSheet / Connect） | 🟦 |
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
| CREATE | `pages/event/create` | `Pages/Event/Create`（一个向导给 11 种运动；各运动只差 `SportSettingsDetails` 和 `Features/Create/<Sport>Create.swift`） | 5 / 6 | 🟦 |
| SETTINGS | `pages/settings/overview` | `Pages/Settings/Overview` | 2 | 🟩 |
| BILLING | `pages/billing` | `Pages/Billing`（运动 / 范围 / 状态，收款清单和我的付款） | 9 | 🟦 |
| CHAT_HUB | `pages/social/chat/hub` | `Pages/Social/Chat/Hub`（私聊 / 群聊、置顶栏可收起、铃铛进通知、+ 进社交） | 10 | 🟦 |
| PROFILE | `pages/profile/overview` | `Pages/Profile/Overview`（含活动中心、发起 / 参加数） | 3–4 | 🟦 |
| WALLET | `pages/wallet` | `Pages/Wallet`（会员卡 / 时长包，付款方式和收款账户入口） | 9 | 🟦 |
| COURSES | `pages/program/mine` | `Pages/Program/Mine`（我的课程，右上角进我的私教） | 12 | 🟦 |
| TOURNAMENTS | `pages/tournament/mine` | `Pages/Tournament/List`（公开赛事、搜索、运动标签，右上角我的赛事） | 12 | 🟦 |
| FAVORITES | `pages/venue/favorites` | `Pages/Venue/Favorites`（球馆 / 建筑 / 论坛 / 帖子 / 评论） | 8 | 🟦 |
| FORUM | `pages/discussion/feed` | `Pages/Discussion/Feed`（信息流卡片按 Android 改版） | 11 | 🟦 |
| PLACE_REQUESTS | `pages/place/requests` | `Pages/Place/Requests`（原在设置里） | 7 | 🟦 |

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
| OpenMapSettings | `pages/settings/map` | `Pages/Settings/Map` | 7 | 🟦 |
| OpenMapStyle | `pages/settings/map` | `Pages/Settings/Map` | 7 | 🟦 |
| OpenLocationMarker | `pages/settings/map` | `Pages/Settings/Map` | 7 | 🟦 |
| OpenLocationPick | `pages/location` | `Pages/Location`（`LoopMapView` + MapLibre；搜索 / 反查走核心 `LocationService`） | 7 | 🟦 |
| OpenPlaceRequests | `pages/place/requests` | `Pages/Place/Requests`（状态分段、按住撤回、重新提交、打开建筑） | 7 | 🟦 |
| OpenMarkPlace | `pages/place/mark` | `Pages/Place/Mark`（新标记 / 被拒的重新提交；地图预览 + 选点页、照片上传、联系方式） | 7 | 🟦 |
| OpenVenue | `pages/venue/detail` | `Pages/Venue/Detail`（9 个分段、会员 / 时长包购买走 connected account 的 PaymentSheet、收藏、导航 / 电话 / 分享；课程 / 教练 / 赛事详情等第 12 组） | 8 | 🟦 |
| OpenBuilding | `pages/venue/detail` | `Pages/Venue/Building` | 8 | 🟦 |
| OpenVenueBook | `pages/venue/book/<sport>` | `Pages/Venue/Book`（三种运动一页；`<Sport>VenueService` 由 `fork_sport.py` 从羽毛球生成） | 8 | 🟦 |
| OpenVenueConfirm | `pages/venue/confirm/<sport>` | `Pages/Venue/Confirm` | 8 | 🟦 |
| OpenCourtBooking | `pages/venue/booking/<sport>` | `Pages/Venue/Booking` | 8 | 🟦 |
| OpenWallet | `pages/wallet` | `Pages/Wallet` | 9 | 🟦 |
| OpenPaymentAccounts | `pages/billing/paymentaccounts` | `Pages/Billing/PaymentAccounts`（Stripe Connect 开通） | 9 | 🟦 |
| OpenPaymentMethods | `pages/billing/paymentmethods` | `Pages/Billing/PaymentMethods` | 9 | 🟦 |
| OpenVenueMembership | `pages/membership/detail` | `Pages/Venue/Detail`（会员面板） | 9 | 🟦 |
| OpenMyMembership | `pages/membership/list` | `Pages/Wallet/Detail` | 9 | 🟦 |
| OpenMyMembershipPurchase | `pages/membership` | `Pages/Wallet/Detail` | 9 | 🟦 |
| OpenVenueBundle | `pages/bundle/detail` | `Pages/Venue/Detail`（时长包面板） | 9 | 🟦 |
| OpenMyBundle | `pages/bundle/list` | `Pages/Wallet/Detail` | 9 | 🟦 |
| OpenAddFriend | `pages/social/addfriend` | `Pages/Social/AddFriend` | 10 | 🟦 |
| OpenFriendRequests | `pages/social/requests` | `Pages/Social/Requests` | 10 | 🟦 |
| OpenBlockedList | `pages/social/blocked` | `Pages/Social/Blocked` | 10 | 🟦 |
| OpenSocialProfile | `pages/social/profile` | `Pages/Social/Profile` | 10 | 🟦 |
| OpenChatConversation | `pages/social/chat/room` | `Pages/Social/Chat/Room` | 10 | 🟦 |
| OpenChatSettings | `pages/social/chat/settings` | `Pages/Social/Chat/Settings`（群主改群名 / 群头像） | 10 | 🟦 |
| OpenGroupMembers / OpenGroupAddMembers | `pages/social/chat/settings` | `Pages/Social/Chat/Settings` | 10 | 🟦 |
| OpenChatLocationPick / OpenChatLocationView | `pages/social/chat/picker` | `Pages/Social/Chat/Picker` | 10 | 🟦 |
| OpenChatEventPicker / OpenChatFavoritePicker | `pages/social/chat/picker` | `Pages/Social/Chat/Picker` | 10 | 🟦 |
| OpenForum | `pages/discussion/detail` | `Pages/Discussion/Detail` | 11 | 🟦 |
| OpenForumManage | `pages/discussion/manage` | `Pages/Discussion/Manage` | 11 | 🟦 |
| OpenForumSearch | `pages/discussion/search` | `Pages/Discussion/Lists/ForumListViews` | 11 | 🟦 |
| OpenForumCreate | `pages/discussion/create` | `Pages/Discussion/Create` | 11 | 🟦 |
| OpenPost | `pages/discussion/post/detail` | `Pages/Discussion/Post/PostDetailView`（关注作者、楼中楼回复、相关内容） | 11 | 🟦 |
| OpenPostCreate / OpenPostEdit | `pages/discussion/post/create`、`edit` | `Pages/Discussion/Post/PostCreateView`、`PostEditView` | 11 | 🟦 |
| OpenLikedPosts | `pages/discussion/liked` | `Pages/Discussion/Lists/ForumListViews` | 11 | 🟦 |
| OpenMyForums | `pages/discussion/mine` | `Pages/Discussion/Lists/ForumListViews` | 11 | 🟦 |
| OpenCourse | `pages/program/course` | `Pages/Program/Course` | 12 | 🟦 |
| OpenCoach | `pages/program/coach` | `Pages/Program/Coach` | 12 | 🟦 |
| OpenCoachPanel | `pages/coach/panel` | `Pages/Coach/Panel` | 12 | 🟦 |
| OpenTournament | `pages/tournament/detail` | `Pages/Tournament/Detail` | 12 | 🟦 |
| OpenMyCoaching | `pages/program/mine` | `Pages/Program/Mine`（课程页右上角进） | 12 | 🟦 |
| OpenMyTournaments | `pages/tournament/mine` | `Pages/Tournament/Mine`（我的报名 / 组队邀请 / 获得的奖品） | 12 | 🟦 |
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
| OpenActivity / OpenCreatedActivity / OpenChecklist | `pages/activity/*` | 🟦 |
| 日历 / 议程 / 活动搜索 / 地图 / 选点 / 标记地点 | `pages/activity/*`、`pages/location`、`pages/place` | 🟦 |
| 门店搜索 / 门店详情 / 场馆建筑 | `pages/venue/{search,detail}` | 🟦 |
| OpenVenueBook / 确认（桌台时段、密室 / 剧本杀场次） | `pages/venue/{book,confirm}` | 🟦 |
| OpenSpaceBooking（我的一条预约） | `pages/venue/booking` | 🟦 |
| OpenChatActivityPicker | `pages/social/chat/picker` | 🟦 |
| 其余命令（社交 / 聊天 / 通知 / 论坛 / 钱包 / 会员 / 账单 / 收藏 / 地图设置 / 本地数据 / 深链） | 与 Loop 同名 | 🟦 |

Near 没有：课程、私教、赛事、时长包。
