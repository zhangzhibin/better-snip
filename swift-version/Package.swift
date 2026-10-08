// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "MacScreenshot",
    platforms: [.macOS(.v12)],
    products: [
        .library(name: "Clibwebp", targets: ["Clibwebp"]),
        .executable(name: "MacScreenshot", targets: ["MacScreenshot"]),
    ],
    targets: [
        .target(
            name: "Clibwebp",
            path: "Vendor/libwebp",
            exclude: [
                "COPYING",
                "PATENTS",
                "src/demux",
                "src/mux",
            ],
            sources: ["src", "sharpyuv"],
            publicHeadersPath: "include",
            cSettings: [
                .headerSearchPath("."),
            ]
        ),
        .executableTarget(
            name: "MacScreenshot",
            dependencies: ["Clibwebp"],
            path: "Sources/MacScreenshot",
            linkerSettings: [
                .linkedFramework("Cocoa"),
                .linkedFramework("CoreGraphics"),
                .linkedFramework("Carbon"),
            ]
        ),
    ]
)
