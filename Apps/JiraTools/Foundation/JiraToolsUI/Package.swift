// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "JiraToolsUI",
    platforms: [
        .macOS(.v13),
    ],
    products: [
        .library(
            name: "JiraToolsUI",
            targets: ["JiraToolsUI"],
        ),
    ],
    targets: [
        .target(name: "JiraToolsUI"),
    ],
)
