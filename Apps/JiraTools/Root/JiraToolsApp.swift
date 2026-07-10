import SwiftUI

enum JiraToolsWindow {
    static let credentials = "jira-credentials"
}

@main
struct JiraToolsApp: App {
    @Environment(\.openWindow) private var openWindow
    @StateObject private var coordinator = JiraToolsAppCoordinator()

    var body: some Scene {
        WindowGroup {
            JiraToolsRootView()
                .environmentObject(coordinator)
                .task {
                    if coordinator.shouldOpenCredentialsWindow {
                        openWindow(id: JiraToolsWindow.credentials)
                    }
                }
        }
        .commands {
            CommandGroup(after: .windowArrangement) {
                Button("Jira Credentials…") {
                    openWindow(id: JiraToolsWindow.credentials)
                }
                .keyboardShortcut(",", modifiers: [.command, .option])
            }
        }

        Window("Jira Credentials", id: JiraToolsWindow.credentials) {
            JiraCredentialsView()
                .environmentObject(coordinator)
        }
        .defaultSize(width: 480, height: 340)
    }
}
