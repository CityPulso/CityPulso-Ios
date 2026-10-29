# CityPulso-Ios

原生 SwiftUI 版 YouLoopy 跃圈 / YouNeary 娱邻，结构对齐 `CityPulso-Android`：

| iOS | Android |
|---|---|
| `PulsoLinkCore` | `pulsolink-core`（公共 API：网络、鉴权、DTO） |
| `PulsoLinkUI` | `pulsolink-ui`（公共 UI，建在原生 SwiftUI 控件之上） |
| `PulsoLink` | `pulsolink`（占位 app） |
| `PulsoLoop` | `pulsoloop` |
| `PulsoNear` | `pulsonear` |

最低 iOS 26：导航栏、Tab 栏、按钮、弹层一律用系统控件与 Liquid Glass，不手写。

## 开发

需要 macOS + Xcode 26 以上：

```sh
brew install xcodegen
cp Config/Local.xcconfig.example Config/Local.xcconfig   # 填 API 地址和签名团队
xcodegen generate
open CityPulso.xcodeproj
```

`PulsoLinkCore` 不依赖 UIKit / SwiftUI，在 Linux 上也能 `swift build` / `swift test`（Keychain 与 JWT 解码只在 Apple 平台编译）。

## 文案

文案以 Android 为准，iOS 不手写 `.xcstrings`。改完 Android 的 `strings_*.xml` 后重新生成：

```sh
python3 Scripts/android_strings.py          # 写入
python3 Scripts/android_strings.py --check  # 只检查是否过期
```

## 图片

图片同样以 Android 为准：`res/drawable-nodpi`（`_light` / `_dark` 合成一张带深色版本的图，`drawable-zh-nodpi` 是中文版）
和 `.icons/inputs/logos`（App 图标，浅色 / 深色）。改了之后重新生成：

```sh
python3 Scripts/android_assets.py          # 写入（需要 Pillow）
python3 Scripts/android_assets.py --check  # 只检查是否过期
```

## 枚举

闭集取值（wire 枚举、带文案的选项）也以 Android 为准：`pulsolink-core/base/enums`、`pulsoloop/enums`、`pulsonear/enums`
里每个 `enum class` 生成一个 Swift 枚举（放在各模块的 `Enums/Generated/`）。Android 枚举里的 companion 常量和函数不生成，
需要时在旁边的 `*+Members.swift` 里手写。

```sh
python3 Scripts/android_enums.py          # 写入，并列出没生成的成员
python3 Scripts/android_enums.py --check  # 只检查是否过期
```

## DTO

接口的数据结构也以 Android 为准：各 App 的 `*/dto/*.kt` 和 core 的 communication / location / payments / resource 里每个
`@Serializable data class` 生成一个 Swift 结构（`Data/Generated/`），读写规则和 Android `WireJson` 一样：缺字段或 null 用
Kotlin 默认值，`@JsonNames` 的别名能读，写出时不带 nil 和等于默认值的字段。`@JsonClassDiscriminator` 的 sealed 接口生成带
关联值的 enum。auth / social / asset 的 DTO 在 core 里手写。

```sh
python3 Scripts/android_dtos.py          # 写入，并列出没生成的部分（类体里的成员、非 Serializable 的类）
python3 Scripts/android_dtos.py --check  # 只检查是否过期
```

## API

接口路径和参数也以 Android 为准：每个 Retrofit `interface`（`*/api/*.kt`）生成一个 Swift 结构（`Data/Generated/*API.swift`），
每个端点一个方法，方法、路径、`@Path` / `@Query` / `@Header` / `@Body` 与 Android 一致；用公开还是带 Bearer 的客户端，
在注册依赖的地方决定（和 Android 的 DI 限定符一样）。core 的 auth / social / asset 接口是手写的。

```sh
python3 Scripts/android_apis.py          # 写入，并列出没生成的端点（原始字节流）
python3 Scripts/android_apis.py --check  # 只检查是否过期
```

## Linux 上测 core

Swift 6.2 的 Linux 工具链里 `libswiftObservation.so` 有一个未解析符号，链接测试时要加一个参数（6.4 不需要）：

```sh
swift test -Xlinker --allow-shlib-undefined
```
