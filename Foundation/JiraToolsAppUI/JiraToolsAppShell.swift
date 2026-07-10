import SwiftUI

public enum JiraToolsDestination: Hashable {
    case staleTickets
}

public struct JiraToolsAppShell<StaleTicketsContent: View>: View {
    @State private var selection: JiraToolsDestination? = .staleTickets

    private let staleTicketsContent: () -> StaleTicketsContent

    public init(
        @ViewBuilder staleTicketsContent: @escaping () -> StaleTicketsContent,
    ) {
        self.staleTicketsContent = staleTicketsContent
    }

    public var body: some View {
        NavigationSplitView {
            List(selection: $selection) {
                Section("Tools") {
                    Label("Stale Tickets", systemImage: "clock.badge.exclamationmark")
                        .tag(JiraToolsDestination.staleTickets)
                }
            }
            .navigationTitle("Jira Tools")
            .frame(minWidth: 180)
        } detail: {
            switch selection {
            case .staleTickets:
                staleTicketsContent()
            case nil:
                VStack(spacing: 8) {
                    Image(systemName: "sidebar.left")
                        .font(.largeTitle)
                        .foregroundStyle(.secondary)
                    Text("Select a tool")
                        .font(.headline)
                }
            }
        }
    }
}
