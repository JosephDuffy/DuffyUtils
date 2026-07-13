// swift-tools-version: 6.2
import CompilerPluginSupport
import PackageDescription

let package = Package(
    name: "DuffyUtils",
    platforms: [
        .macOS(.v13),
    ],
    products: [
        .library(
            name: "JiraToolsCore",
            targets: ["JiraToolsCore"],
        ),
        .library(
            name: "JiraToolsStaleTickets",
            targets: ["JiraToolsStaleTickets"],
        ),
        .library(
            name: "JiraToolsAppFoundation",
            targets: ["JiraToolsAppFoundation"],
        ),
        .library(
            name: "JiraToolsStaleTicketsUI",
            targets: ["JiraToolsStaleTicketsUI"],
        ),
        .library(
            name: "JiraToolsAppUI",
            targets: ["JiraToolsAppUI"],
        ),
        .executable(
            name: "jira-tools",
            targets: ["JiraToolsCLI"],
        ),
    ],
    dependencies: [
        .package(url: "https://github.com/apple/swift-argument-parser.git", from: "1.6.2"),
        .package(url: "https://github.com/swiftlang/swift-subprocess.git", branch: "main"),
        .package(url: "https://github.com/swiftlang/swift-syntax", "510.0.0" ..< "602.999.99"),
    ],
    targets: [
        .executableTarget(
            name: "install",
            dependencies: [
                .product(name: "ArgumentParser", package: "swift-argument-parser"),
                .product(name: "Subprocess", package: "swift-subprocess"),
            ]
        ),
        .executableTarget(
            name: "export-signed-command",
            dependencies: [
                .product(name: "ArgumentParser", package: "swift-argument-parser"),
                .product(name: "Subprocess", package: "swift-subprocess"),
            ]
        ),
        .executableTarget(
            name: "export-signed-app",
            dependencies: [
                .product(name: "ArgumentParser", package: "swift-argument-parser"),
                .product(name: "Subprocess", package: "swift-subprocess"),
            ]
        ),
        .executableTarget(
            name: "git-new-branch-and-worktree",
            dependencies: [
                .product(name: "ArgumentParser", package: "swift-argument-parser"),
                "DuffyUtilsInternals",
                .product(name: "Subprocess", package: "swift-subprocess"),
            ]
        ),
        .executableTarget(
            name: "JiraToolsCLI",
            dependencies: [
                .product(name: "ArgumentParser", package: "swift-argument-parser"),
                "DuffyUtilsInternals",
                "JiraToolsCore",
                "JiraToolsStaleTickets",
            ],
            path: "Sources/JiraToolsCLI",
        ),
        .target(
            name: "JiraToolsCore",
            path: "Sources/JiraToolsCore",
        ),
        .target(
            name: "JiraToolsStaleTickets",
            dependencies: ["JiraToolsCore"],
            path: "Sources/JiraToolsStaleTickets",
        ),
        .target(
            name: "JiraToolsAppFoundation",
            dependencies: ["JiraToolsCore"],
            path: "Foundation/JiraToolsAppFoundation",
        ),
        .target(
            name: "JiraToolsStaleTicketsUI",
            dependencies: [
                "JiraToolsAppFoundation",
                "JiraToolsCore",
                "JiraToolsStaleTickets",
            ],
            path: "Features/StaleTickets/JiraToolsStaleTicketsUI",
        ),
        .target(
            name: "JiraToolsAppUI",
            path: "Foundation/JiraToolsAppUI",
        ),
        .executableTarget(
            name: "open-in-jira",
            dependencies: [
                .product(name: "ArgumentParser", package: "swift-argument-parser"),
                "DuffyUtilsInternals",
                .product(name: "Subprocess", package: "swift-subprocess"),
            ]
        ),
        .executableTarget(
            name: "git-checkout-pr-in-worktree",
            dependencies: [
                .product(name: "ArgumentParser", package: "swift-argument-parser"),
                "DuffyUtilsInternals",
                .product(name: "Subprocess", package: "swift-subprocess"),
            ]
        ),
        .executableTarget(
            name: "git-remove-current-worktree-and-branch",
            dependencies: [
                .product(name: "ArgumentParser", package: "swift-argument-parser"),
                "DuffyUtilsInternals",
                .product(name: "Subprocess", package: "swift-subprocess"),
            ]
        ),
        .target(
            name: "DuffyUtilsInternals",
            dependencies: [
                .product(name: "ArgumentParser", package: "swift-argument-parser"),
                "DuffyUtilsFoundation",
                "DuffyUtilsMacros",
                .product(name: "Subprocess", package: "swift-subprocess"),
            ]
        ),
        .target(
            name: "DuffyUtilsFoundation"
        ),
        .macro(
            name: "DuffyUtilsMacros",
            dependencies: [
                "DuffyUtilsFoundation",
                .product(name: "SwiftDiagnostics", package: "swift-syntax"),
                .product(name: "SwiftSyntax", package: "swift-syntax"),
                .product(name: "SwiftSyntaxMacros", package: "swift-syntax"),
                .product(name: "SwiftCompilerPlugin", package: "swift-syntax"),
            ]
        ),
        .testTarget(
            name: "JiraToolsCoreTests",
            dependencies: ["JiraToolsCore"],
        ),
        .testTarget(
            name: "JiraToolsStaleTicketsTests",
            dependencies: [
                "JiraToolsStaleTickets",
                "JiraToolsStaleTicketsUI",
            ],
        ),
        .testTarget(
            name: "JiraToolsAppFoundationTests",
            dependencies: ["JiraToolsAppFoundation"],
        ),
    ]
)
