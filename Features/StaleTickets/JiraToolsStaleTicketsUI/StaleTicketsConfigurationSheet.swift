import JiraToolsAppFoundation
import JiraToolsCore
import JiraToolsStaleTickets
import SwiftUI

struct StaleTicketsConfigurationSheet: View {
    @Binding var draft: StaleTicketsConfigurationDraft
    let onSave: () -> Bool
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 0) {
            Form {
                Section("Tool") {
                    TextField("Name", text: $draft.displayName)
                }

                Section("Jira Query") {
                    TextField("Jira site URL", text: $draft.baseURL, prompt: Text("example.atlassian.net"))
                        .onSubmit {
                            normalizeBaseURL()
                        }
                    Picker("Query type", selection: $draft.queryMode) {
                        Text("Saved filter").tag(StaleTicketsQueryMode.filter)
                        Text("JQL").tag(StaleTicketsQueryMode.jql)
                    }
                    .pickerStyle(.radioGroup)
                    TextField(queryInputLabel, text: $draft.filterInput, axis: .vertical)
                        .lineLimit(2...5)
                }

                Section("Displayed Fields") {
                    TextField("Extra fields, comma separated", text: $draft.extraFields, axis: .vertical)
                        .lineLimit(2...4)
                    TextField("Deemphasized statuses, comma separated", text: $draft.deemphasizedStatuses)
                }

                Section("Staleness") {
                    highlightedSourceToggle(.currentUser, label: "Your top-level comments")
                    highlightedSourceToggle(.assignee, label: "Assignee top-level comments")
                    highlightedSourceToggle(.anyUser, label: "Any top-level comments")

                    TextField("Green hours", value: $draft[hours: \.okDuration], format: .number)
                    TextField("Warning hours", value: $draft[hours: \.warningDuration], format: .number)
                    TextField("Error hours", value: $draft[hours: \.errorDuration], format: .number)
                }

                Section("Refresh") {
                    TextField("Result limit", value: $draft.maxResults, format: .number)
                    TextField("Refresh interval (seconds)", value: $draft.refreshInterval, format: .number)
                    Picker("Service sort", selection: $draft.serviceSort) {
                        Text("Latest comment").tag(TicketSort.latestComment)
                        Text("Your comment").tag(TicketSort.currentUser)
                        Text("Assignee comment").tag(TicketSort.assignee)
                    }
                }

                Section("Watch Alerts") {
                    alertSeverityToggle(.warning, label: "Warning tickets")
                    alertSeverityToggle(.error, label: "Error tickets")
                    Picker("Alert mode", selection: $draft.alertMode) {
                        Text("Notification").tag(JiraToolsAlertMode.notification)
                        Text("Sound").tag(JiraToolsAlertMode.sound)
                        Text("Notification and sound").tag(JiraToolsAlertMode.both)
                        Text("None").tag(JiraToolsAlertMode.none)
                    }
                }
            }
            .formStyle(.grouped)

            Divider()

            HStack {
                Spacer()
                Button("Cancel", role: .cancel) {
                    dismiss()
                }
                Button("Save") {
                    if onSave() {
                        dismiss()
                    }
                }
                .keyboardShortcut(.defaultAction)
            }
            .padding()
        }
        .frame(minWidth: 560, minHeight: 570)
    }

    private func highlightedSourceToggle(
        _ source: HighlightedCommentSource,
        label: String,
    ) -> some View {
        Toggle(
            label,
            isOn: Binding(
                get: { draft.highlightedCommentSources.contains(source) },
                set: { isEnabled in
                    if isEnabled {
                        draft.highlightedCommentSources.insert(source)
                    } else {
                        draft.highlightedCommentSources.remove(source)
                    }
                },
            ),
        )
    }

    private func alertSeverityToggle(
        _ severity: Severity,
        label: String,
    ) -> some View {
        Toggle(
            label,
            isOn: Binding(
                get: { draft.alertSeverities.contains(severity) },
                set: { isEnabled in
                    if isEnabled {
                        draft.alertSeverities.insert(severity)
                    } else {
                        draft.alertSeverities.remove(severity)
                    }
                },
            ),
        )
    }

    private func normalizeBaseURL() {
        guard let url = jiraURL(from: draft.baseURL) else {
            return
        }

        draft.baseURL = url.absoluteString
    }

    private var queryInputLabel: String {
        switch draft.queryMode {
        case .filter:
            "Filter URL or numeric filter ID"
        case .jql:
            "JQL query"
        }
    }
}
