// swift-tools-version: 6.3
import PackageDescription

let package = Package(
    name: "ApolloTube",
    platforms: [.iOS(.v17), .macOS(.v13)],
    products: [
        .library(name: "ApolloTube", type: .static, targets: ["ApolloTube"])
    ],
    targets: [
        .target(
            name: "ApolloTube",
            path: "ApolloTube",
            resources: [.copy("po_token.html"), .copy("player_configs.json")]
        ),
        .testTarget(name: "ApolloTubeTests", dependencies: ["ApolloTube"])
    ],
    swiftLanguageModes: [.v6]
)
