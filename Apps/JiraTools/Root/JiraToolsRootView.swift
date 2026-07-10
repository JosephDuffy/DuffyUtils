import JiraToolsAppUI
import JiraToolsStaleTicketsUI
import SwiftUI

struct JiraToolsRootView: View {
    @Environment(\.openWindow) private var openWindow
    @EnvironmentObject private var coordinator: JiraToolsAppCoordinator

    var body: some View {
        JiraToolsAppShell {
            if let viewModel = coordinator.staleTicketsViewModel {
                StaleTicketsView(viewModel: viewModel)
            } else {
                VStack(spacing: 12) {
                    Image(systemName: "key.fill")
                        .font(.largeTitle)
                        .foregroundStyle(.secondary)
                    Text("Add Jira credentials to get started")
                        .font(.headline)
                    Button("Open Jira Credentials") {
                        openWindow(id: JiraToolsWindow.credentials)
                    }
                }
            }
        }
        .frame(minWidth: 900, minHeight: 560)
    }
}
