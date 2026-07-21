import Foundation
import JiraToolsFoundation
import Testing

@Suite
struct JiraAccountStoreTests {
    @Test
    @MainActor
    func savesTheTokenInKeychainAndOnlyMetadataInPreferences() throws {
        let suiteName = "JiraToolsFoundationTests.\(UUID().uuidString)"
        guard let defaults = UserDefaults(suiteName: suiteName) else {
            Issue.record("Unable to create isolated UserDefaults suite")
            return
        }
        defer {
            defaults.removePersistentDomain(forName: suiteName)
        }

        let account = JiraAccount(
            siteURL: try #require(URL(string: "https://example.atlassian.net")),
            authorizationKind: .apiToken(email: "person@example.com"),
        )
        let keychain = KeychainJiraCredentialStore(
            service: "JiraToolsFoundationTests.\(UUID().uuidString)",
        )
        defer {
            try? keychain.removeToken(for: account)
        }
        let preferences = CodablePreferencesStore(
            defaults: defaults,
            key: "account",
            defaultValue: JiraAccountPreferences(),
        )
        let store = JiraAccountStore(
            preferencesStore: preferences,
            credentialStore: keychain,
        )

        try store.save(account: account, apiToken: "api-token-value")

        #expect(store.activeAccount == account)
        #expect(try store.apiTokenCredentials()?.token == "api-token-value")
        let encoded = try #require(defaults.data(forKey: "account"))
        #expect(!String(decoding: encoded, as: UTF8.self).contains("api-token-value"))

        try store.removeActiveAccount()

        #expect(store.activeAccount == nil)
        #expect(try keychain.token(for: account) == nil)
    }
}
