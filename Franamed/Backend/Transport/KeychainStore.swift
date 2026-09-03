//
//  KeychainStore.swift
//  Franamed
//
//  Created by Дмитрий Филимонов on 30.08.2026.
//

import Foundation
import Security

enum KeychainStore {
    private static let service = "com.franamed.backend"

    private static func query(for key: String) -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key
        ]
    }

    static func read(_ key: String) -> Data? {
        var lookup = query(for: key)
        lookup[kSecReturnData as String] = true
        lookup[kSecMatchLimit as String] = kSecMatchLimitOne

        var result: CFTypeRef?
        guard SecItemCopyMatching(lookup as CFDictionary, &result) == errSecSuccess else { return nil }
        return result as? Data
    }

    @discardableResult
    static func write(_ data: Data, for key: String) -> OSStatus {
        let attributes: [String: Any] = [
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        ]

        let status = SecItemUpdate(query(for: key) as CFDictionary, attributes as CFDictionary)
        guard status == errSecItemNotFound else { return status }

        return SecItemAdd(query(for: key).merging(attributes) { current, _ in current } as CFDictionary, nil)
    }

    @discardableResult
    static func delete(_ key: String) -> OSStatus {
        SecItemDelete(query(for: key) as CFDictionary)
    }

    static func readString(_ key: String) -> String? {
        read(key).flatMap { String(data: $0, encoding: .utf8) }
    }

    @discardableResult
    static func writeString(_ value: String, for key: String) -> OSStatus {
        write(Data(value.utf8), for: key)
    }
}
