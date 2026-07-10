import Foundation
import JiraToolsAppFoundation
import Testing

@Suite
struct CodablePreferencesStoreTests {
    @Test
    @MainActor
    func savesAndLoadsAccountMetadataWithoutCredentials() throws {
        let suiteName = "JiraToolsAppFoundationTests.\(UUID().uuidString)"
        guard let defaults = UserDefaults(suiteName: suiteName) else {
            Issue.record("Unable to create isolated UserDefaults suite")
            return
        }
        defer {
            defaults.removePersistentDomain(forName: suiteName)
        }

        let store = CodablePreferencesStore(
            defaults: defaults,
            key: "account",
            defaultValue: JiraAccountPreferences(),
        )
        let account = JiraAccount(
            siteURL: try #require(URL(string: "https://example.atlassian.net")),
            authorizationKind: .apiToken(email: "person@example.com"),
        )

        try store.save(JiraAccountPreferences(activeAccount: account))

        #expect(store.value.activeAccount == account)
        let encoded = try #require(defaults.data(forKey: "account"))
        #expect(!String(decoding: encoded, as: UTF8.self).contains("api-token-value"))
    }

    @Test
    @MainActor
    func returnsDefaultValueWhenNoValueHasBeenSaved() {
        let suiteName = "JiraToolsAppFoundationTests.\(UUID().uuidString)"
        guard let defaults = UserDefaults(suiteName: suiteName) else {
            Issue.record("Unable to create isolated UserDefaults suite")
            return
        }
        defer {
            defaults.removePersistentDomain(forName: suiteName)
        }

        let expected = JiraAccountPreferences()
        let store = CodablePreferencesStore(
            defaults: defaults,
            key: "account",
            defaultValue: expected,
        )

        #expect(store.value == expected)
        #expect(!store.hasSavedValue)
    }

    @Test
    @MainActor
    func tracksWhetherAValueHasBeenSaved() throws {
        let suiteName = "JiraToolsAppFoundationTests.\(UUID().uuidString)"
        guard let defaults = UserDefaults(suiteName: suiteName) else {
            Issue.record("Unable to create isolated UserDefaults suite")
            return
        }
        defer {
            defaults.removePersistentDomain(forName: suiteName)
        }

        let store = CodablePreferencesStore(
            defaults: defaults,
            key: "value",
            defaultValue: JiraAccountPreferences(),
        )

        #expect(!store.hasSavedValue)
        try store.save(JiraAccountPreferences())
        #expect(store.hasSavedValue)
        store.remove()
        #expect(!store.hasSavedValue)
    }
}
