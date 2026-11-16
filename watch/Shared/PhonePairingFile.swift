import Darwin
import Foundation

/// Stores the LAN credential separately from preferences and from the Watch pairing.
struct PhonePairingFile {
    let directory: URL
    private var file: URL { directory.appendingPathComponent("pairing") }

    func read() -> String? {
        try? String(contentsOf: file, encoding: .utf8)
    }

    func save(_ value: String) throws {
        let manager = FileManager.default
        try manager.createDirectory(at: directory, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        #if os(iOS)
        var privateDirectory = directory
        var resources = URLResourceValues()
        resources.isExcludedFromBackup = true
        try privateDirectory.setResourceValues(resources)
        #endif
        let staging = directory.appendingPathComponent(UUID().uuidString)
        guard manager.createFile(atPath: staging.path, contents: nil, attributes: [.posixPermissions: 0o600]) else {
            throw CocoaError(.fileWriteUnknown)
        }
        defer { try? manager.removeItem(at: staging) }
        try Data(value.utf8).write(to: staging)
        guard rename(staging.path, file.path) == 0 else { throw CocoaError(.fileWriteUnknown) }
    }

    func remove() throws {
        do { try FileManager.default.removeItem(at: file) }
        catch let error as CocoaError where error.code == .fileNoSuchFile {}
    }
}
