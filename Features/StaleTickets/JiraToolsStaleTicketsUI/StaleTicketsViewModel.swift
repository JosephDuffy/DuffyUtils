import Combine
import Foundation
import JiraToolsAppFoundation
import JiraToolsCore
import JiraToolsStaleTickets

public typealias StaleTicketsConfigurationSaveAction = @MainActor (
    StaleTicketsConfigurationDraft,
    StaleTicketsConfiguration
) throws -> StaleTicketsRequest

public enum StaleTicketsTableSortColumn: Hashable, Sendable {
    case severity
    case key
    case status
    case assignee
    case currentUserComment
    case assigneeComment
    case latestComment
    case latestReply
    case summary
    case extraField(String)
    case extraFields
}

public struct StaleTicketsTableComparator: Codable, Hashable, Sendable, SortComparator {
    public var column: StaleTicketsTableSortColumn
    public var order: SortOrder

    public init(
        column: StaleTicketsTableSortColumn,
        order: SortOrder = .forward,
    ) {
        self.column = column
        self.order = order
    }

    public func compare(
        _ lhs: StaleTicketsTableRow,
        _ rhs: StaleTicketsTableRow,
    ) -> ComparisonResult {
        let result = switch column {
        case .severity:
            compare(lhs.severityRank, rhs.severityRank)
        case .key:
            compare(lhs.key, rhs.key)
        case .status:
            compare(lhs.status, rhs.status)
        case .assignee:
            compare(lhs.assignee, rhs.assignee)
        case .currentUserComment:
            compare(lhs.currentUserCommentDate, rhs.currentUserCommentDate)
        case .assigneeComment:
            compare(lhs.assigneeCommentDate, rhs.assigneeCommentDate)
        case .latestComment:
            compare(lhs.latestCommentDate, rhs.latestCommentDate)
        case .latestReply:
            compare(lhs.latestReplyDate, rhs.latestReplyDate)
        case .summary:
            compare(lhs.summary, rhs.summary)
        case .extraField(let fieldID):
            compare(lhs.extraFieldValue(for: fieldID), rhs.extraFieldValue(for: fieldID))
        case .extraFields:
            compare(lhs.extraFieldsDisplay, rhs.extraFieldsDisplay)
        }

        return order == .forward ? result : result.reversed
    }

    private func compare<Value: Comparable>(
        _ lhs: Value,
        _ rhs: Value,
    ) -> ComparisonResult {
        if lhs < rhs {
            return .orderedAscending
        }
        if lhs > rhs {
            return .orderedDescending
        }
        return .orderedSame
    }
}

extension ComparisonResult {
    fileprivate var reversed: ComparisonResult {
        switch self {
        case .orderedAscending:
            .orderedDescending
        case .orderedDescending:
            .orderedAscending
        case .orderedSame:
            .orderedSame
        }
    }
}

extension StaleTicketsTableSortColumn: Codable {
    private enum CodingKeys: String, CodingKey {
        case fieldID
        case kind
    }

    private enum Kind: String, Codable {
        case severity
        case key
        case status
        case assignee
        case currentUserComment
        case assigneeComment
        case latestComment
        case latestReply
        case summary
        case extraField
        case extraFields
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let kind = try container.decode(Kind.self, forKey: .kind)
        self = switch kind {
        case .severity: .severity
        case .key: .key
        case .status: .status
        case .assignee: .assignee
        case .currentUserComment: .currentUserComment
        case .assigneeComment: .assigneeComment
        case .latestComment: .latestComment
        case .latestReply: .latestReply
        case .summary: .summary
        case .extraField:
            .extraField(try container.decode(String.self, forKey: .fieldID))
        case .extraFields: .extraFields
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .severity:
            try container.encode(Kind.severity, forKey: .kind)
        case .key:
            try container.encode(Kind.key, forKey: .kind)
        case .status:
            try container.encode(Kind.status, forKey: .kind)
        case .assignee:
            try container.encode(Kind.assignee, forKey: .kind)
        case .currentUserComment:
            try container.encode(Kind.currentUserComment, forKey: .kind)
        case .assigneeComment:
            try container.encode(Kind.assigneeComment, forKey: .kind)
        case .latestComment:
            try container.encode(Kind.latestComment, forKey: .kind)
        case .latestReply:
            try container.encode(Kind.latestReply, forKey: .kind)
        case .summary:
            try container.encode(Kind.summary, forKey: .kind)
        case .extraField(let fieldID):
            try container.encode(Kind.extraField, forKey: .kind)
            try container.encode(fieldID, forKey: .fieldID)
        case .extraFields:
            try container.encode(Kind.extraFields, forKey: .kind)
        }
    }
}

public struct StaleTicketsTableSort: Codable, Sendable {
    public var comparators: [StaleTicketsTableComparator]

    public init(comparators: [StaleTicketsTableComparator] = [
        StaleTicketsTableComparator(column: .severity),
    ]) {
        self.comparators = comparators
    }

    private enum CodingKeys: String, CodingKey {
        case comparators
        case column
        case isAscending
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        if let comparators = try container.decodeIfPresent([StaleTicketsTableComparator].self, forKey: .comparators) {
            self.comparators = comparators
            return
        }

        let legacyColumn = try container.decodeIfPresent(String.self, forKey: .column) ?? "severity"
        let isAscending = try container.decodeIfPresent(Bool.self, forKey: .isAscending) ?? true
        self.comparators = [StaleTicketsTableComparator(
            column: StaleTicketsTableSortColumn(legacyValue: legacyColumn),
            order: isAscending ? .forward : .reverse,
        )]
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(comparators, forKey: .comparators)
    }
}

private extension StaleTicketsTableSortColumn {
    init(legacyValue: String) {
        self = switch legacyValue {
        case "key": .key
        case "status": .status
        case "assignee": .assignee
        case "currentUserComment": .currentUserComment
        case "assigneeComment": .assigneeComment
        case "latestComment": .latestComment
        case "latestReply": .latestReply
        case "summary": .summary
        default: .severity
        }
    }
}

@MainActor
public final class StaleTicketsViewModel: ObservableObject {
    @Published public private(set) var snapshot: StaleTicketsSnapshot?
    @Published public private(set) var lastLoadedAt: Date?
    @Published public private(set) var refreshError: String?
    @Published public private(set) var isRefreshing = false
    @Published public private(set) var isConfigured: Bool
    @Published public var isWatching = false {
        didSet {
            watchingDidChange(isWatching)
            if isWatching {
                watchChangeCoordinator.reset()
            }
            updateWatchTask()
        }
    }
    public private(set) var configurationDraft: StaleTicketsConfigurationDraft
    @Published var sortOrder: [StaleTicketsTableComparator]

    public private(set) var request: StaleTicketsRequest
    public private(set) var rows: [StaleTicketsTableRow] = []

    private let saveConfiguration: StaleTicketsConfigurationSaveAction
    private let authorizationProvider: @MainActor () throws -> JiraAuthorization
    private let deliverAlert: @MainActor ([StaleTicketsReport], Set<Severity>, JiraToolsAlertMode) async -> Void
    private let sortDidChange: @MainActor (StaleTicketsTableSort) -> Void
    private let watchingDidChange: @MainActor (Bool) -> Void
    private var watchChangeCoordinator = WatchChangeCoordinator<String, StaleTicketState>()
    private var refreshTask: Task<Void, Never>?
    private var sortOrderCancellable: AnyCancellable?
    private var watchTask: Task<Void, Never>?
    private var refreshID = UUID()

    public init(
        request: StaleTicketsRequest,
        filterInput: String,
        queryMode: StaleTicketsQueryMode = .filter,
        refreshInterval: TimeInterval = 60,
        isConfigured: Bool = true,
        alertSeverities: Set<Severity> = [.warning, .error],
        alertMode: JiraToolsAlertMode = .both,
        tableSort: StaleTicketsTableSort = StaleTicketsTableSort(),
        saveConfiguration: @escaping StaleTicketsConfigurationSaveAction,
        authorizationProvider: @escaping @MainActor () throws -> JiraAuthorization,
        watchingDidChange: @escaping @MainActor (Bool) -> Void = { _ in },
        deliverAlert: @escaping @MainActor ([StaleTicketsReport], Set<Severity>, JiraToolsAlertMode) async -> Void = { _, _, _ in },
        sortDidChange: @escaping @MainActor (StaleTicketsTableSort) -> Void = { _ in },
    ) {
        self.request = request
        self.isConfigured = isConfigured
        configurationDraft = StaleTicketsConfigurationDraft(
            configuration: request.configuration,
            filterInput: filterInput,
            queryMode: queryMode,
            baseURL: request.location.baseURL.absoluteString,
            refreshInterval: refreshInterval,
        )
        sortOrder = tableSort.comparators
        self.saveConfiguration = saveConfiguration
        self.authorizationProvider = authorizationProvider
        self.watchingDidChange = watchingDidChange
        self.deliverAlert = deliverAlert
        self.sortDidChange = sortDidChange
        configurationDraft.alertSeverities = alertSeverities
        configurationDraft.alertMode = alertMode
        sortOrderCancellable = $sortOrder
            .dropFirst()
            .sink { [weak self] sortOrder in
                guard let self else {
                    return
                }

                self.rows = self.rows.sorted(using: sortOrder)
                self.sortDidChange(StaleTicketsTableSort(comparators: sortOrder))
            }
    }

    deinit {
        refreshTask?.cancel()
        watchTask?.cancel()
    }

    public func refresh() {
        guard isConfigured else {
            return
        }

        let refreshID = UUID()
        self.refreshID = refreshID
        refreshTask?.cancel()
        refreshError = nil
        isRefreshing = true

        let refreshRequest: StaleTicketsRequest
        do {
            refreshRequest = StaleTicketsRequest(
                authorization: try authorizationProvider(),
                location: request.location,
                configuration: request.configuration,
            )
        } catch {
            refreshError = error.localizedDescription
            return
        }

        let service = StaleTicketsRefreshService(request: refreshRequest)
        refreshTask = Task { [weak self] in
            do {
                for try await snapshot in service.refresh() {
                    guard !Task.isCancelled else {
                        return
                    }
                    guard let self, self.refreshID == refreshID else {
                        return
                    }

                    self.apply(snapshot)
                }
            } catch is CancellationError {
                return
            } catch {
                guard let self, self.refreshID == refreshID else {
                    return
                }

                refreshError = error.localizedDescription
            }

            guard let self, self.refreshID == refreshID else {
                return
            }

            isRefreshing = false
        }
    }

    public func saveConfigurationDraft(_ draft: StaleTicketsConfigurationDraft) -> Bool {
        do {
            let configuration = try draft.validatedConfiguration()
            request = try saveConfiguration(draft, configuration)
            configurationDraft = draft
            isConfigured = true
            if isWatching {
                updateWatchTask()
            }
            refresh()
            return true
        } catch {
            refreshError = error.localizedDescription
            return false
        }
    }

    public func clearRefreshError() {
        refreshError = nil
    }

    public func issueURL(for row: StaleTicketsTableRow) -> URL {
        request.location.baseURL
            .appendingPathComponent("browse")
            .appendingPathComponent(row.key)
    }

    private func apply(_ snapshot: StaleTicketsSnapshot) {
        self.snapshot = snapshot
        rows = snapshot.reports.map {
            StaleTicketsTableRow(
                report: $0,
                extraFields: snapshot.extraFields,
            )
        }
        rows = rows.sorted(using: sortOrder)

        if case .complete = snapshot.status {
            lastLoadedAt = snapshot.updatedAt
            isRefreshing = false
            notifyForWatchedChanges(in: snapshot)
        }
    }

    private func notifyForWatchedChanges(in snapshot: StaleTicketsSnapshot) {
        guard isWatching else {
            return
        }

        let reportsByKey = Dictionary(
            uniqueKeysWithValues: snapshot.reports.map { ($0.issue.key, $0) },
        )
        let states = Dictionary(
            uniqueKeysWithValues: snapshot.reports.map {
                ($0.issue.key, StaleTicketState(report: $0))
            },
        )
        let changedReports = watchChangeCoordinator.replace(with: states).compactMap { change in
            switch change {
            case .added(let id, _), .changed(let id, _, _):
                reportsByKey[id]
            case .removed:
                nil
            }
        }
        let attentionReports = changedReports.filter {
            configurationDraft.alertSeverities.contains($0.severity)
        }
        guard !attentionReports.isEmpty else {
            return
        }

        let alertSeverities = configurationDraft.alertSeverities
        let alertMode = configurationDraft.alertMode
        Task {
            await deliverAlert(attentionReports, alertSeverities, alertMode)
        }
    }

    private func updateWatchTask() {
        watchTask?.cancel()

        guard isWatching else {
            watchTask = nil
            return
        }

        refresh()
        let interval = configurationDraft.refreshInterval
        watchTask = Task { [weak self] in
            while !Task.isCancelled {
                let nanoseconds = UInt64(interval * 1_000_000_000)
                try? await Task.sleep(nanoseconds: nanoseconds)
                guard !Task.isCancelled else {
                    return
                }
                self?.refresh()
            }
        }
    }

}
