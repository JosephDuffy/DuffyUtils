import JiraToolsStaleTickets
import SwiftUI

public struct StaleTicketsView: View {
    @ObservedObject private var viewModel: StaleTicketsViewModel
    @ObservedObject private var configurationViewModel: StaleTicketsConfigurationViewModel
    @Environment(\.openURL) private var openURL
    @SceneStorage("StaleTicketsView.isTicketDetailsPresented") private var isTicketDetailsPresented: Bool = true
    @State private var isConfigurationPresented = false
    @State private var selectedTicketKey: String?
    private let title: String

    public init(
        title: String = "Stale Tickets",
        viewModel: StaleTicketsViewModel,
    ) {
        self.title = title
        self.viewModel = viewModel
        configurationViewModel = viewModel.configuration
    }

    public var body: some View {
        Group {
            if #available(macOS 14, *) {
                mainContent
                    .inspector(isPresented: $isTicketDetailsPresented) {
                        ticketInspector
                    }
            } else {
                legacyContent
            }
        }
        .navigationTitle(title)
        .sheet(
            isPresented: $isConfigurationPresented,
            onDismiss: configurationViewModel.resetDraft,
        ) {
            StaleTicketsConfigurationSheet(
                draft: $configurationViewModel.draft,
                onSave: saveConfiguration,
            )
        }
        .task {
            guard !configurationViewModel.isConfigured else {
                return
            }

            presentConfiguration()
        }
        .onReceive(viewModel.$snapshot) { snapshot in
            guard let snapshot,
                  case .complete = snapshot.status else {
                return
            }

            clearSelectionIfNeeded()
        }
        .toolbar {
            ToolbarItemGroup(placement: .primaryAction) {
                Button(action: viewModel.refresh) {
                    Label("Refresh", systemImage: "arrow.clockwise")
                }
                .disabled(viewModel.isRefreshing || !configurationViewModel.isConfigured)

                Toggle(isOn: $viewModel.isWatching) {
                    Label("Watch", systemImage: "eye")
                }
                .toggleStyle(.button)

                Button(action: presentConfiguration) {
                    Label("Configure", systemImage: "slider.horizontal.3")
                }
            }

            if #available(macOS 26, *) {
                ToolbarSpacer(.flexible, placement: .primaryAction)
            }

            ToolbarItemGroup(placement: .primaryAction) {
                Button(action: toggleTicketDetails) {
                    Label(
                        isTicketDetailsPresented ? "Hide Ticket Details" : "Show Ticket Details",
                        systemImage: "sidebar.right",
                    )
                }
            }
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

    private var legacyContent: some View {
        HStack(spacing: 0) {
            mainContent

            if isTicketDetailsPresented {
                Divider()
                ticketInspector
                .frame(minWidth: 320, idealWidth: 360, maxWidth: 420)
            }
        }
    }

    private var mainContent: some View {
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
                    title: configurationViewModel.isConfigured ? "No Stale Ticket Results" : "Configure Stale Tickets",
                    systemImage: configurationViewModel.isConfigured ? "ticket" : "slider.horizontal.3",
                    message: configurationViewModel.isConfigured
                        ? "Refresh to load tickets matching the configured Jira filter."
                        : "Choose a Jira filter or JQL query before refreshing tickets.",
                ) {
                    Button(configurationViewModel.isConfigured ? "Refresh" : "Configure") {
                        if configurationViewModel.isConfigured {
                            viewModel.refresh()
                        } else {
                            presentConfiguration()
                        }
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var ticketInspector: some View {
        StaleTicketsTicketInspector(
            row: selectedTicketRow,
            extraFields: viewModel.snapshot?.extraFields ?? [],
            issueURL: selectedTicketRow.map(viewModel.issueURL(for:)),
        )
    }

    @ViewBuilder
    private func results(_ snapshot: StaleTicketsSnapshot) -> some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                if let lastLoadedAt = viewModel.lastLoadedAt {
                    Text("Loaded")
                    Text(lastLoadedAt, format: .dateTime)
                        .foregroundStyle(.secondary)
                }

                if viewModel.isRefreshing {
                    ProgressView()
                        .controlSize(.small)
                    Text(progressDescription(for: snapshot))
                }

                if !snapshot.errors.isEmpty {
                    HStack(alignment: .top, spacing: 8) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundStyle(.orange)
                        Text(snapshot.errors.joined(separator: "\n"))
                            .textSelection(.enabled)
                    }
                    .padding(.horizontal, 8)
                    .background(.orange.opacity(0.12))
                }

                Spacer()
            }
            .background(.bar)
            .padding(8)

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
        Table(
            viewModel.rows,
            selection: $selectedTicketKey,
            sortOrder: $viewModel.sortOrder,
        ) {
            standardColumns()
            TableColumnForEach(snapshot.extraFields, id: \.id) { field in
                TableColumn(field.name, sortUsing: StaleTicketsTableComparator(column: .extraField(field.id))) { row in
                    Text(row.extraFieldValue(for: field.id))
                        .opacity(rowOpacity(for: row))
                }
                .width(min: 100, ideal: 150)
            }
            commentAndSummaryColumns()
        }
    }

    private func fallbackTicketsTable() -> some View {
        Table(
            viewModel.rows,
            selection: $selectedTicketKey,
            sortOrder: $viewModel.sortOrder,
        ) {
            standardColumns()
            TableColumn("Extra Fields", sortUsing: StaleTicketsTableComparator(column: .extraFields)) { row in
                Text(row.extraFieldsDisplay.isEmpty ? "—" : row.extraFieldsDisplay)
                    .lineLimit(3)
                    .opacity(rowOpacity(for: row))
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
                .opacity(rowOpacity(for: row))
        }
        .width(min: 76, ideal: 88)

        TableColumn("Key", sortUsing: StaleTicketsTableComparator(column: .key)) { row in
            Button(row.key) {
                openURL(viewModel.issueURL(for: row))
            }
            .buttonStyle(.link)
            .opacity(rowOpacity(for: row))
        }
        .width(min: 80, ideal: 100)

        TableColumn("Status", sortUsing: StaleTicketsTableComparator(column: .status)) { row in
            Text(row.status)
                .opacity(rowOpacity(for: row))
        }
        .width(min: 90, ideal: 130)

        TableColumn("Assignee", sortUsing: StaleTicketsTableComparator(column: .assignee)) { row in
            Text(row.assignee)
                .opacity(rowOpacity(for: row))
        }
        .width(min: 100, ideal: 150)
    }

    @TableColumnBuilder<StaleTicketsTableRow, StaleTicketsTableComparator>
    private func commentAndSummaryColumns() -> some TableColumnContent<StaleTicketsTableRow, StaleTicketsTableComparator> {
        TableColumn("Your Comment", sortUsing: StaleTicketsTableComparator(column: .currentUserComment)) { row in
            Text(ageText(row.report.latestCurrentUserCommentDate))
                .opacity(rowOpacity(for: row))
                .help(row.report.latestCurrentUserCommentDate?.formatted() ?? "You have never commented")
        }
        .width(min: 110, ideal: 140)

        TableColumn("Assignee Comment", sortUsing: StaleTicketsTableComparator(column: .assigneeComment)) { row in
            Text(ageText(row.report.latestAssigneeCommentDate))
                .opacity(rowOpacity(for: row))
                .help(row.report.latestAssigneeCommentDate?.formatted() ?? "Assignee has never commented")
        }
        .width(min: 130, ideal: 155)

        TableColumn("Latest Comment", sortUsing: StaleTicketsTableComparator(column: .latestComment)) { row in
            Text(ageText(row.report.latestCommentDate))
                .opacity(rowOpacity(for: row))
                .help(row.report.latestCommentDate?.formatted() ?? "No comment has been made")
        }
        .width(min: 120, ideal: 145)

        TableColumn("Latest Reply", sortUsing: StaleTicketsTableComparator(column: .latestReply)) { row in
            Text(ageText(row.report.latestReplyDate, missing: "None"))
                .opacity(rowOpacity(for: row))
                .help(row.report.latestReplyDate?.formatted() ?? "No comment replies")
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
            .opacity(rowOpacity(for: row))
        }
        .width(min: 260, ideal: 420)
    }

    private func ageText(_ date: Date?, missing: String = "Never") -> String {
        guard let date else {
            return missing
        }

        return date.formatted(.relative(presentation: .named))
    }

    private func presentConfiguration() {
        configurationViewModel.resetDraft()
        isConfigurationPresented = true
    }

    private func toggleTicketDetails() {
        isTicketDetailsPresented.toggle()
    }

    private func clearSelectionIfNeeded() {
        guard let selectedTicketKey,
              !viewModel.rows.contains(where: { $0.id == selectedTicketKey }) else {
            return
        }

        self.selectedTicketKey = nil
    }

    private var selectedTicketRow: StaleTicketsTableRow? {
        guard let selectedTicketKey else {
            return nil
        }

        return viewModel.rows.first { $0.id == selectedTicketKey }
    }

    private func saveConfiguration() -> Bool {
        do {
            try configurationViewModel.save()
        } catch {
            viewModel.presentError(error)
            return false
        }

        return true
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

    private func rowOpacity(for row: StaleTicketsTableRow) -> Double {
        row.report.isDeemphasized ? 0.45 : 1
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
