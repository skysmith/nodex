// swift-tools-version: 5.9

import PackageDescription

let package = Package(
    name: "Nodex",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .executable(name: "nodex", targets: ["nodex"])
    ],
    targets: [
        .executableTarget(
            name: "nodex",
            exclude: ["Info.plist"],
            linkerSettings: [
                .linkedFramework("CoreMotion"),
                .linkedFramework("AppKit"),
                .unsafeFlags([
                    "-Xlinker", "-sectcreate",
                    "-Xlinker", "__TEXT",
                    "-Xlinker", "__info_plist",
                    "-Xlinker", "Sources/nodex/Info.plist"
                ])
            ]
        ),
        .testTarget(
            name: "NodexTests"
        )
    ],
    swiftLanguageVersions: [.v5]
)
