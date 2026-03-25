import Foundation
import Security

final class FreeSaveCounter {
    let freeLimit = 5

    private let defaults: UserDefaults
    private let slidesSavedCountKey = "slidesSavedCount"

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        migrateToKeychainIfNeeded()
    }

    var slidesSavedCount: Int {
        get {
            max(0, keychainInt(forKey: slidesSavedCountKey) ?? defaults.integer(forKey: slidesSavedCountKey))
        }
        set {
            let value = max(0, newValue)
            setKeychainInt(value, forKey: slidesSavedCountKey)
            defaults.set(value, forKey: slidesSavedCountKey)
        }
    }

    var remainingFreeSaves: Int {
        max(0, freeLimit - slidesSavedCount)
    }

    func consumeSaves(_ n: Int) {
        guard n > 0 else { return }
        slidesSavedCount += n
    }

    // MARK: - PDF Export

    private let pdfExportsUsedKey = "pdfExportsUsed"
    private let freePDFExportLimit = 1

    var pdfExportsUsed: Int {
        get { max(0, keychainInt(forKey: pdfExportsUsedKey) ?? defaults.integer(forKey: pdfExportsUsedKey)) }
        set {
            let value = max(0, newValue)
            setKeychainInt(value, forKey: pdfExportsUsedKey)
            defaults.set(value, forKey: pdfExportsUsedKey)
        }
    }

    var hasFreeExportRemaining: Bool {
        pdfExportsUsed < freePDFExportLimit
    }

    func consumePDFExport() {
        pdfExportsUsed += 1
    }

    // MARK: - Keychain Persistence

    private let keychainService = "com.newsira.slidecrop.freecounter"

    private func migrateToKeychainIfNeeded() {
        let migrationKey = "keychainMigrated_v1"
        guard !defaults.bool(forKey: migrationKey) else { return }

        let savedCount = defaults.integer(forKey: slidesSavedCountKey)
        let pdfCount = defaults.integer(forKey: pdfExportsUsedKey)

        if savedCount > 0 { setKeychainInt(savedCount, forKey: slidesSavedCountKey) }
        if pdfCount > 0 { setKeychainInt(pdfCount, forKey: pdfExportsUsedKey) }

        defaults.set(true, forKey: migrationKey)
    }

    private func keychainInt(forKey key: String) -> Int? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: keychainService,
            kSecAttrAccount as String: key,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]

        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        guard status == errSecSuccess,
              let data = result as? Data,
              let string = String(data: data, encoding: .utf8),
              let value = Int(string) else {
            return nil
        }
        return value
    }

    private func setKeychainInt(_ value: Int, forKey key: String) {
        let data = String(value).data(using: .utf8)!
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: keychainService,
            kSecAttrAccount as String: key
        ]

        let existing = SecItemCopyMatching(query as CFDictionary, nil)
        if existing == errSecSuccess {
            SecItemUpdate(query as CFDictionary, [kSecValueData as String: data] as CFDictionary)
        } else {
            var newItem = query
            newItem[kSecValueData as String] = data
            newItem[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
            SecItemAdd(newItem as CFDictionary, nil)
        }
    }
}
