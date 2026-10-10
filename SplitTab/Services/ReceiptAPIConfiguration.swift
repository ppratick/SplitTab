import Foundation
import Security

/// Personal-device credentials are kept out of source, preferences, and trip backups.
enum ReceiptAPIConfiguration {
    static let endpoint = URL(string: "https://api.openai.com/v1/chat/completions")!
    private static var query: [String: Any] {
        [kSecClass as String: kSecClassGenericPassword,
         kSecAttrService as String: "com.pratick.SplitTab.receipt-scanning",
         kSecAttrAccount as String: "openai-api-key"]
    }

    static func savedKey() throws -> String? {
        var request = query
        request[kSecReturnData as String] = true
        request[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: CFTypeRef?
        let status = SecItemCopyMatching(request as CFDictionary, &result)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess, let data = result as? Data,
              let key = String(data: data, encoding: .utf8) else { throw KeyError.storage(status) }
        return key
    }

    static func saveKey(_ input: String) throws {
        let key = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !key.isEmpty, !key.contains(where: { $0.isWhitespace }) else { throw KeyError.invalid }
        let values: [String: Any] = [kSecValueData as String: Data(key.utf8),
            kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlockedThisDeviceOnly]
        let status = SecItemUpdate(query as CFDictionary, values as CFDictionary)
        if status == errSecItemNotFound {
            let result = SecItemAdd(query.merging(values) { _, new in new } as CFDictionary, nil)
            guard result == errSecSuccess else { throw KeyError.storage(result) }
        } else if status != errSecSuccess { throw KeyError.storage(status) }
    }

    static func removeKey() throws {
        let status = SecItemDelete(query as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else { throw KeyError.storage(status) }
    }

    static func apiKey() throws -> String {
        if let key = try savedKey() { return key }
        return ProcessInfo.processInfo.environment["OPENAI_API_KEY"]?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    }

    enum KeyError: LocalizedError {
        case invalid, storage(OSStatus)
        var errorDescription: String? {
            switch self {
            case .invalid: return "Enter an API key without spaces or line breaks."
            case .storage(let status): return "Could not access the iPhone Keychain (error \(status)). Unlock your device and try again."
            }
        }
    }
}
