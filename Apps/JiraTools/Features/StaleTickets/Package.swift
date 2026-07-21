// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "JiraToolsStaleTicketsFeature",
    platforms: [
        .macOS(.v13),
    ],
    products: [
        .library(
            name: "JiraToolsStaleTickets",
            targets: ["JiraToolsStaleTickets"],
        ),
        .library(
            name: "JiraToolsStaleTicketsUI",
            targets: ["JiraToolsStaleTicketsUI"],
        ),
    ],
    dependencies: [
        .package(path: "../../Foundation/JiraToolsFoundation"),
        .package(path: "../../Services/JiraAPI"),
        .package(url: "https://github.com/JosephDuffy/UseCaseMacro.git", branch: "main"),
    ],
    targets: [
        .target(
            name: "JiraToolsStaleTickets",
            dependencies: [
                "JiraAPI",
                "JiraToolsFoundation",
            ],
        ),
        .target(
            name: "JiraToolsStaleTicketsUI",
            dependencies: [
                "JiraAPI",
                "JiraToolsFoundation",
                "JiraToolsStaleTickets",
                .product(name: "UseCaseMacro", package: "UseCaseMacro"),
            ],
        ),
        .testTarget(
            name: "JiraToolsStaleTicketsTests",
            dependencies: [
                "JiraAPI",
                "JiraToolsFoundation",
                "JiraToolsStaleTickets",
            ],
        ),
        .testTarget(
            name: "JiraToolsStaleTicketsUITests",
            dependencies: [
                "JiraAPI",
                "JiraToolsStaleTickets",
                "JiraToolsStaleTicketsUI",
            ],
        ),
    ],
)
