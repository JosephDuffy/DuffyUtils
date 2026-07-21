import JiraAPI
import JiraToolsStaleTickets
import SwiftUI

struct StaleTicketsTicketInspector: View {
    let row: StaleTicketsTableRow?
    let extraFields: [JiraField]
    let issueURL: URL?

    var body: some View {
        Group {
            if let row {
                ScrollView {
                    VStack(alignment: .leading, spacing: 20) {
                        metadata(for: row)
                        comments(for: row)
                    }
                    .padding()
                }
            } else {
                StaleTicketsTicketInspectorEmptyState(
                    title: "Select a Ticket",
                    systemImage: "ticket",
                    message: "Select a ticket to view its metadata and comments.",
                )
            }
        }
        .navigationTitle("Ticket Details")
    }

    private func metadata(for row: StaleTicketsTableRow) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(row.summary)
                .font(.title3)
                .fontWeight(.semibold)
                .textSelection(.enabled)

            Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 8) {
                metadataRow("Severity") {
                    Text(row.severityLabel)
                        .foregroundStyle(severityColor(for: row))
                }
                metadataRow("Key") {
                    if let issueURL {
                        Link(row.key, destination: issueURL)
                    } else {
                        Text(row.key)
                    }
                }
                metadataRow("Status") {
                    Text(row.status)
                }
                metadataRow("Assignee") {
                    Text(row.assignee)
                }
                metadataRow("Latest comment") {
                    Text(dateText(row.report.latestCommentDate, missing: "None"))
                }
                metadataRow("Latest reply") {
                    Text(dateText(row.report.latestReplyDate, missing: "None"))
                }
                metadataRow("Your comment") {
                    Text(dateText(row.report.latestCurrentUserCommentDate, missing: "Never"))
                }
                metadataRow("Assignee comment") {
                    Text(dateText(row.report.latestAssigneeCommentDate, missing: "Never"))
                }

                ForEach(extraFields, id: \.id) { field in
                    metadataRow(field.name) {
                        Text(row.extraFieldValue(for: field.id))
                            .textSelection(.enabled)
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func comments(for row: StaleTicketsTableRow) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Comments")
                .font(.headline)

            if row.report.areCommentsLoading {
                HStack(spacing: 8) {
                    ProgressView()
                        .controlSize(.small)
                    Text("Loading comments…")
                        .foregroundStyle(.secondary)
                }
            } else if let error = row.report.error {
                Label(error, systemImage: "exclamationmark.triangle.fill")
                    .foregroundStyle(.red)
                    .textSelection(.enabled)
            } else if row.report.comments.isEmpty {
                StaleTicketsTicketInspectorEmptyState(
                    title: "No Comments",
                    systemImage: "text.bubble",
                    message: "No comments have been added to this ticket.",
                )
            } else {
                StaleTicketsCommentThreadView(comments: row.report.comments)
            }
        }
    }

    private func metadataRow<Content: View>(
        _ label: String,
        @ViewBuilder content: () -> Content,
    ) -> some View {
        GridRow {
            Text(label)
                .foregroundStyle(.secondary)
            content()
        }
    }

    private func dateText(_ date: Date?, missing: String) -> String {
        guard let date else {
            return missing
        }

        return date.formatted(.relative(presentation: .named))
    }

    private func severityColor(for row: StaleTicketsTableRow) -> Color {
        switch row.report.severity {
        case .error:
            .red
        case .warning:
            .orange
        case .neutral:
            .secondary
        case .ok:
            .green
        }
    }
}

private struct StaleTicketsCommentThreadView: View {
    let comments: [JiraComment]

    var body: some View {
        let thread = StaleTicketsCommentThread.make(from: comments)
        VStack(alignment: .leading, spacing: 12) {
            commentNodes(thread)
        }
    }

    private func commentNodes(_ nodes: [StaleTicketsCommentThreadNode]) -> AnyView {
        AnyView(
            ForEach(nodes) { node in
                VStack(alignment: .leading, spacing: 12) {
                    StaleTicketsCommentView(comment: node.comment)

                    if !node.replies.isEmpty {
                        commentNodes(node.replies)
                            .padding(.leading, 16)
                    }
                }
            },
        )
    }
}

private struct StaleTicketsCommentView: View {
    let comment: JiraComment

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Text(comment.author.displayName ?? comment.author.accountId)
                    .fontWeight(.semibold)
                Text(comment.createdDateText)
                    .foregroundStyle(.secondary)
                if let updated = comment.updatedDateText {
                    Text("(edited \(updated))")
                        .foregroundStyle(.secondary)
                }
            }
            .font(.caption)

            if let body = comment.body {
                StaleTicketsCommentBodyView(commentBody: body)
            } else {
                Text("Comment content is unavailable.")
                    .foregroundStyle(.secondary)
            }
        }
        .padding(12)
        .background(Color.secondary.opacity(0.12), in: RoundedRectangle(cornerRadius: 8))
    }
}

private struct StaleTicketsTicketInspectorEmptyState: View {
    let title: String
    let systemImage: String
    let message: String

    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: systemImage)
                .font(.title2)
                .foregroundStyle(.secondary)
            Text(title)
                .font(.headline)
            Text(message)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding()
    }
}

private extension JiraComment {
    var createdDateText: String {
        guard let date = parseJiraDate(created) else {
            return created
        }

        return date.formatted(.relative(presentation: .named))
    }

    var updatedDateText: String? {
        guard let updated else {
            return nil
        }

        guard let date = parseJiraDate(updated) else {
            return updated
        }

        return date.formatted(.relative(presentation: .named))
    }
}
