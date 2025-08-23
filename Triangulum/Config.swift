import Foundation

struct Config {
    /// OpenWeatherMap API Key from secure Keychain storage
    static var openWeatherAPIKey: String {
        // Try environment variable first (for development/CI)
        if let envKey = ProcessInfo.processInfo.environment["OPENWEATHER_API_KEY"],
           !envKey.isEmpty,
           envKey != "your_api_key_here" {
            return envKey
        }
        
        // Try Keychain storage (primary method)
        if let keychainKey = KeychainHelper.shared.getOpenWeatherAPIKey(),
           !keychainKey.isEmpty {
            return keychainKey
        }
        
        return ""
    }
    
    /// Check if API key is available and valid
    static var hasValidAPIKey: Bool {
        return !openWeatherAPIKey.isEmpty
    }
    
    /// Store API key securely in Keychain
    static func storeAPIKey(_ apiKey: String) -> Bool {
        guard !apiKey.isEmpty, apiKey != "your_api_key_here" else { return false }
        return KeychainHelper.shared.storeOpenWeatherAPIKey(apiKey)
    }
    
    /// Delete stored API key from Keychain
    static func deleteAPIKey() -> Bool {
        return KeychainHelper.shared.deleteOpenWeatherAPIKey()
    }
}