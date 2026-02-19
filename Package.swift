// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "LXSTSwift",
    platforms: [
        .macOS(.v13),
        .iOS(.v16)
    ],
    products: [
        .library(
            name: "LXSTSwift",
            targets: ["LXSTSwift"]
        )
    ],
    dependencies: [
        .package(path: "../ReticulumSwift"),
    ],
    targets: [
        // C library shims (headers + linker settings)
        .target(
            name: "COpus",
            path: "Sources/COpus",
            publicHeadersPath: "include",
            linkerSettings: [
                .linkedLibrary("opus"),
            ]
        ),
        .target(
            name: "CCodec2",
            path: "Sources/CCodec2",
            publicHeadersPath: "include",
            linkerSettings: [
                .linkedLibrary("codec2"),
            ]
        ),
        .target(
            name: "LXSTSwift",
            dependencies: [
                "ReticulumSwift",
                // COpus and CCodec2 are optional — Swift code uses #if canImport()
            ],
            path: "Sources/LXSTSwift"
        ),
        .testTarget(
            name: "LXSTSwiftTests",
            dependencies: ["LXSTSwift"],
            path: "Tests/LXSTSwiftTests"
        ),
    ]
)
