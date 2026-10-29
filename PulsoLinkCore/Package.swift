// swift-tools-version: 6.2
import PackageDescription

// Shared Link layer for every CityPulso iOS app (Android `pulsolink-core`):
// config, HTTP clients, auth session, enums, DTOs, repositories.
let package = Package(
    name: "PulsoLinkCore",
    platforms: [.iOS(.v26), .macOS(.v26)],
    products: [
        .library(name: "PulsoLinkCore", targets: ["PulsoLinkCore"]),
    ],
    dependencies: [
        .package(url: "https://github.com/Alamofire/Alamofire.git", from: "5.10.2"),
        .package(url: "https://github.com/auth0/JWTDecode.swift.git", from: "3.2.0"),
        .package(url: "https://github.com/marksands/BetterCodable.git", from: "0.4.0"),
        .package(url: "https://github.com/kishikawakatsumi/KeychainAccess.git", from: "4.2.2"),
        .package(url: "https://github.com/hmlongco/Factory.git", from: "2.4.0"),
    ],
    targets: [
        .target(
            name: "PulsoLinkCore",
            dependencies: [
                "Alamofire",
                .product(
                    name: "JWTDecode",
                    package: "JWTDecode.swift",
                    condition: .when(platforms: [.iOS, .macOS])
                ),
                "BetterCodable",
                .product(
                    name: "KeychainAccess",
                    package: "KeychainAccess",
                    condition: .when(platforms: [.iOS, .macOS])
                ),
                "Factory",
            ]
        ),
        .testTarget(name: "PulsoLinkCoreTests", dependencies: ["PulsoLinkCore"]),
    ]
)
