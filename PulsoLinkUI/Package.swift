// swift-tools-version: 6.2
import PackageDescription

// Shared SwiftUI layer for every CityPulso iOS app (Android `pulsolink-ui`):
// accent theme, thin compositions over native SwiftUI controls, and the session model. iOS only.
let package = Package(
    name: "PulsoLinkUI",
    defaultLocalization: "zh-Hans",
    platforms: [.iOS(.v26)],
    products: [
        .library(name: "PulsoLinkUI", targets: ["PulsoLinkUI"]),
    ],
    dependencies: [
        .package(path: "../PulsoLinkCore"),
        .package(url: "https://github.com/hmlongco/Factory.git", from: "2.4.0"),
    ],
    targets: [
        .target(
            name: "PulsoLinkUI",
            dependencies: ["PulsoLinkCore", "Factory"],
            resources: [.process("Resources")]
        ),
    ]
)
