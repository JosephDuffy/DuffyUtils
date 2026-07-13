import Foundation
import JiraToolsAppFoundation
import JiraToolsCore
import JiraToolsStaleTickets
import JiraToolsStaleTicketsUI

enum JiraToolIdentifier: String, Codable {
    case staleTickets

    var defaultDisplayName: String {
        switch self {
        case .staleTickets:
            "Stale Tickets"
        }
    }

    var systemImage: String {
        switch self {
        case .staleTickets:
            "clock.badge.exclamationmark"
        }
    }
}

struct JiraToolInstance: Codable, Identifiable {
    let id: UUID
    let tool: JiraToolIdentifier
    var staleTicketsPreferences: StaleTicketsPreferences

    init(
        id: UUID = UUID(),
        tool: JiraToolIdentifier,
        staleTicketsPreferences: StaleTicketsPreferences,
    ) {
        self.id = id
        self.tool = tool
        self.staleTicketsPreferences = staleTicketsPreferences
    }
}

struct JiraToolInstancesPreferences: Codable {
    var hasMigratedLegacyPreferences = false
    var instances: [JiraToolInstance] = []
}

struct StaleTicketsPreferences: Codable {
    var displayName = JiraToolIdentifier.staleTickets.defaultDisplayName
    var filterInput = ""
    var queryMode: StaleTicketsQueryMode = .filter
    var refreshInterval = 60.0
    var isConfigured = false
    var isWatching = false
    var alertSeverities: Set<Severity> = [.warning, .error]
    var alertMode: JiraToolsAlertMode = .both
    var tableSort = StaleTicketsTableSort()
    var configuration = StaleTicketsConfiguration(
        warningDuration: .hours(20),
        errorDuration: .hours(24),
        okDuration: .hours(4),
        maxResults: 100,
        extraFields: [],
        deemphasizedStatuses: [],
        highlightedCommentSources: [.assignee],
        sort: .latestComment,
    )

    enum CodingKeys: String, CodingKey {
        case displayName
        case filterInput
        case queryMode
        case refreshInterval
        case isConfigured
        case isWatching
        case alertSeverities
        case alertMode
        case tableSort
        // Persist durations as seconds using the established preference keys.
        case warningHours
        case errorHours
        case greenHours
        case maxResults
        case extraFields
        case deemphasizedStatuses
        case highlightedCommentSources
        case sort
    }

    init() {}

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        displayName = try container.decodeIfPresent(String.self, forKey: .displayName)
            ?? JiraToolIdentifier.staleTickets.defaultDisplayName
        filterInput = try container.decodeIfPresent(String.self, forKey: .filterInput) ?? ""
        queryMode = try container.decodeIfPresent(StaleTicketsQueryMode.self, forKey: .queryMode)
            ?? (filterInput.contains("://") || filterInput.contains(".atlassian.net") ? .filter : .jql)
        refreshInterval = try container.decodeIfPresent(TimeInterval.self, forKey: .refreshInterval) ?? 60
        isConfigured = try container.decodeIfPresent(Bool.self, forKey: .isConfigured)
            ?? !filterInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        isWatching = try container.decodeIfPresent(Bool.self, forKey: .isWatching) ?? false
        alertSeverities = try container.decodeIfPresent(Set<Severity>.self, forKey: .alertSeverities) ?? [.warning, .error]
        alertMode = try container.decodeIfPresent(JiraToolsAlertMode.self, forKey: .alertMode) ?? .both
        tableSort = try container.decodeIfPresent(StaleTicketsTableSort.self, forKey: .tableSort) ?? StaleTicketsTableSort()
        configuration = StaleTicketsConfiguration(
            warningDuration: try container.decode(Duration.self, forKey: .warningHours),
            errorDuration: try container.decode(Duration.self, forKey: .errorHours),
            okDuration: try container.decode(Duration.self, forKey: .greenHours),
            maxResults: try container.decodeIfPresent(Int.self, forKey: .maxResults) ?? 100,
            extraFields: try container.decodeIfPresent([String].self, forKey: .extraFields) ?? [],
            deemphasizedStatuses: try container.decodeIfPresent([String].self, forKey: .deemphasizedStatuses) ?? [],
            highlightedCommentSources: Set(
                try container.decodeIfPresent([HighlightedCommentSource].self, forKey: .highlightedCommentSources) ?? [.assignee],
            ),
            sort: try container.decodeIfPresent(TicketSort.self, forKey: .sort) ?? .latestComment,
        )
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(displayName, forKey: .displayName)
        try container.encode(filterInput, forKey: .filterInput)
        try container.encode(queryMode, forKey: .queryMode)
        try container.encode(refreshInterval, forKey: .refreshInterval)
        try container.encode(isConfigured, forKey: .isConfigured)
        try container.encode(isWatching, forKey: .isWatching)
        try container.encode(alertSeverities, forKey: .alertSeverities)
        try container.encode(alertMode, forKey: .alertMode)
        try container.encode(tableSort, forKey: .tableSort)
        try container.encode(configuration.warningDuration, forKey: .warningHours)
        try container.encode(configuration.errorDuration, forKey: .errorHours)
        try container.encode(configuration.okDuration, forKey: .greenHours)
        try container.encode(configuration.maxResults, forKey: .maxResults)
        try container.encode(configuration.extraFields, forKey: .extraFields)
        try container.encode(configuration.deemphasizedStatuses, forKey: .deemphasizedStatuses)
        try container.encode(Array(configuration.highlightedCommentSources), forKey: .highlightedCommentSources)
        try container.encode(configuration.sort, forKey: .sort)
    }

    private func seconds(in duration: Duration) -> TimeInterval {
        let components = duration.components
        return Double(components.seconds) + Double(components.attoseconds) / 1e18
    }
}

extension Duration {
    fileprivate static func hours(_ hours: some BinaryInteger) -> Duration {
        .seconds(hours * 60 * 60)
    }

    fileprivate static func hours(_ hours: Double) -> Duration {
        .seconds(hours * 60 * 60)
    }
}
