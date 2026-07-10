import Combine
import Foundation
import JiraToolsAppFoundation
import JiraToolsAppUI
import JiraToolsCore
import JiraToolsStaleTickets
import JiraToolsStaleTicketsUI

@MainActor
final class JiraToolsAppCoordinator: ObservableObject {
    @Published var isNewToolPresented = false
    @Published var selectedToolID: UUID?
    @Published private(set) var toolInstances: [JiraToolInstance] = []

    private let accountStore = JiraAccountStore()
    private let alertService = SystemAlertService()
    private let legacyStaleTicketsPreferencesStore = CodablePreferencesStore(
        key: "com.josephduffy.JiraTools.stale-tickets-preferences",
        defaultValue: StaleTicketsPreferences(),
    )
    private let toolInstancesPreferencesStore = CodablePreferencesStore(
        key: "com.josephduffy.JiraTools.tool-instances-preferences",
        defaultValue: JiraToolInstancesPreferences(),
    )
    private var staleTicketsViewModels: [JiraToolInstance.ID: StaleTicketsViewModel] = [:]

    init() {
        loadToolInstances()
        rebuildStaleTicketsViewModels()
    }

    var hasCredentials: Bool {
        accountStore.hasCredentials
    }

    var shouldOpenCredentialsWindow: Bool {
        !hasCredentials
    }

    var sidebarItems: [JiraToolsSidebarItem] {
        toolInstances.map { instance in
            JiraToolsSidebarItem(
                id: instance.id,
                title: instance.staleTicketsPreferences.displayName,
                systemImage: instance.tool.systemImage,
            )
        }
    }

    func tool(for id: JiraToolInstance.ID) -> JiraToolInstance? {
        toolInstances.first { $0.id == id }
    }

    func staleTicketsViewModel(for id: JiraToolInstance.ID) -> StaleTicketsViewModel? {
        staleTicketsViewModels[id]
    }

    func presentNewTool() {
        isNewToolPresented = true
    }

    func addTool(_ tool: JiraToolIdentifier) {
        var preferences = StaleTicketsPreferences()
        preferences.displayName = tool.defaultDisplayName

        let instance = JiraToolInstance(
            tool: tool,
            staleTicketsPreferences: preferences,
        )
        toolInstances.append(instance)
        selectedToolID = instance.id
        try? saveToolInstances()
        rebuildStaleTicketsViewModel(for: instance)
        staleTicketsViewModels[instance.id]?.isConfigurationPresented = true
    }

    func removeSelectedTool() {
        guard let selectedToolID,
              let index = toolInstances.firstIndex(where: { $0.id == selectedToolID }) else {
            return
        }

        staleTicketsViewModels[selectedToolID] = nil
        toolInstances.remove(at: index)
        self.selectedToolID = toolInstances.indices.contains(index)
            ? toolInstances[index].id
            : toolInstances.last?.id
        try? saveToolInstances()
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
        rebuildStaleTicketsViewModels()
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
        staleTicketsViewModels = [:]
    }

    private func loadToolInstances() {
        var preferences = toolInstancesPreferencesStore.value
        if !preferences.hasMigratedLegacyPreferences {
            if legacyStaleTicketsPreferencesStore.hasSavedValue {
                preferences.instances = [JiraToolInstance(
                    tool: .staleTickets,
                    staleTicketsPreferences: legacyStaleTicketsPreferencesStore.value,
                )]
            }
            preferences.hasMigratedLegacyPreferences = true
            try? toolInstancesPreferencesStore.save(preferences)
        }

        toolInstances = preferences.instances
        selectedToolID = toolInstances.first?.id
        isNewToolPresented = toolInstances.isEmpty
    }

    private func rebuildStaleTicketsViewModels() {
        staleTicketsViewModels = [:]

        guard accountStore.activeAccount != nil else {
            return
        }

        for instance in toolInstances {
            rebuildStaleTicketsViewModel(for: instance)
        }
    }

    private func rebuildStaleTicketsViewModel(for instance: JiraToolInstance) {
        guard instance.tool == .staleTickets,
              let account = accountStore.activeAccount else {
            return
        }

        let preferences = instance.staleTicketsPreferences
        let configurationDraft = StaleTicketsConfigurationDraft(
            configuration: preferences.configuration,
            displayName: preferences.displayName,
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
            tableSort: preferences.tableSort,
            saveConfiguration: { [weak self] draft, configuration in
                guard let self else {
                    throw CancellationError()
                }

                let location = try draft.resolvedLocation()
                try self.updateStaleTicketsPreferences(for: instance.id) { preferences in
                    preferences.displayName = draft.displayName.trimmingCharacters(in: .whitespacesAndNewlines)
                    preferences.filterInput = draft.filterInput
                    preferences.queryMode = draft.queryMode
                    preferences.refreshInterval = draft.refreshInterval
                    preferences.isConfigured = true
                    preferences.alertSeverities = draft.alertSeverities
                    preferences.alertMode = draft.alertMode
                    preferences.configuration = configuration
                }
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

                try? self.updateStaleTicketsPreferences(for: instance.id) { preferences in
                    preferences.isWatching = isWatching
                }
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
            sortDidChange: { [weak self] tableSort in
                guard let self else {
                    return
                }

                try? self.updateStaleTicketsPreferences(for: instance.id) { preferences in
                    preferences.tableSort = tableSort
                }
            },
        )
        viewModel.isConfigurationPresented = !preferences.isConfigured
        viewModel.isWatching = preferences.isConfigured && preferences.isWatching
        staleTicketsViewModels[instance.id] = viewModel
    }

    private func updateStaleTicketsPreferences(
        for id: JiraToolInstance.ID,
        _ update: (inout StaleTicketsPreferences) -> Void,
    ) throws {
        guard let index = toolInstances.firstIndex(where: { $0.id == id }) else {
            throw JiraToolsError("This tool was removed.")
        }

        var instance = toolInstances[index]
        update(&instance.staleTicketsPreferences)
        toolInstances[index] = instance
        try saveToolInstances()
    }

    private func saveToolInstances() throws {
        try toolInstancesPreferencesStore.save(JiraToolInstancesPreferences(
            hasMigratedLegacyPreferences: true,
            instances: toolInstances,
        ))
    }
}
