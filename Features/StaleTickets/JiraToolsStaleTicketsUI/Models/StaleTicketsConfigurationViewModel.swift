import Combine
import Foundation
import JiraToolsStaleTickets

@MainActor
public final class StaleTicketsConfigurationViewModel: ObservableObject {
    @Published public var draft: StaleTicketsConfigurationDraft
    @Published public private(set) var request: StaleTicketsRequest
    @Published public private(set) var isConfigured: Bool
    public private(set) var savedDraft: StaleTicketsConfigurationDraft

    private let saveConfiguration: SaveStaleTicketsConfigurationUseCase

    public init(
        draft: StaleTicketsConfigurationDraft,
        request: StaleTicketsRequest,
        isConfigured: Bool,
        saveConfiguration: SaveStaleTicketsConfigurationUseCase,
    ) {
        self.draft = draft
        self.request = request
        self.isConfigured = isConfigured
        savedDraft = draft
        self.saveConfiguration = saveConfiguration
    }

    public func save() throws {
        let configuration = try draft.validatedConfiguration()
        request = try saveConfiguration(draft: draft, configuration: configuration)
        savedDraft = draft
        isConfigured = true
    }

    public func resetDraft() {
        draft = savedDraft
    }
}
