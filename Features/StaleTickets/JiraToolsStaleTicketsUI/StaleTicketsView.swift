import JiraToolsStaleTickets
import SwiftUI

public struct StaleTicketsView: View {
    @ObservedObject private var viewModel: StaleTicketsViewModel
    @Environment(\.openURL) private var openURL

    public init(viewModel: StaleTicketsViewModel) {
        self.viewModel = viewModel
    }

    public var body: some View {
        Group {
            if let snapshot = viewModel.snapshot {
                results(snapshot)
            } else if viewModel.isRefreshing {
                StaleTicketsEmptyState(
                    title: "Refreshing Stale Tickets",
                    systemImage: "arrow.triangle.2.circlepath",
                    message: "Connecting to Jira and loading tickets.",
                    isProgressing: true,
                )
            } else {
                StaleTicketsEmptyState(
                    title: viewModel.isConfigured ? "No Stale Ticket Results" : "Configure Stale Tickets",
                    systemImage: viewModel.isConfigured ? "ticket" : "slider.horizontal.3",
                    message: viewModel.isConfigured
                        ? "Refresh to load tickets matching the configured Jira filter."
                        : "Choose a Jira filter or JQL query before refreshing tickets.",
                ) {
                    Button(viewModel.isConfigured ? "Refresh" : "Configure") {
                        if viewModel.isConfigured {
                            viewModel.refresh()
                        } else {
                            viewModel.isConfigurationPresented = true
                        }
                    }
                }
            }
        }
        .navigationTitle("Stale Tickets")
        .toolbar {
            ToolbarItemGroup(placement: .primaryAction) {
                Button(action: viewModel.refresh) {
                    Label("Refresh", systemImage: "arrow.clockwise")
                }
                .disabled(viewModel.isRefreshing || !viewModel.isConfigured)

                Toggle(isOn: $viewModel.isWatching) {
                    Label("Watch", systemImage: "eye")
                }
                .toggleStyle(.button)

                Button {
                    viewModel.isConfigurationPresented = true
                } label: {
                    Label("Configure", systemImage: "slider.horizontal.3")
                }
            }
        }
        .sheet(isPresented: $viewModel.isConfigurationPresented) {
            StaleTicketsConfigurationSheet(
                draft: $viewModel.configurationDraft,
                onSave: viewModel.saveConfigurationDraft,
            )
        }
        .alert(
            "Refresh Failed",
            isPresented: Binding(
                get: { viewModel.refreshError != nil },
                set: { isPresented in
                    if !isPresented {
                        viewModel.clearRefreshError()
                    }
                },
            ),
        ) {
            Button("OK", role: .cancel, action: viewModel.clearRefreshError)
        } message: {
            Text(viewModel.refreshError ?? "An unknown error occurred.")
        }
    }

    @ViewBuilder
    private func results(_ snapshot: StaleTicketsSnapshot) -> some View {
        VStack(spacing: 0) {
            if viewModel.isRefreshing {
                HStack(spacing: 8) {
                    ProgressView()
                        .controlSize(.small)
                    Text(progressDescription(for: snapshot))
                    Spacer()
                }
                .padding(8)
                .background(.bar)
            }

            if !snapshot.errors.isEmpty {
                HStack(alignment: .top, spacing: 8) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(.orange)
                    Text(snapshot.errors.joined(separator: "\n"))
                        .textSelection(.enabled)
                    Spacer()
                }
                .padding(8)
                .background(.orange.opacity(0.12))
            }

            if viewModel.rows.isEmpty, !viewModel.isRefreshing {
                StaleTicketsEmptyState(
                    title: "No Matching Tickets",
                    systemImage: "line.3.horizontal.decrease.circle",
                    message: "No tickets matched the configured Jira filter.",
                )
            } else {
                ticketsTable(snapshot)
            }
        }
    }

    @ViewBuilder
    private func ticketsTable(_ snapshot: StaleTicketsSnapshot) -> some View {
        if #available(macOS 14.4, *) {
            dynamicTicketsTable(snapshot)
        } else {
            fallbackTicketsTable()
        }
    }

    @available(macOS 14.4, *)
    private func dynamicTicketsTable(_ snapshot: StaleTicketsSnapshot) -> some View {
        Table(viewModel.rows, sortOrder: $viewModel.sortOrder) {
            standardColumns()
            TableColumnForEach(snapshot.extraFields, id: \.id) { field in
                TableColumn(field.name, sortUsing: StaleTicketsTableComparator(column: .extraField(field.id))) { row in
                    Text(row.extraFieldValue(for: field.id))
                }
                .width(min: 100, ideal: 150)
            }
            commentAndSummaryColumns()
        }
    }

    private func fallbackTicketsTable() -> some View {
        Table(viewModel.rows, sortOrder: $viewModel.sortOrder) {
            standardColumns()
            TableColumn("Extra Fields", sortUsing: StaleTicketsTableComparator(column: .extraFields)) { row in
                Text(row.extraFieldsDisplay.isEmpty ? "—" : row.extraFieldsDisplay)
                    .lineLimit(3)
            }
            .width(min: 150, ideal: 220)
            commentAndSummaryColumns()
        }
    }

    @TableColumnBuilder<StaleTicketsTableRow, StaleTicketsTableComparator>
    private func standardColumns() -> some TableColumnContent<StaleTicketsTableRow, StaleTicketsTableComparator> {
        TableColumn("Severity", sortUsing: StaleTicketsTableComparator(column: .severity)) { row in
            Text(row.severityLabel)
                .foregroundStyle(severityColor(for: row))
        }
        .width(min: 76, ideal: 88)

        TableColumn("Key", sortUsing: StaleTicketsTableComparator(column: .key)) { row in
            Button(row.key) {
                openURL(viewModel.issueURL(for: row))
            }
            .buttonStyle(.link)
        }
        .width(min: 80, ideal: 100)

        TableColumn("Status", sortUsing: StaleTicketsTableComparator(column: .status)) { row in
            Text(row.status)
        }
        .width(min: 90, ideal: 130)

        TableColumn("Assignee", sortUsing: StaleTicketsTableComparator(column: .assignee)) { row in
            Text(row.assignee)
        }
        .width(min: 100, ideal: 150)
    }

    @TableColumnBuilder<StaleTicketsTableRow, StaleTicketsTableComparator>
    private func commentAndSummaryColumns() -> some TableColumnContent<StaleTicketsTableRow, StaleTicketsTableComparator> {
        TableColumn("Your Comment", sortUsing: StaleTicketsTableComparator(column: .currentUserComment)) { row in
            Text(ageText(row.report.latestCurrentUserCommentDate))
        }
        .width(min: 110, ideal: 140)

        TableColumn("Assignee Comment", sortUsing: StaleTicketsTableComparator(column: .assigneeComment)) { row in
            Text(ageText(row.report.latestAssigneeCommentDate))
        }
        .width(min: 130, ideal: 155)

        TableColumn("Latest Comment", sortUsing: StaleTicketsTableComparator(column: .latestComment)) { row in
            Text(ageText(row.report.latestCommentDate))
        }
        .width(min: 120, ideal: 145)

        TableColumn("Latest Reply", sortUsing: StaleTicketsTableComparator(column: .latestReply)) { row in
            Text(ageText(row.report.latestReplyDate, missing: "None"))
        }
        .width(min: 110, ideal: 135)

        TableColumn("Summary", sortUsing: StaleTicketsTableComparator(column: .summary)) { row in
            VStack(alignment: .leading, spacing: 2) {
                Text(row.summary)
                if let error = row.report.error {
                    Text(error)
                        .font(.caption)
                        .foregroundStyle(.red)
                }
            }
        }
        .width(min: 260, ideal: 420)
    }

    private func ageText(_ date: Date?, missing: String = "Never") -> String {
        guard let date else {
            return missing
        }

        return date.formatted(.relative(presentation: .named))
    }

    private func progressDescription(for snapshot: StaleTicketsSnapshot) -> String {
        switch snapshot.status {
        case .queryingFilter:
            "Querying filter…"
        case .checkingComments(let completed, let total):
            "Checking comments (\(completed) of \(total))…"
        case .complete:
            "Refreshing…"
        case .failed:
            "Refresh failed"
        }
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

private struct StaleTicketsEmptyState<Actions: View>: View {
    let title: String
    let systemImage: String
    let message: String
    let isProgressing: Bool
    @ViewBuilder let actions: () -> Actions

    init(
        title: String,
        systemImage: String,
        message: String,
        isProgressing: Bool = false,
        @ViewBuilder actions: @escaping () -> Actions = { EmptyView() },
    ) {
        self.title = title
        self.systemImage = systemImage
        self.message = message
        self.isProgressing = isProgressing
        self.actions = actions
    }

    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: systemImage)
                .font(.system(size: 32))
                .foregroundStyle(.secondary)
            Text(title)
                .font(.headline)
            Text(message)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            if isProgressing {
                ProgressView()
            }
            actions()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding()
    }
}
