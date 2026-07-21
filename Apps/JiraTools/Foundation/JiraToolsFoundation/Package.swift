// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "JiraToolsFoundation",
    platforms: [
        .macOS(.v13),
    ],
    products: [
        .library(
            name: "JiraToolsFoundation",
            targets: ["JiraToolsFoundation"],
        ),
    ],
    targets: [
        .target(name: "JiraToolsFoundation"),
        .testTarget(
            name: "JiraToolsFoundationTests",
            dependencies: ["JiraToolsFoundation"],
        ),
    ],
)
