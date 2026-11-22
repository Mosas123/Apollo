// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "V2RecoveryGRDBFixture",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "V2RecoveryGRDBFixture", targets: ["V2RecoveryGRDBFixture"])
    ],
    dependencies: [
        .package(url: "https://github.com/groue/GRDB.swift.git", exact: "7.12.0")
    ],
    targets: [
        .executableTarget(
            name: "V2RecoveryGRDBFixture",
            dependencies: [.product(name: "GRDB", package: "GRDB.swift")]
        )
    ]
)
