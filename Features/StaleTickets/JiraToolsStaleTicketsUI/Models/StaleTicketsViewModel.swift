import Combine
import Foundation
import JiraToolsAppFoundation
import JiraToolsCore
import JiraToolsStaleTickets

@MainActor
public final class StaleTicketsViewModel: ObservableObject {
    @Published public private(set) var snapshot: StaleTicketsSnapshot?
    @Published public private(set) var lastLoadedAt: Date?
    @Published public private(set) var refreshError: String?
    @Published public private(set) var isRefreshing = false
    @Published public var isWatching = false {
        didSet {
            watchingDidChange(isWatching: isWatching)
            if isWatching {
                watchChangeCoordinator.reset()
            }
            updateWatchTask()
        }
    }
    @Published var sortOrder: [StaleTicketsTableComparator]

    public private(set) var rows: [StaleTicketsTableRow] = []

    public let configuration: StaleTicketsConfigurationViewModel

    private let loadAuthorization: LoadStaleTicketsAuthorizationUseCase
    private let refreshStaleTickets: RefreshStaleTicketsUseCase
    private let watchingDidChange: HandleStaleTicketsWatchingChangeUseCase
    private let deliverAlert: DeliverStaleTicketsAlertUseCase
    private let saveTableSort: SaveStaleTicketsTableSortUseCase
    private let refreshCache = StaleTicketsRefreshCache()
    private var watchChangeCoordinator = WatchChangeCoordinator<String, StaleTicketState>()
    private var refreshTask: Task<Void, Never>?
    private var configurationRequestCancellable: AnyCancellable?
    private var sortOrderCancellable: AnyCancellable?
    private var watchTask: Task<Void, Never>?
    private var refreshID = UUID()

    public init(
        configuration: StaleTicketsConfigurationViewModel,
        tableSort: StaleTicketsTableSort = StaleTicketsTableSort(),
        loadAuthorization: LoadStaleTicketsAuthorizationUseCase,
        refreshStaleTickets: RefreshStaleTicketsUseCase = RefreshStaleTicketsUseCase { request, cache in
            StaleTicketsRefreshService(request: request, cache: cache).refresh()
        },
        watchingDidChange: HandleStaleTicketsWatchingChangeUseCase = HandleStaleTicketsWatchingChangeUseCase { _ in },
        deliverAlert: DeliverStaleTicketsAlertUseCase = DeliverStaleTicketsAlertUseCase { _, _, _ in },
        saveTableSort: SaveStaleTicketsTableSortUseCase = SaveStaleTicketsTableSortUseCase { _ in },
    ) {
        self.configuration = configuration
        sortOrder = tableSort.comparators
        self.loadAuthorization = loadAuthorization
        self.refreshStaleTickets = refreshStaleTickets
        self.watchingDidChange = watchingDidChange
        self.deliverAlert = deliverAlert
        self.saveTableSort = saveTableSort
        configurationRequestCancellable = configuration.$request
            .dropFirst()
            .sink { [weak self] _ in
                guard let self else {
                    return
                }

                if isWatching {
                    updateWatchTask()
                }
                refresh()
            }
        sortOrderCancellable = $sortOrder
            .dropFirst()
            .sink { [weak self] sortOrder in
                guard let self else {
                    return
                }

                rows = rows.sorted(using: sortOrder)
                saveTableSort(tableSort: StaleTicketsTableSort(comparators: sortOrder))
            }
    }

    deinit {
        refreshTask?.cancel()
        watchTask?.cancel()
    }

    public func refresh() {
        guard configuration.isConfigured else {
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
                authorization: try loadAuthorization(),
                location: configuration.request.location,
                configuration: configuration.request.configuration,
            )
        } catch {
            refreshError = error.localizedDescription
            isRefreshing = false
            return
        }

        let snapshots = refreshStaleTickets(
            request: refreshRequest,
            cache: refreshCache,
        )
        refreshTask = Task { [weak self] in
            do {
                for try await snapshot in snapshots {
                    guard !Task.isCancelled else {
                        return
                    }
                    guard let self, self.refreshID == refreshID else {
                        return
                    }

                    apply(snapshot)
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

    public func clearRefreshError() {
        refreshError = nil
    }

    public func presentError(_ error: any Error) {
        refreshError = error.localizedDescription
    }

    public func issueURL(for row: StaleTicketsTableRow) -> URL {
        configuration.request.location.baseURL
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
        let alertSeverities = configuration.savedDraft.alertSeverities
        let attentionReports = changedReports.filter {
            alertSeverities.contains($0.severity)
        }
        guard !attentionReports.isEmpty else {
            return
        }

        let alertMode = configuration.savedDraft.alertMode
        Task {
            await deliverAlert(
                reports: attentionReports,
                severities: alertSeverities,
                mode: alertMode,
            )
        }
    }

    private func updateWatchTask() {
        watchTask?.cancel()

        guard isWatching else {
            watchTask = nil
            return
        }

        refresh()
        let interval = configuration.savedDraft.refreshInterval
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
