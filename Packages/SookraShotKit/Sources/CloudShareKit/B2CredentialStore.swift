import Foundation
import Security

/// Backblaze B2 application key ID + key, stored together as JSON in the macOS
/// Keychain. Never touches UserDefaults or disk.
public enum B2CredentialStore {
    private static let service = "sookrashot-b2"
    private static let account = "default"

    public struct Credentials: Sendable {
        public let keyID: String
        public let appKey: String
    }

    public static var credentials: Credentials? {
        var query = baseQuery
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var item: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess,
              let data = item as? Data,
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: String],
              let keyID = object["keyID"], !keyID.isEmpty,
              let appKey = object["appKey"], !appKey.isEmpty
        else { return nil }
        return Credentials(keyID: keyID, appKey: appKey)
    }

    public static var hasCredentials: Bool { credentials != nil }

    public static func set(keyID: String, appKey: String) {
        let trimmedID = keyID.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedKey = appKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedID.isEmpty, !trimmedKey.isEmpty else {
            clear()
            return
        }
        guard let data = try? JSONSerialization.data(withJSONObject: ["keyID": trimmedID, "appKey": trimmedKey]) else { return }
        clear()
        var query = baseQuery
        query[kSecValueData as String] = data
        query[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
        SecItemAdd(query as CFDictionary, nil)
    }

    public static func clear() {
        SecItemDelete(baseQuery as CFDictionary)
    }

    private static var baseQuery: [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
    }
}
