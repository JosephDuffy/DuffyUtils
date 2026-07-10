import SwiftUI

struct NewToolView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var tool = JiraToolIdentifier.staleTickets

    let addTool: (JiraToolIdentifier) -> Void

    var body: some View {
        VStack(spacing: 0) {
            Form {
                Picker("Tool", selection: $tool) {
                    Text("Stale Tickets")
                        .tag(JiraToolIdentifier.staleTickets)
                }
            }
            .formStyle(.grouped)

            Divider()

            HStack {
                Spacer()
                Button("Cancel", role: .cancel) {
                    dismiss()
                }
                Button("Add Tool") {
                    addTool(tool)
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
            }
            .padding()
        }
        .frame(width: 400, height: 140)
    }
}
