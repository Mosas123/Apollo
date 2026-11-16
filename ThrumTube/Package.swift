// swift-tools-version: 6.3
import PackageDescription

let package = Package(
    name: "SwiftyTube",
    platforms: [.iOS(.v17), .macOS(.v13)],
    products: [
        .library(name: "SwiftyTube", type: .static, targets: ["SwiftyTube"])
    ],
    targets: [
        .target(
            name: "SwiftyTube",
            path: "SwiftyTube",
            resources: [.copy("po_token.html"), .copy("player_configs.json")]
        ),
        .testTarget(name: "SwiftyTubeTests", dependencies: ["SwiftyTube"])
    ],
    swiftLanguageModes: [.v5]
)
