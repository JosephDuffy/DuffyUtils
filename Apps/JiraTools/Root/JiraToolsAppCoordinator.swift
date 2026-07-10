import Combine
import Foundation
import JiraToolsAppFoundation
import JiraToolsCore
import JiraToolsStaleTickets
import JiraToolsStaleTicketsUI

@MainActor
final class JiraToolsAppCoordinator: ObservableObject {
    @Published private(set) var staleTicketsViewModel: StaleTicketsViewModel?

    private let accountStore = JiraAccountStore()
    private let alertService = SystemAlertService()
    private let preferencesStore = CodablePreferencesStore(
        key: "com.josephduffy.JiraTools.stale-tickets-preferences",
        defaultValue: StaleTicketsPreferences(),
    )

    init() {
        rebuildStaleTicketsViewModel()
    }

    var hasCredentials: Bool {
        accountStore.hasCredentials
    }

    var shouldOpenCredentialsWindow: Bool {
        !hasCredentials
    }

    func saveCredentials(
        siteURL: URL,
        email: String,
        token: String,
    ) throws {
        guard let baseURL = jiraBaseURL(from: siteURL) else {
            throw JiraToolsError("Enter a Jira site such as example.atlassian.net.")
        }

        let account = JiraAccount(
            siteURL: baseURL,
            authorizationKind: .apiToken(email: email),
        )
        try accountStore.save(account: account, apiToken: token)
        rebuildStaleTicketsViewModel()
    }

    func verifyCredentials(
        siteURL: URL,
        email: String,
        token: String,
    ) async throws -> JiraUser {
        guard let baseURL = jiraBaseURL(from: siteURL) else {
            throw JiraToolsError("Enter a Jira site such as example.atlassian.net.")
        }

        let client = JiraClient(
            baseURL: baseURL,
            authorization: .apiToken(email: email, token: token),
            extraFieldIDs: [],
        )
        return try await client.verifyConnection()
    }

    func removeCredentials() throws {
        try accountStore.removeActiveAccount()
        staleTicketsViewModel = nil
    }

    private func rebuildStaleTicketsViewModel() {
        guard let account = accountStore.activeAccount else {
            staleTicketsViewModel = nil
            return
        }

        let preferences = preferencesStore.value
        let configurationDraft = StaleTicketsConfigurationDraft(
            configuration: preferences.configuration,
            filterInput: preferences.filterInput,
            queryMode: preferences.queryMode,
            baseURL: account.siteURL.absoluteString,
            refreshInterval: preferences.refreshInterval,
        )
        let location = try? configurationDraft.resolvedLocation()
        let request = StaleTicketsRequest(
            authorization: .oauth(accessToken: ""),
            location: location ?? ResolvedJiraLocation(baseURL: account.siteURL, jql: ""),
            configuration: preferences.configuration,
        )
        let viewModel = StaleTicketsViewModel(
            request: request,
            filterInput: preferences.filterInput,
            queryMode: preferences.queryMode,
            refreshInterval: preferences.refreshInterval,
            isConfigured: preferences.isConfigured && location != nil,
            alertSeverities: preferences.alertSeverities,
            alertMode: preferences.alertMode,
            saveConfiguration: { [weak self] draft, configuration in
            guard let self else {
                throw CancellationError()
            }
            let location = try draft.resolvedLocation()
            let existingPreferences = self.preferencesStore.value
            try self.preferencesStore.save(StaleTicketsPreferences(
                filterInput: draft.filterInput,
                queryMode: draft.queryMode,
                refreshInterval: draft.refreshInterval,
                isConfigured: true,
                isWatching: existingPreferences.isWatching,
                alertSeverities: draft.alertSeverities,
                alertMode: draft.alertMode,
                configuration: configuration,
            ))
            return StaleTicketsRequest(
                authorization: .oauth(accessToken: ""),
                location: location,
                configuration: configuration,
            )
        },
            authorizationProvider: { [weak self] in
            guard let self,
                  let authorization = try self.accountStore.authorization() else {
                throw JiraToolsError("Add Jira credentials before refreshing tickets.")
            }
            return authorization
        },
            watchingDidChange: { [weak self] isWatching in
            guard let self else {
                return
            }
            var preferences = self.preferencesStore.value
            preferences.isWatching = isWatching
            try? self.preferencesStore.save(preferences)
            if isWatching {
                Task {
                    _ = try? await self.alertService.requestAuthorization()
                }
            }
        },
            deliverAlert: { [weak self] reports, severities, mode in
            guard let self, mode != .none else {
                return
            }
            let attentionReports = reports.filter { severities.contains($0.severity) }
            guard !attentionReports.isEmpty else {
                return
            }
            let keys = attentionReports.map(\.issue.key).joined(separator: ", ")
            let worst = attentionReports.map(\.severity).min() ?? .warning
            try? await self.alertService.deliver(
                JiraToolsAlert(
                    title: "Jira tickets need attention",
                    body: "\(attentionReports.count) ticket(s): \(keys) (\(worst.label))",
                ),
                mode: mode,
            )
        },
        )
        viewModel.isConfigurationPresented = !preferences.isConfigured
        viewModel.isWatching = preferences.isConfigured && preferences.isWatching
        staleTicketsViewModel = viewModel
    }
}

private struct StaleTicketsPreferences: Codable {
    var filterInput = ""
    var queryMode: StaleTicketsQueryMode = .filter
    var refreshInterval = 60.0
    var isConfigured = false
    var isWatching = false
    var alertSeverities: Set<Severity> = [.warning, .error]
    var alertMode: JiraToolsAlertMode = .both
    var configuration = StaleTicketsConfiguration(
        warningHours: 20 * 3_600,
        errorHours: 24 * 3_600,
        greenHours: 4 * 3_600,
        maxResults: 100,
        extraFields: [],
        deemphasizedStatuses: [],
        highlightedCommentSources: [.assignee],
        sort: .latestComment,
    )

    enum CodingKeys: String, CodingKey {
        case filterInput
        case queryMode
        case refreshInterval
        case isConfigured
        case isWatching
        case alertSeverities
        case alertMode
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

    init(
        filterInput: String,
        queryMode: StaleTicketsQueryMode,
        refreshInterval: TimeInterval,
        isConfigured: Bool,
        isWatching: Bool,
        alertSeverities: Set<Severity>,
        alertMode: JiraToolsAlertMode,
        configuration: StaleTicketsConfiguration,
    ) {
        self.filterInput = filterInput
        self.queryMode = queryMode
        self.refreshInterval = refreshInterval
        self.isConfigured = isConfigured
        self.isWatching = isWatching
        self.alertSeverities = alertSeverities
        self.alertMode = alertMode
        self.configuration = configuration
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        filterInput = try container.decodeIfPresent(String.self, forKey: .filterInput) ?? ""
        queryMode = try container.decodeIfPresent(StaleTicketsQueryMode.self, forKey: .queryMode)
            ?? (filterInput.contains("://") || filterInput.contains(".atlassian.net") ? .filter : .jql)
        refreshInterval = try container.decodeIfPresent(TimeInterval.self, forKey: .refreshInterval) ?? 60
        isConfigured = try container.decodeIfPresent(Bool.self, forKey: .isConfigured)
            ?? !filterInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        isWatching = try container.decodeIfPresent(Bool.self, forKey: .isWatching) ?? false
        alertSeverities = try container.decodeIfPresent(Set<Severity>.self, forKey: .alertSeverities) ?? [.warning, .error]
        alertMode = try container.decodeIfPresent(JiraToolsAlertMode.self, forKey: .alertMode) ?? .both
        configuration = StaleTicketsConfiguration(
            warningHours: try container.decodeIfPresent(TimeInterval.self, forKey: .warningHours) ?? 20 * 3_600,
            errorHours: try container.decodeIfPresent(TimeInterval.self, forKey: .errorHours) ?? 24 * 3_600,
            greenHours: try container.decodeIfPresent(TimeInterval.self, forKey: .greenHours) ?? 4 * 3_600,
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
        try container.encode(filterInput, forKey: .filterInput)
        try container.encode(queryMode, forKey: .queryMode)
        try container.encode(refreshInterval, forKey: .refreshInterval)
        try container.encode(isConfigured, forKey: .isConfigured)
        try container.encode(isWatching, forKey: .isWatching)
        try container.encode(alertSeverities, forKey: .alertSeverities)
        try container.encode(alertMode, forKey: .alertMode)
        try container.encode(configuration.warningHours, forKey: .warningHours)
        try container.encode(configuration.errorHours, forKey: .errorHours)
        try container.encode(configuration.greenHours, forKey: .greenHours)
        try container.encode(configuration.maxResults, forKey: .maxResults)
        try container.encode(configuration.extraFields, forKey: .extraFields)
        try container.encode(configuration.deemphasizedStatuses, forKey: .deemphasizedStatuses)
        try container.encode(Array(configuration.highlightedCommentSources), forKey: .highlightedCommentSources)
        try container.encode(configuration.sort, forKey: .sort)
    }
}
