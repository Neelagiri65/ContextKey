import Foundation
import CryptoKit

// MARK: - Storage Service

/// Encrypted local storage for user context profiles using AES-256-GCM
@MainActor
final class StorageService: ObservableObject {

    @Published var profile: UserContextProfile?
    @Published var hasStoredProfile = false

    private let fileManager = FileManager.default
    private let profileFileName = "context_profile.encrypted"
    private let keyTag = "com.nativerse.contextkey.v2.encryptionkey"

    init() {
        // Check if a profile exists on init
        hasStoredProfile = fileManager.fileExists(atPath: profileFileURL.path)
    }

    // MARK: - Public API

    /// Save the profile encrypted to disk
    func save(_ profile: UserContextProfile) throws {
        let data = try JSONEncoder().encode(profile)
        let key = try getOrCreateKey()
        let sealedBox = try AES.GCM.seal(data, using: key)

        guard let combined = sealedBox.combined else {
            throw StorageError.encryptionFailed
        }

        try combined.write(to: profileFileURL)
        self.profile = profile
        self.hasStoredProfile = true
    }

    /// Load and decrypt the profile from disk
    func load() throws -> UserContextProfile {
        guard fileManager.fileExists(atPath: profileFileURL.path) else {
            throw StorageError.noProfileFound
        }

        let encryptedData = try Data(contentsOf: profileFileURL)
        let key = try getOrCreateKey()
        let sealedBox = try AES.GCM.SealedBox(combined: encryptedData)
        let decryptedData = try AES.GCM.open(sealedBox, using: key)

        let profile = try JSONDecoder().decode(UserContextProfile.self, from: decryptedData)
        self.profile = profile
        self.hasStoredProfile = true
        return profile
    }

    /// Delete all stored data permanently
    func deleteAll() throws {
        if fileManager.fileExists(atPath: profileFileURL.path) {
            try fileManager.removeItem(at: profileFileURL)
        }
        // Remove encryption key from keychain
        deleteKeyFromKeychain()
        self.profile = nil
        self.hasStoredProfile = false
    }

    /// Update existing profile with new facts (merge)
    func mergeAndSave(newFacts: [ContextFact], from platform: Platform, stats: ImportRecord) throws {
        var existingProfile: UserContextProfile
        if let loaded = try? load() {
            existingProfile = loaded
        } else {
            existingProfile = UserContextProfile()
        }

        // Merge new facts with existing
        for newFact in newFacts {
            let normalized = newFact.content.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
            if let idx = existingProfile.facts.firstIndex(where: {
                $0.content.lowercased().trimmingCharacters(in: .whitespacesAndNewlines) == normalized
            }) {
                // Update existing fact: bump confidence and update date
                existingProfile.facts[idx].confidence = min(1.0, existingProfile.facts[idx].confidence + 0.1)
                existingProfile.facts[idx].lastSeenDate = max(existingProfile.facts[idx].lastSeenDate, newFact.lastSeenDate)
            } else {
                existingProfile.facts.append(newFact)
            }
        }

        existingProfile.importHistory.append(stats)
        existingProfile.lastUpdated = Date()

        try save(existingProfile)
    }

    // MARK: - File Paths

    private var profileFileURL: URL {
        let documentsDir = fileManager.urls(for: .documentDirectory, in: .userDomainMask).first!
        return documentsDir.appendingPathComponent(profileFileName)
    }

    // MARK: - Encryption Key Management (Keychain)

    private func getOrCreateKey() throws -> SymmetricKey {
        // Try to load existing key from keychain
        if let keyData = loadKeyFromKeychain() {
            return SymmetricKey(data: keyData)
        }

        // Generate new key and store in keychain
        let key = SymmetricKey(size: .bits256)
        let keyData = key.withUnsafeBytes { Data($0) }
        try saveKeyToKeychain(keyData)
        return key
    }

    private func saveKeyToKeychain(_ keyData: Data) throws {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: keyTag,
            kSecValueData as String: keyData,
            kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlockedThisDeviceOnly
        ]

        // Delete any existing key first
        SecItemDelete(query as CFDictionary)

        let status = SecItemAdd(query as CFDictionary, nil)
        guard status == errSecSuccess else {
            throw StorageError.keychainError
        }
    }

    private func loadKeyFromKeychain() -> Data? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: keyTag,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]

        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        guard status == errSecSuccess else { return nil }
        return result as? Data
    }

    private func deleteKeyFromKeychain() {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: keyTag
        ]
        SecItemDelete(query as CFDictionary)
    }

    // MARK: - Errors

    enum StorageError: Error, LocalizedError {
        case encryptionFailed
        case noProfileFound
        case keychainError

        var errorDescription: String? {
            switch self {
            case .encryptionFailed: return "Failed to encrypt data."
            case .noProfileFound: return "No saved profile found."
            case .keychainError: return "Failed to access secure storage."
            }
        }
    }
}
