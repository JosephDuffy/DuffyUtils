import ArgumentParser
import DuffyUtilsInternals
import Foundation

struct StaleTicketsCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "stale-tickets",
        abstract: "List Jira tickets and highlight those that are considered stale.",
    )

    @Option(help: "Jira issue navigator URL containing a filter=ID or jql=... query. Falls back to 'duffyutils.jira-tools.filter-url'.")
    var filterURL: String?

    @Option(help: "Jira site URL, for example https://example.atlassian.net. Falls back to 'duffyutils.jira-tools.base-url'.")
    var baseURL: String?

    @Option(help: "JQL to query instead of parsing a filter URL. Falls back to 'duffyutils.jira-tools.jql'.")
    var jql: String?

    @Flag(help: "Refresh continuously.")
    var watch = false

    @Option(help: "Watch refresh interval in seconds.")
    var interval: Double = 60

    @Option(help: "Mark orange after this many hours since a selected top-level comment.")
    var warningHours: Double = 20

    @Option(help: "Mark red after this many hours or when a selected top-level comment is missing.")
    var errorHours: Double = 24

    @Option(help: "Mark green when a selected top-level comment is newer than this.")
    var greenHours: Double = 4

    @Option(help: "Comma-separated levels: error,warning,ok,neutral, or none.")
    var notifyLevels: String = "warning,error"

    @Option(help: "Comma-separated stale comment sources to highlight: current-user, any-user, assignee. Falls back to 'duffyutils.jira-tools.highlight-stale-comments'. Defaults to assignee.")
    var highlightStaleComments: String?

    @Option(help: "Sort tickets by comment date: latest-comment, current-user, assignee. Falls back to 'duffyutils.jira-tools.sort'. Defaults to latest-comment.")
    var sort: String?

    @Option(help: "Alert mode: notification, sound, both, or none.")
    var alert: AlertMode = .both

    @Flag(help: "Alert for matching tickets on the first watch refresh.")
    var notifyOnStart = false

    @Option(help: "Jira search page size.")
    var maxResults: Int = 100

    @Option(help: "Number of tickets to show per rendered page. Falls back to 'duffyutils.jira-tools.page-size'.")
    var pageSize: Int?

    @Option(help: "Initial page number to show, 1-based. Falls back to 'duffyutils.jira-tools.page'.")
    var page: Int?

    @Option(help: "Comma-separated Jira field names or ids to display after Assignee. Falls back to 'duffyutils.jira-tools.extra-fields'.")
    var extraFields: String?

    @Option(help: "Comma-separated Jira status names to dim, case-insensitive. Falls back to 'duffyutils.jira-tools.deemphasized-statuses'.")
    var deemphasizedStatuses: String?

    @Flag(help: "Disable ANSI colors.")
    var noColor = false

    @GitConfigValue(name: "duffyutils.jira-tools.filter-url")
    private var configuredFilterURL: String?

    @GitConfigValue(name: "duffyutils.jira-tools.base-url")
    private var configuredBaseURL: String?

    @GitConfigValue(name: "duffyutils.jira-tools.jql")
    private var configuredJQL: String?

    @GitConfigValue(name: "duffyutils.jira-tools.extra-fields")
    private var configuredExtraFields: String?

    @GitConfigValue(name: "duffyutils.jira-tools.deemphasized-statuses")
    private var configuredDeemphasizedStatuses: String?

    @GitConfigValue(name: "duffyutils.jira-tools.highlight-stale-comments")
    private var configuredHighlightStaleComments: String?

    @GitConfigValue(name: "duffyutils.jira-tools.sort")
    private var configuredSort: String?

    @GitConfigValue(name: "duffyutils.jira-tools.page-size")
    private var configuredPageSize: String?

    @GitConfigValue(name: "duffyutils.jira-tools.page")
    private var configuredPage: String?

    mutating func run() async throws {
        let configuredFilterURLValue = try await configuredFilterURL
        let configuredBaseURLValue = try await configuredBaseURL
        let configuredJQLValue = try await configuredJQL
        let configuredExtraFieldsValue = try await configuredExtraFields
        let configuredDeemphasizedStatusesValue = try await configuredDeemphasizedStatuses
        let configuredHighlightStaleCommentsValue = try await configuredHighlightStaleComments
        let configuredSortValue = try await configuredSort
        let configuredPageSizeValue = try await configuredPageSize
        let configuredPageValue = try await configuredPage
        let filterURL = filterURL ?? configuredFilterURLValue
        let baseURL = baseURL ?? configuredBaseURLValue
        let jql = jql ?? configuredJQLValue
        let extraFields = parseCommaSeparatedValues(extraFields ?? configuredExtraFieldsValue ?? "")
        let deemphasizedStatuses = parseCommaSeparatedValues(
            deemphasizedStatuses ?? configuredDeemphasizedStatusesValue ?? "",
        )
        let highlightedCommentSources = try parseHighlightedCommentSources(
            highlightStaleComments ?? configuredHighlightStaleCommentsValue ?? "assignee",
        )
        let sort = try parseTicketSort(sort ?? configuredSortValue ?? "latest-comment")
        let pageSize = try resolvedPositiveInt(
            option: pageSize,
            configuredValue: configuredPageSizeValue,
            defaultValue: 25,
            name: "page-size",
        )
        let page = try resolvedPositiveInt(
            option: page,
            configuredValue: configuredPageValue,
            defaultValue: 1,
            name: "page",
        )
        let notifyLevels = try parseSeveritySet(notifyLevels)
        let location = try resolveJiraLocation(
            filterURL: filterURL.flatMap(URL.init(string:)),
            jql: jql,
            baseURL: baseURL.flatMap(URL.init(string:)),
        )
        let configuration = TicketsConfiguration(
            warningHours: warningHours,
            errorHours: errorHours,
            greenHours: greenHours,
            maxResults: maxResults,
            extraFields: extraFields,
            deemphasizedStatuses: deemphasizedStatuses,
            highlightedCommentSources: highlightedCommentSources,
            sort: sort,
        )
        let noColor = noColor || ProcessInfo.processInfo.environment["NO_COLOR"] != nil
        let renderer = TerminalRenderer(
            configuration: RendererConfiguration(
                location: location,
                tickets: configuration,
                watch: watch,
                intervalSeconds: interval,
                noColor: noColor,
            ),
        )
        let credentials = try JiraCredentials.fromEnvironment()
        let service = TicketRefreshService(
            credentials: credentials,
            location: location,
            configuration: configuration,
        )

        try await runRefreshLoop(
            service: service,
            renderer: renderer,
            notifyLevels: notifyLevels,
            pagination: PaginationState(
                pageIndex: page - 1,
                pageSize: pageSize,
            ),
        )
    }

    private func runRefreshLoop(
        service: TicketRefreshService,
        renderer: TerminalRenderer,
        notifyLevels: Set<Severity>,
        pagination: PaginationState,
    ) async throws {
        var previousStates: [String: TicketState] = [:]
        var firstRun = true
        var latestSnapshot: RefreshSnapshot?
        var pagination = pagination
        let terminalInput = watch ? TerminalInput() : nil
        terminalInput?.enableRawMode()
        defer {
            terminalInput?.restore()
            renderer.restoreTerminalDisplay()
        }

        refreshLoop: repeat {
            let snapshot: RefreshSnapshot
            var didRenderProgress = false
            let shouldRenderProgress = renderer.canReplaceOutput
            do {
                snapshot = try await service.refresh { progressSnapshot in
                    guard shouldRenderProgress else {
                        return
                    }

                    if case .queryingFilter = progressSnapshot.status {
                        // Preserve the requested page until Jira returns the issue count.
                    } else {
                        pagination = pagination.clamped(totalItems: progressSnapshot.reports.count)
                    }
                    didRenderProgress = true
                    renderer.render(
                        progressSnapshot,
                        pagination: pagination,
                        replacingPreviousOutput: true,
                    )
                }
                pagination = pagination.clamped(totalItems: snapshot.reports.count)
                latestSnapshot = snapshot
            } catch {
                snapshot = latestSnapshot?.addingError(error) ?? RefreshSnapshot(
                    reports: [],
                    extraFields: [],
                    currentUserName: "unknown",
                    updatedAt: Date(),
                    errors: [String(describing: error)],
                    status: .failed,
                )
                pagination = pagination.clamped(totalItems: snapshot.reports.count)
            }

            renderer.render(
                snapshot,
                pagination: pagination,
                replacingPreviousOutput: didRenderProgress,
            )
            let changedAttentionTickets = snapshot.reports.filter { report in
                guard notifyLevels.contains(report.severity) else {
                    return false
                }
                let state = TicketState(report: report)
                let previous = previousStates[report.issue.key]
                if firstRun {
                    return notifyOnStart
                }
                return previous != state
            }

            if watch && !changedAttentionTickets.isEmpty {
                sendAlert(for: changedAttentionTickets, mode: alert)
            }

            previousStates = Dictionary(uniqueKeysWithValues: snapshot.reports.map { ($0.issue.key, TicketState(report: $0)) })
            firstRun = false

            if !watch {
                break
            }

            while true {
                let action = try await waitForNextRefresh(
                    intervalSeconds: interval,
                    terminalInput: terminalInput,
                )

                switch action {
                case .refresh:
                    continue refreshLoop
                case .nextPage:
                    guard let latestSnapshot else {
                        continue
                    }

                    pagination.pageIndex += 1
                    pagination = pagination.clamped(totalItems: latestSnapshot.reports.count)
                    renderer.render(
                        latestSnapshot,
                        pagination: pagination,
                        replacingPreviousOutput: true,
                    )
                case .previousPage:
                    guard let latestSnapshot else {
                        continue
                    }

                    pagination.pageIndex -= 1
                    pagination = pagination.clamped(totalItems: latestSnapshot.reports.count)
                    renderer.render(
                        latestSnapshot,
                        pagination: pagination,
                        replacingPreviousOutput: true,
                    )
                }
            }
        } while true
    }
}

func parseSeveritySet(_ rawValue: String) throws -> Set<Severity> {
    if rawValue == "none" {
        return []
    }

    let levels = try rawValue.split(separator: ",").map { rawLevel -> Severity in
        guard let severity = Severity(rawValue: rawLevel.trimmingCharacters(in: .whitespacesAndNewlines)) else {
            throw AppError("Unknown notify level: \(rawLevel)")
        }
        return severity
    }

    return Set(levels)
}

func parseCommaSeparatedValues(_ rawValue: String) -> [String] {
    rawValue
        .split(separator: ",")
        .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
        .filter { !$0.isEmpty }
}

func parseHighlightedCommentSources(_ rawValue: String) throws -> Set<HighlightedCommentSource> {
    let rawSources = parseCommaSeparatedValues(rawValue)
    guard !rawSources.isEmpty else {
        return [.assignee]
    }

    let sources = try rawSources.map { rawSource -> HighlightedCommentSource in
        guard let source = HighlightedCommentSource(rawValue: rawSource) else {
            throw AppError("Unknown stale comment highlight source: \(rawSource)")
        }

        return source
    }

    return Set(sources)
}

func parseTicketSort(_ rawValue: String) throws -> TicketSort {
    let trimmedRawValue = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
    guard let sort = TicketSort(rawValue: trimmedRawValue) else {
        throw AppError("Unknown ticket sort: \(rawValue)")
    }

    return sort
}

func resolvedPositiveInt(
    option: Int?,
    configuredValue: String?,
    defaultValue: Int,
    name: String,
) throws -> Int {
    let value: Int
    if let option {
        value = option
    } else if let configuredValue {
        let trimmedValue = configuredValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let parsedValue = Int(trimmedValue) else {
            throw AppError("Invalid \(name): \(configuredValue)")
        }

        value = parsedValue
    } else {
        value = defaultValue
    }

    guard value > 0 else {
        throw AppError("\(name) must be greater than 0.")
    }

    return value
}
