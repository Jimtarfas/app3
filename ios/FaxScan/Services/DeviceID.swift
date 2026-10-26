import Foundation
import Security

/// A random identifier for this install, kept in the Keychain so fax history
/// status lookups keep working after an app update. It isn't tied to the person.
enum DeviceID {
    private static let account = "device-id"
    private static let service = "com.faxandscan.app"

    static let current: UUID = {
        if let existing = read() { return existing }
        let id = UUID()
        write(id)
        return id
    }()

    private static func read() -> UUID? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
        ]
        var item: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess,
              let data = item as? Data, let string = String(data: data, encoding: .utf8) else { return nil }
        return UUID(uuidString: string)
    }

    private static func write(_ id: UUID) {
        let item: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly,
            kSecValueData as String: Data(id.uuidString.utf8),
        ]
        SecItemAdd(item as CFDictionary, nil)
    }
}
