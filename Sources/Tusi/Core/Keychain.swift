import Foundation
import Security

/// Both API keys live in a single Keychain item.
///
/// macOS authorizes access per item, so one item per slot meant one password prompt per
/// slot on every launch. The keys are always read together anyway, so storing them as one
/// JSON blob makes that exactly one prompt.
enum Keychain {
    private static let service = "com.tusi.app"
    private static let account = "apiKeys"
    private static let legacyAccounts = ["apiKey.0", "apiKey.1", "apiKey"]

    /// Keys by slot index. Missing slots are simply absent.
    static func loadKeys() -> [Int: String] {
        guard let data = read(account: account),
              let raw = try? JSONDecoder().decode([String: String].self, from: data)
        else { return [:] }
        return raw.reduce(into: [:]) { result, pair in
            if let index = Int(pair.key) { result[index] = pair.value }
        }
    }

    static func saveKeys(_ keys: [Int: String]) {
        let raw = keys
            .filter { !$0.value.isEmpty }
            .reduce(into: [String: String]()) { $0[String($1.key)] = $1.value }

        guard !raw.isEmpty else {
            delete(account: account)
            return
        }
        guard let data = try? JSONEncoder().encode(raw) else { return }
        write(data, account: account)
    }

    /// Folds the old one-item-per-slot layout into the combined item. Returns the keys it
    /// recovered, or nil when there was nothing to migrate.
    static func migrateLegacyKeysIfNeeded() -> [Int: String]? {
        var recovered: [Int: String] = [:]
        var found = false
        for legacy in legacyAccounts {
            guard let data = read(account: legacy), let value = String(data: data, encoding: .utf8) else { continue }
            found = true
            // "apiKey" predates slots entirely and was always the primary.
            let index = legacy == "apiKey" ? 0 : Int(legacy.suffix(1)) ?? 0
            if recovered[index] == nil, !value.isEmpty { recovered[index] = value }
        }
        guard found else { return nil }
        saveKeys(recovered)
        legacyAccounts.forEach { delete(account: $0) }
        return recovered
    }

    // MARK: - Raw item access

    private static func baseQuery(account: String) -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
    }

    private static func read(account: String) -> Data? {
        var query = baseQuery(account: account)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: AnyObject?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess else { return nil }
        return result as? Data
    }

    private static func write(_ data: Data, account: String) {
        let query = baseQuery(account: account)
        let attributes: [String: Any] = [kSecValueData as String: data]
        if SecItemUpdate(query as CFDictionary, attributes as CFDictionary) == errSecItemNotFound {
            var addQuery = query
            addQuery[kSecValueData as String] = data
            SecItemAdd(addQuery as CFDictionary, nil)
        }
    }

    private static func delete(account: String) {
        SecItemDelete(baseQuery(account: account) as CFDictionary)
    }
}
