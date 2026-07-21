import Foundation

@MainActor
public final class JiraAccountStore {
    private let credentialStore: KeychainJiraCredentialStore
    private let preferencesStore: CodablePreferencesStore<JiraAccountPreferences>

    public init(
        preferencesStore: CodablePreferencesStore<JiraAccountPreferences> = CodablePreferencesStore(
            key: "com.josephduffy.JiraTools.account-preferences",
            defaultValue: JiraAccountPreferences(),
        ),
        credentialStore: KeychainJiraCredentialStore = KeychainJiraCredentialStore(),
    ) {
        self.preferencesStore = preferencesStore
        self.credentialStore = credentialStore
    }

    public var activeAccount: JiraAccount? {
        preferencesStore.value.activeAccount
    }

    public var hasCredentials: Bool {
        activeAccount != nil
    }

    public func apiTokenCredentials() throws -> JiraAPITokenCredentials? {
        guard let activeAccount else {
            return nil
        }
        guard case .apiToken(let email) = activeAccount.authorizationKind else {
            throw JiraAccountStoreError.unsupportedAuthorizationKind
        }
        guard let token = try credentialStore.token(for: activeAccount), !token.isEmpty else {
            throw JiraAccountStoreError.missingCredential
        }
        return JiraAPITokenCredentials(account: activeAccount, email: email, token: token)
    }

    public func removeActiveAccount() throws {
        guard let activeAccount else {
            return
        }

        try credentialStore.removeToken(for: activeAccount)
        try preferencesStore.save(JiraAccountPreferences())
    }

    public func save(
        account: JiraAccount,
        apiToken: String,
    ) throws {
        guard case .apiToken = account.authorizationKind else {
            throw JiraAccountStoreError.unsupportedAuthorizationKind
        }
        guard !apiToken.isEmpty else {
            throw JiraAccountStoreError.emptyCredential
        }

        try credentialStore.saveToken(apiToken, for: account)
        try preferencesStore.save(JiraAccountPreferences(activeAccount: account))
    }
}

public enum JiraAccountStoreError: Error, Equatable, Sendable {
    case emptyCredential
    case missingCredential
    case unsupportedAuthorizationKind
}
