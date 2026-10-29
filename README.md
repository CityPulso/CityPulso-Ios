# CityPulso-Ios

原生 SwiftUI 版 YouLoopy 跃圈 / YouNeary 娱邻，结构对齐 `CityPulso-Android`：

| iOS | Android |
|---|---|
| `Packages/PulsoLinkCore` | `pulsolink-core` |
| `Packages/PulsoLinkUI` | `pulsolink-ui` |
| `Apps/PulsoLoop` | `pulsoloop` |
| `Apps/PulsoNear` | `pulsonear` |

## 开发

需要 macOS + Xcode 16 以上：

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
python3 scripts/android_strings.py          # 写入
python3 scripts/android_strings.py --check  # 只检查是否过期
```
