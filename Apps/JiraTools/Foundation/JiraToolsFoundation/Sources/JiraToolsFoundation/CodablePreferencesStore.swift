import Foundation

@MainActor
public final class CodablePreferencesStore<Value: Codable> {
    private let defaultValue: Value
    private let defaults: UserDefaults
    private let key: String

    public init(
        defaults: UserDefaults = .standard,
        key: String,
        defaultValue: Value,
    ) {
        self.defaults = defaults
        self.key = key
        self.defaultValue = defaultValue
    }

    public var value: Value {
        guard let data = defaults.data(forKey: key) else {
            return defaultValue
        }

        do {
            return try JSONDecoder().decode(Value.self, from: data)
        } catch {
            return defaultValue
        }
    }

    public var hasSavedValue: Bool {
        defaults.data(forKey: key) != nil
    }

    public func save(_ value: Value) throws {
        let data = try JSONEncoder().encode(value)
        defaults.set(data, forKey: key)
    }

    public func remove() {
        defaults.removeObject(forKey: key)
    }
}
