import Foundation
import JiraToolsCore

public struct JiraAccount: Codable, Equatable, Hashable, Identifiable, Sendable {
    public let authorizationKind: JiraAccountAuthorizationKind
    public let id: UUID
    public let siteURL: URL

    public init(
        id: UUID = UUID(),
        siteURL: URL,
        authorizationKind: JiraAccountAuthorizationKind,
    ) {
        self.id = id
        self.siteURL = siteURL
        self.authorizationKind = authorizationKind
    }
}

public enum JiraAccountAuthorizationKind: Codable, Equatable, Hashable, Sendable {
    case apiToken(email: String)
    case oauth(accountID: String)
}

public struct JiraAPITokenCredentials: Equatable, Sendable {
    public let account: JiraAccount
    public let email: String
    public let token: String

    public init(
        account: JiraAccount,
        email: String,
        token: String,
    ) {
        self.account = account
        self.email = email
        self.token = token
    }

    public var authorization: JiraAuthorization {
        .apiToken(email: email, token: token)
    }
}

public struct JiraAccountPreferences: Codable, Equatable, Sendable {
    public var activeAccount: JiraAccount?

    public init(activeAccount: JiraAccount? = nil) {
        self.activeAccount = activeAccount
    }
}
