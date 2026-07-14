// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "NextUp",
    platforms: [.macOS(.v14)],
    products: [.executable(name: "NextUp", targets: ["NextUp"])],
    targets: [
        .executableTarget(
            name: "NextUp",
            path: "Sources/NextUp",
            exclude: ["Resources"],
            linkerSettings: [
                .linkedFramework("SwiftUI"),
                .linkedFramework("AppKit"),
                .linkedFramework("Charts"),
                .linkedFramework("Security")
            ]
        ),
        .testTarget(
            name: "NextUpTests",
            dependencies: ["NextUp"],
            path: "Tests/NextUpTests"
        )
    ]
)
