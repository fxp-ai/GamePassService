// swift-tools-version:6.0
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "GamePassService",
    platforms: [.macOS(.v15)],
    products: [
        .executable(name: "GamePassService", targets: ["GamePassService"]),
    ],
    dependencies: [
        .package(url: "https://github.com/hummingbird-project/hummingbird.git", from: "2.0.0"),
        .package(url: "https://github.com/vapor/postgres-nio.git", from: "1.21.0"),
        .package(url: "https://github.com/apple/swift-argument-parser.git", from: "1.3.0"),
        .package(url: "https://github.com/pultar/GamePassKit.git", branch: "main"),
        .package(url: "https://github.com/pultar/GamePassShared.git", branch: "main"),
        .package(url: "https://github.com/twostraws/SwiftGD.git", from: "2.0.0"),
    ],
    targets: [
        .executableTarget(name: "GamePassService",
            dependencies: [
                .product(name: "ArgumentParser", package: "swift-argument-parser"),
                .product(name: "Hummingbird", package: "hummingbird"),
                .product(name: "PostgresNIO", package: "postgres-nio"),
                .product(name: "GamePassKit", package: "GamePassKit"),
                .product(name: "GamePassShared", package: "GamePassShared"),
                .product(name: "SwiftGD", package: "SwiftGD"),
            ],
            path: "Sources/App"
        ),
        .testTarget(name: "GamePassServiceTests",
            dependencies: [
                .byName(name: "GamePassService"),
                .product(name: "HummingbirdTesting", package: "hummingbird"),
            ],
            path: "Tests/AppTests"
        )
    ]
)
