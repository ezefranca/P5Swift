// swift-tools-version: 6.2

import PackageDescription

let package = Package(
    name: "p5.swift",
    platforms: [.iOS(.v17), .macOS(.v14)],
    products: [
        .library(name: "P5", targets: ["P5"]),
        .executable(name: "P5SmokeSample", targets: ["P5SmokeSample"]),
    ],
    dependencies: [
        .package(
            url: "https://github.com/swiftlang/swift-testing",
            revision: "swift-6.2.3-RELEASE"
        )
    ],
    targets: [
        .target(
            name: "P5",
            resources: [
                .copy("Resources/P5Renderer3D.metal"),
                .process("Resources/PrivacyInfo.xcprivacy"),
            ]
        ),
        .testTarget(
            name: "P5Tests",
            dependencies: [
                "P5",
                .product(name: "Testing", package: "swift-testing"),
            ]
        ),
        .executableTarget(name: "P5SmokeSample", dependencies: ["P5"]),
    ],
    swiftLanguageModes: [.v6]
)
