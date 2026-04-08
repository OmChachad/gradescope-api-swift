// swift-tools-version: 6.2

import PackageDescription

let package = Package(
    name: "GradescopeAPI",
    platforms: [
        .iOS(.v15),
        .macOS(.v12),
    ],
    products: [
        .library(
            name: "GradescopeAPI",
            targets: ["GradescopeAPI"]
        ),
    ],
    targets: [
        .target(
            name: "GradescopeAPI"
        ),
        .executableTarget(
            name: "GradescopeAPISmokeCheck",
            dependencies: ["GradescopeAPI"]
        ),
        .executableTarget(
            name: "GradescopeAPIWebKitCheck",
            dependencies: ["GradescopeAPI"]
        ),
    ]
)
