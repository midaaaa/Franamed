import Foundation
import Synchronization

#if canImport(Security)
@_exported import Security
#else
typealias OSStatus = Int32
let errSecSuccess: OSStatus = 0
#endif
enum KeychainStore {
    private static let items = Mutex<[String: Data]>([:])

    static func read(_ key: String) -> Data? {
        items.withLock { $0[key] }
    }

    @discardableResult
    static func write(_ data: Data, for key: String) -> OSStatus {
        items.withLock { $0[key] = data }
        return errSecSuccess
    }

    @discardableResult
    static func delete(_ key: String) -> OSStatus {
        items.withLock { $0[key] = nil }
        return errSecSuccess
    }

    static func readString(_ key: String) -> String? {
        read(key).flatMap { String(data: $0, encoding: .utf8) }
    }

    @discardableResult
    static func writeString(_ value: String, for key: String) -> OSStatus {
        write(Data(value.utf8), for: key)
    }
}

enum DeviceSecret {
    static func loadOrCreate() throws -> String {
        if let existing = KeychainStore.readString("deviceSecret") { return existing }
        let secret = (0..<43).map { _ in String("abcdefghijklmnopqrstuvwxyz0123456789".randomElement()!) }.joined()
        KeychainStore.writeString(secret, for: "deviceSecret")
        return secret
    }

    static func reset() {
        KeychainStore.delete("deviceSecret")
    }
}
