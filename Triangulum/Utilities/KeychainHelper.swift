import Foundation
import Security

/// A utility class for securely storing and retrieving data from the iOS Keychain
class KeychainHelper {

    static let shared = KeychainHelper()

    private init() {}

    /// Store a string value in the Keychain
    /// - Parameters:
    ///   - value: The string value to store
    ///   - key: The key to associate with the value
    /// - Returns: True if the value was successfully stored, false otherwise
    @discardableResult
    func store(_ value: String, forKey key: String) -> Bool {
        guard let data = value.data(using: .utf8) else { return false }
        return store(data, forKey: key)
    }

    /// Store data in the Keychain
    /// - Parameters:
    ///   - data: The data to store
    ///   - key: The key to associate with the data
    /// - Returns: True if the data was successfully stored, false otherwise
    @discardableResult
    func store(_ data: Data, forKey key: String) -> Bool {
        // Delete existing item first (in case it exists)
        delete(key)

        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: key,
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlockedThisDeviceOnly
        ]

        let status = SecItemAdd(query as CFDictionary, nil)
        return status == errSecSuccess
    }

    /// Retrieve a string value from the Keychain
    /// - Parameter key: The key associated with the value
    /// - Returns: The string value if found, nil otherwise
    func retrieve(forKey key: String) -> String? {
        guard let data = retrieveData(forKey: key) else { return nil }
        return String(data: data, encoding: .utf8)
    }

    /// Retrieve data from the Keychain
    /// - Parameter key: The key associated with the data
    /// - Returns: The data if found, nil otherwise
    func retrieveData(forKey key: String) -> Data? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: key,
            kSecReturnData as String: kCFBooleanTrue!,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]

        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)

        guard status == errSecSuccess else { return nil }
        return result as? Data
    }

    /// Delete an item from the Keychain
    /// - Parameter key: The key associated with the item to delete
    /// - Returns: True if the item was successfully deleted or didn't exist, false otherwise
    @discardableResult
    func delete(_ key: String) -> Bool {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: key
        ]

        let status = SecItemDelete(query as CFDictionary)
        return status == errSecSuccess || status == errSecItemNotFound
    }

    /// Check if an item exists in the Keychain
    /// - Parameter key: The key to check for
    /// - Returns: True if the item exists, false otherwise
    func exists(forKey key: String) -> Bool {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: key,
            kSecReturnData as String: kCFBooleanFalse!,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]

        let status = SecItemCopyMatching(query as CFDictionary, nil)
        return status == errSecSuccess
    }
}

// MARK: - App-Specific Keys
extension KeychainHelper {

    /// Keys for storing app-specific data
    struct Keys {
        static let openWeatherAPIKey = "com.triangulum.openweather.apikey"
    }

    /// Store the OpenWeatherMap API key securely
    /// - Parameter apiKey: The API key to store
    /// - Returns: True if successfully stored
    func storeOpenWeatherAPIKey(_ apiKey: String) -> Bool {
        return store(apiKey, forKey: Keys.openWeatherAPIKey)
    }

    /// Retrieve the OpenWeatherMap API key
    /// - Returns: The API key if stored, nil otherwise
    func getOpenWeatherAPIKey() -> String? {
        return retrieve(forKey: Keys.openWeatherAPIKey)
    }

    /// Delete the stored OpenWeatherMap API key
    /// - Returns: True if successfully deleted
    func deleteOpenWeatherAPIKey() -> Bool {
        return delete(Keys.openWeatherAPIKey)
    }

    /// Check if OpenWeatherMap API key is stored
    /// - Returns: True if API key exists in keychain
    func hasOpenWeatherAPIKey() -> Bool {
        return exists(forKey: Keys.openWeatherAPIKey)
    }
}
