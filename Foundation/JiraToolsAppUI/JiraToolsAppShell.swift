import Foundation
import SwiftUI

public struct JiraToolsSidebarItem: Identifiable, Hashable {
    public let id: UUID
    public let title: String
    public let systemImage: String

    public init(
        id: UUID,
        title: String,
        systemImage: String,
    ) {
        self.id = id
        self.title = title
        self.systemImage = systemImage
    }
}

public struct JiraToolsAppShell<Detail: View>: View {
    @Binding private var selection: JiraToolsSidebarItem.ID?

    private let items: [JiraToolsSidebarItem]
    private let addTool: () -> Void
    private let detail: (JiraToolsSidebarItem.ID) -> Detail
    private let removeTool: () -> Void

    public init(
        items: [JiraToolsSidebarItem],
        selection: Binding<JiraToolsSidebarItem.ID?>,
        addTool: @escaping () -> Void,
        removeTool: @escaping () -> Void,
        @ViewBuilder detail: @escaping (JiraToolsSidebarItem.ID) -> Detail,
    ) {
        self.items = items
        _selection = selection
        self.addTool = addTool
        self.removeTool = removeTool
        self.detail = detail
    }

    public var body: some View {
        NavigationSplitView {
            List(selection: $selection) {
                Section("Tools") {
                    ForEach(items) { item in
                        Label(item.title, systemImage: item.systemImage)
                            .tag(item.id)
                    }
                }
            }
            .navigationTitle("Jira Tools")
            .frame(minWidth: 180)
            .safeAreaInset(edge: .bottom) {
                HStack(spacing: 0) {
                    Button(action: addTool) {
                        Label("Add Tool", systemImage: "plus")
                    }
                    .buttonStyle(.borderless)

                    Divider()
                        .frame(height: 16)
                        .padding(.horizontal, 6)

                    Button(action: removeTool) {
                        Label("Remove Tool", systemImage: "minus")
                    }
                    .buttonStyle(.borderless)
                    .disabled(selection == nil)

                    Spacer()
                }
                .padding(8)
                .background(.bar)
            }
        } detail: {
            if let selection {
                detail(selection)
            } else {
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
