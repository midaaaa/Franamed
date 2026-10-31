import Foundation

#if os(Linux)
extension URL {
    static var applicationSupportDirectory: URL {
        FileManager.default.temporaryDirectory.appendingPathComponent("PvPKit/Application Support")
    }
}
#endif
