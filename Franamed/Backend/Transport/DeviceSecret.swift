//
//  DeviceSecret.swift
//  Franamed
//
//  Created by Дмитрий Филимонов on 30.08.2026.
//

import Foundation

enum DeviceSecret {
    private static let key = "deviceSecret"
    private static let byteCount = 32

    static func loadOrCreate() throws -> String {
        if let existing = KeychainStore.readString(key) { return existing }

        var bytes = [UInt8](repeating: 0, count: byteCount)
        guard SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes) == errSecSuccess else {
            throw BackendError.randomGeneratorUnavailable
        }

        let secret = Data(bytes).base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")

        let status = KeychainStore.writeString(secret, for: key)
        guard status == errSecSuccess else { throw BackendError.keychainFailure(status) }

        return secret
    }

    static func reset() {
        KeychainStore.delete(key)
    }
}
