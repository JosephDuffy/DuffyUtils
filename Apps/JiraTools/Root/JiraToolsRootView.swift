import JiraToolsAppUI
import JiraToolsStaleTicketsUI
import SwiftUI

struct JiraToolsRootView: View {
    @Environment(\.openWindow) private var openWindow
    @EnvironmentObject private var coordinator: JiraToolsAppCoordinator
    @State private var hasInitializedUIState = false
    @State private var isNewToolPresented = false
    @State private var selectedToolID: JiraToolInstance.ID?

    var body: some View {
        JiraToolsAppShell(
            items: coordinator.sidebarItems,
            selection: $selectedToolID,
            addTool: {
                isNewToolPresented = true
            },
            removeTool: removeSelectedTool,
        ) { id in
            toolContent(for: id)
        }
        .frame(minWidth: 900, minHeight: 560)
        .focusedValue(
            \.jiraToolsNewToolAction,
            JiraToolsNewToolAction {
                isNewToolPresented = true
            },
        )
        .onAppear {
            guard !hasInitializedUIState else {
                return
            }

            hasInitializedUIState = true
            selectedToolID = coordinator.sidebarItems.first?.id
            isNewToolPresented = coordinator.sidebarItems.isEmpty
        }
        .onChange(of: coordinator.sidebarItems) { items in
            guard let selectedToolID,
                  items.contains(where: { $0.id == selectedToolID }) else {
                self.selectedToolID = items.first?.id
                return
            }
        }
        .sheet(isPresented: $isNewToolPresented) {
            NewToolView { tool in
                selectedToolID = coordinator.addTool(tool)
            }
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

    private func removeSelectedTool() {
        guard let selectedToolID else {
            return
        }

        coordinator.removeTool(id: selectedToolID)
    }
}
