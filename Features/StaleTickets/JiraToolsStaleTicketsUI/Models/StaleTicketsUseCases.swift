import JiraToolsAppFoundation
import JiraToolsCore
import JiraToolsStaleTickets
import UseCaseMacro

@MainActor
@UseCase
public struct SaveStaleTicketsConfigurationUseCase: Sendable {
    public func callAsFunction(
        draft: StaleTicketsConfigurationDraft,
        configuration: StaleTicketsConfiguration,
    ) throws -> StaleTicketsRequest
}

@MainActor
@UseCase
public struct LoadStaleTicketsAuthorizationUseCase: Sendable {
    public func callAsFunction() throws -> JiraAuthorization
}

@MainActor
@UseCase
public struct HandleStaleTicketsWatchingChangeUseCase: Sendable {
    public func callAsFunction(isWatching: Bool)
}

@MainActor
@UseCase
public struct DeliverStaleTicketsAlertUseCase: Sendable {
    public func callAsFunction(
        reports: [StaleTicketsReport],
        severities: Set<Severity>,
        mode: JiraToolsAlertMode,
    ) async
}

@MainActor
@UseCase
public struct SaveStaleTicketsTableSortUseCase: Sendable {
    public func callAsFunction(tableSort: StaleTicketsTableSort)
}

@UseCase
public struct RefreshStaleTicketsUseCase: Sendable {
    public func callAsFunction(
        request: StaleTicketsRequest,
        cache: StaleTicketsRefreshCache,
    ) -> AsyncThrowingStream<StaleTicketsSnapshot, Error>
}
