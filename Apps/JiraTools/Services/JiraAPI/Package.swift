// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "JiraAPI",
    platforms: [
        .macOS(.v13),
    ],
    products: [
        .library(
            name: "JiraAPI",
            targets: ["JiraAPI"],
        ),
    ],
    dependencies: [
        .package(path: "../../Foundation/JiraToolsFoundation"),
    ],
    targets: [
        .target(
            name: "JiraAPI",
            dependencies: ["JiraToolsFoundation"],
        ),
        .testTarget(
            name: "JiraAPITests",
            dependencies: ["JiraAPI"],
        ),
    ],
)
