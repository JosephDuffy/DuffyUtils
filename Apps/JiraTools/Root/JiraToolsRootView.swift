import JiraToolsAppUI
import JiraToolsStaleTicketsUI
import SwiftUI

struct JiraToolsRootView: View {
    @Environment(\.openWindow) private var openWindow
    @EnvironmentObject private var coordinator: JiraToolsAppCoordinator

    var body: some View {
        JiraToolsAppShell(
            items: coordinator.sidebarItems,
            selection: $coordinator.selectedToolID,
            addTool: coordinator.presentNewTool,
            removeTool: coordinator.removeSelectedTool,
        ) { id in
            toolContent(for: id)
        }
        .frame(minWidth: 900, minHeight: 560)
        .sheet(isPresented: $coordinator.isNewToolPresented) {
            NewToolView(addTool: coordinator.addTool)
        }
    }

    @ViewBuilder
    private func toolContent(for id: JiraToolInstance.ID) -> some View {
        switch coordinator.tool(for: id)?.tool {
        case .staleTickets:
            if let instance = coordinator.tool(for: id),
               let viewModel = coordinator.staleTicketsViewModel(for: id) {
                StaleTicketsView(
                    title: instance.staleTicketsPreferences.displayName,
                    viewModel: viewModel,
                )
            } else {
                credentialsRequiredView
            }
        case nil:
            VStack(spacing: 8) {
                Image(systemName: "questionmark.folder")
                    .font(.largeTitle)
                    .foregroundStyle(.secondary)
                Text("Tool Not Found")
                    .font(.headline)
            }
        }
    }

    private var credentialsRequiredView: some View {
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
