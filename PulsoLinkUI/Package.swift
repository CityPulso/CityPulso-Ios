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
        .package(url: "https://github.com/google/GoogleSignIn-iOS.git", from: "8.0.0"),
        .package(url: "https://github.com/kean/Nuke.git", from: "12.8.0"),
    ],
    targets: [
        .target(
            name: "PulsoLinkUI",
            dependencies: [
                "PulsoLinkCore",
                "Factory",
                .product(name: "GoogleSignIn", package: "GoogleSignIn-iOS"),
                "Nuke",
                .product(name: "NukeUI", package: "Nuke"),
            ],
            resources: [.process("Resources")]
        ),
    ]
)
