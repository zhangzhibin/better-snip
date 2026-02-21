// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "MacScreenshot",
    platforms: [.macOS(.v12)],
    targets: [
        .executableTarget(
            name: "MacScreenshot",
            path: "Sources/MacScreenshot",
            linkerSettings: [
                .linkedFramework("Cocoa"),
                .linkedFramework("CoreGraphics"),
            ]
        ),
    ]
)
