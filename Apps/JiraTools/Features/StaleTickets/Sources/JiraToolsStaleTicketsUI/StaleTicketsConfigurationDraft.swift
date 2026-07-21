import Foundation
import JiraAPI
import JiraToolsFoundation
import JiraToolsStaleTickets

public enum StaleTicketsQueryMode: String, CaseIterable, Codable, Sendable {
    case filter
    case jql
}

public struct StaleTicketsConfigurationDraft: Equatable, Sendable {
    public var displayName: String
    public var filterInput: String
    public var queryMode: StaleTicketsQueryMode
    public var baseURL: String
    public var extraFields: String
    public var deemphasizedStatuses: String
    public var highlightedCommentSources: Set<HighlightedCommentSource>
    public var okDuration: Duration
    public var warningDuration: Duration
    public var errorDuration: Duration
    public var maxResults: Int
    public var serviceSort: TicketSort
    public var refreshInterval: TimeInterval
    public var alertSeverities: Set<Severity>
    public var alertMode: JiraToolsAlertMode

    public init(
        displayName: String = "Stale Tickets",
        filterInput: String,
        queryMode: StaleTicketsQueryMode,
        baseURL: String,
        extraFields: String,
        deemphasizedStatuses: String,
        highlightedCommentSources: Set<HighlightedCommentSource>,
        okDuration: Duration,
        warningDuration: Duration,
        errorDuration: Duration,
        maxResults: Int,
        serviceSort: TicketSort,
        refreshInterval: TimeInterval,
        alertSeverities: Set<Severity>,
        alertMode: JiraToolsAlertMode,
    ) {
        self.displayName = displayName
        self.filterInput = filterInput
        self.queryMode = queryMode
        self.baseURL = baseURL
        self.extraFields = extraFields
        self.deemphasizedStatuses = deemphasizedStatuses
        self.highlightedCommentSources = highlightedCommentSources
        self.okDuration = okDuration
        self.warningDuration = warningDuration
        self.errorDuration = errorDuration
        self.maxResults = maxResults
        self.serviceSort = serviceSort
        self.refreshInterval = refreshInterval
        self.alertSeverities = alertSeverities
        self.alertMode = alertMode
    }

    public init(
        configuration: StaleTicketsConfiguration,
        displayName: String = "Stale Tickets",
        filterInput: String,
        queryMode: StaleTicketsQueryMode,
        baseURL: String,
        refreshInterval: TimeInterval,
    ) {
        self.init(
            displayName: displayName,
            filterInput: filterInput,
            queryMode: queryMode,
            baseURL: baseURL,
            extraFields: configuration.extraFields.joined(separator: ", "),
            deemphasizedStatuses: configuration.deemphasizedStatuses.joined(separator: ", "),
            highlightedCommentSources: configuration.highlightedCommentSources,
            okDuration: configuration.okDuration,
            warningDuration: configuration.warningDuration,
            errorDuration: configuration.errorDuration,
            maxResults: configuration.maxResults,
            serviceSort: configuration.sort,
            refreshInterval: refreshInterval,
            alertSeverities: [.warning, .error],
            alertMode: .both,
        )
    }

    public func validatedConfiguration() throws -> StaleTicketsConfiguration {
        guard !displayName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw StaleTicketsConfigurationValidationError.missingDisplayName
        }

        guard maxResults > 0 else {
            throw StaleTicketsConfigurationValidationError.nonPositiveResultLimit
        }

        guard refreshInterval > 0 else {
            throw StaleTicketsConfigurationValidationError.nonPositiveRefreshInterval
        }

        guard !highlightedCommentSources.isEmpty else {
            throw StaleTicketsConfigurationValidationError.missingHighlightedSource
        }

        guard okDuration <= warningDuration, warningDuration < errorDuration else {
            throw StaleTicketsConfigurationValidationError.invalidThresholds
        }

        return StaleTicketsConfiguration(
            warningDuration: warningDuration,
            errorDuration: errorDuration,
            okDuration: okDuration,
            maxResults: maxResults,
            extraFields: commaSeparatedValues(from: extraFields),
            deemphasizedStatuses: commaSeparatedValues(from: deemphasizedStatuses),
            highlightedCommentSources: highlightedCommentSources,
            sort: serviceSort,
        )
    }

    public func resolvedLocation() throws -> ResolvedJiraLocation {
        guard let baseURL = jiraURL(from: baseURL) else {
            throw StaleTicketsConfigurationValidationError.invalidBaseURL
        }

        let queryInput = filterInput.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !queryInput.isEmpty else {
            throw StaleTicketsConfigurationValidationError.missingFilter
        }

        switch queryMode {
        case .filter:
            if queryInput.allSatisfy(\.isNumber) {
                return ResolvedJiraLocation(baseURL: baseURL, jql: "filter = \(queryInput)")
            }
            guard let filterURL = jiraURL(from: queryInput) else {
                throw StaleTicketsConfigurationValidationError.invalidFilterURL
            }
            return try resolveJiraLocation(filterURL: filterURL, jql: nil, baseURL: baseURL)
        case .jql:
            return ResolvedJiraLocation(baseURL: baseURL, jql: queryInput)
        }
    }

    subscript(
        hours keyPath: WritableKeyPath<StaleTicketsConfigurationDraft, Duration>,
    ) -> Double {
        get {
            let components = self[keyPath: keyPath].components
            return (Double(components.seconds) + Double(components.attoseconds) / 1e18) / 3_600
        }
        set(hours) {
            self[keyPath: keyPath] = .seconds(hours * 3_600)
        }
    }

    subscript(highlightedCommentSourceEnabled source: HighlightedCommentSource) -> Bool {
        get { highlightedCommentSources.contains(source) }
        set(isEnabled) {
            if isEnabled {
                highlightedCommentSources.insert(source)
            } else {
                highlightedCommentSources.remove(source)
            }
        }
    }

    subscript(alertSeverityEnabled severity: Severity) -> Bool {
        get { alertSeverities.contains(severity) }
        set(isEnabled) {
            if isEnabled {
                alertSeverities.insert(severity)
            } else {
                alertSeverities.remove(severity)
            }
        }
    }

    private func commaSeparatedValues(from input: String) -> [String] {
        input
            .split(whereSeparator: { $0 == "," || $0.isNewline })
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
    }
}

public enum StaleTicketsConfigurationValidationError: LocalizedError, Equatable, Sendable {
    case missingDisplayName
    case invalidBaseURL
    case invalidFilterURL
    case missingFilter
    case nonPositiveResultLimit
    case nonPositiveRefreshInterval
    case missingHighlightedSource
    case invalidThresholds

    public var errorDescription: String? {
        switch self {
        case .missingDisplayName:
            "Enter a name for this tool."
        case .invalidBaseURL:
            "Enter a valid Jira site URL."
        case .invalidFilterURL:
            "Enter a Jira filter URL or numeric filter ID."
        case .missingFilter:
            "Enter a filter URL or JQL query."
        case .nonPositiveResultLimit:
            "The result limit must be greater than zero."
        case .nonPositiveRefreshInterval:
            "The refresh interval must be greater than zero."
        case .missingHighlightedSource:
            "Choose at least one staleness source."
        case .invalidThresholds:
            "Green must be no greater than warning, and warning must be less than error."
        }
    }
}
