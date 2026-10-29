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
