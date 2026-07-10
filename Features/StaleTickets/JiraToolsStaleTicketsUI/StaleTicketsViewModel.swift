import Combine
import Foundation
import JiraToolsAppFoundation
import JiraToolsCore
import JiraToolsStaleTickets

public typealias StaleTicketsConfigurationSaveAction = @MainActor (
    StaleTicketsConfigurationDraft,
    StaleTicketsConfiguration
) throws -> StaleTicketsRequest

@MainActor
public final class StaleTicketsViewModel: ObservableObject {
    @Published public private(set) var snapshot: StaleTicketsSnapshot?
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
    @Published public var isConfigurationPresented = false
    @Published public var configurationDraft: StaleTicketsConfigurationDraft
    @Published var sortOrder = [KeyPathComparator(\StaleTicketsTableRow.severityRank)]

    public private(set) var request: StaleTicketsRequest
    public private(set) var rows: [StaleTicketsTableRow] = []

    private let saveConfiguration: StaleTicketsConfigurationSaveAction
    private let authorizationProvider: @MainActor () throws -> JiraAuthorization
    private let deliverAlert: @MainActor ([StaleTicketsReport], Set<Severity>, JiraToolsAlertMode) async -> Void
    private let watchingDidChange: @MainActor (Bool) -> Void
    private var watchChangeCoordinator = WatchChangeCoordinator<String, StaleTicketState>()
    private var refreshTask: Task<Void, Never>?
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
        saveConfiguration: @escaping StaleTicketsConfigurationSaveAction,
        authorizationProvider: @escaping @MainActor () throws -> JiraAuthorization,
        watchingDidChange: @escaping @MainActor (Bool) -> Void = { _ in },
        deliverAlert: @escaping @MainActor ([StaleTicketsReport], Set<Severity>, JiraToolsAlertMode) async -> Void = { _, _, _ in },
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
        self.saveConfiguration = saveConfiguration
        self.authorizationProvider = authorizationProvider
        self.watchingDidChange = watchingDidChange
        self.deliverAlert = deliverAlert
        configurationDraft.alertSeverities = alertSeverities
        configurationDraft.alertMode = alertMode
    }

    deinit {
        refreshTask?.cancel()
        watchTask?.cancel()
    }

    public func refresh() {
        guard isConfigured else {
            isConfigurationPresented = true
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

    public func saveConfigurationDraft() {
        do {
            let configuration = try configurationDraft.validatedConfiguration()
            request = try saveConfiguration(configurationDraft, configuration)
            isConfigured = true
            isConfigurationPresented = false
            if isWatching {
                updateWatchTask()
            }
            refresh()
        } catch {
            refreshError = error.localizedDescription
        }
    }

    public func clearRefreshError() {
        refreshError = nil
    }

    public func updateSortOrder() {
        rows = rows.sorted(using: sortOrder)
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
        updateSortOrder()

        if case .complete = snapshot.status {
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
