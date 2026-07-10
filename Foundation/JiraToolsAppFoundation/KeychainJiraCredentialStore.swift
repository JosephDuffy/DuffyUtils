import Foundation
import Security

public struct KeychainJiraCredentialStore: Sendable {
    private let service: String

    public init(service: String = "com.josephduffy.JiraTools.credentials") {
        self.service = service
    }

    public func removeToken(for account: JiraAccount) throws {
        let status = SecItemDelete(baseQuery(for: account) as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw KeychainJiraCredentialStoreError.operationFailed(status: status)
        }
    }

    public func saveToken(
        _ token: String,
        for account: JiraAccount,
    ) throws {
        let data = Data(token.utf8)
        let updateStatus = SecItemUpdate(
            baseQuery(for: account) as CFDictionary,
            [kSecValueData: data] as CFDictionary,
        )

        if updateStatus == errSecSuccess {
            return
        }

        guard updateStatus == errSecItemNotFound else {
            throw KeychainJiraCredentialStoreError.operationFailed(status: updateStatus)
        }

        var query = baseQuery(for: account)
        query[kSecValueData] = data
        query[kSecAttrAccessible] = kSecAttrAccessibleWhenUnlocked
        let addStatus = SecItemAdd(query as CFDictionary, nil)
        guard addStatus == errSecSuccess else {
            throw KeychainJiraCredentialStoreError.operationFailed(status: addStatus)
        }
    }

    public func token(for account: JiraAccount) throws -> String? {
        var query = baseQuery(for: account)
        query[kSecMatchLimit] = kSecMatchLimitOne
        query[kSecReturnData] = true

        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        if status == errSecItemNotFound {
            return nil
        }
        guard status == errSecSuccess else {
            throw KeychainJiraCredentialStoreError.operationFailed(status: status)
        }
        guard let data = result as? Data,
              let token = String(data: data, encoding: .utf8) else {
            throw KeychainJiraCredentialStoreError.invalidStoredToken
        }
        return token
    }

    private func baseQuery(for account: JiraAccount) -> [CFString: Any] {
        [
            kSecClass: kSecClassGenericPassword,
            kSecAttrAccount: account.id.uuidString,
            kSecAttrService: service,
        ]
    }
}

public enum KeychainJiraCredentialStoreError: Error, Equatable, Sendable {
    case invalidStoredToken
    case operationFailed(status: OSStatus)
}
