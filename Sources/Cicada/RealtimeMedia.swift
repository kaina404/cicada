import AppKit
import Foundation

struct RealtimeImageGate {
    private(set) var lastAt = -Double.infinity
    private var lastSignature: [UInt8]?
    mutating func allow(signature: [UInt8], now: Double, audioSent: Bool, slide: Bool) -> Bool {
        guard audioSent, slide, now - lastAt >= 1 else { return false }
        if let lastSignature, ScreenWatch.difference(lastSignature, signature) < 0.015 { return false }
        lastAt = now; lastSignature = signature
        return true
    }
}

enum RealtimeMedia {
    static func pcm(_ samples: [Float]) -> Data {
        var data = Data(capacity: samples.count * 2)
        for sample in samples {
            let value = sample.isFinite ? max(-1, min(1, sample)) : 0
            let integer = Int16(max(-32768, min(32767, (Double(value) * 32768).rounded())))
            var little = integer.littleEndian
            withUnsafeBytes(of: &little) { data.append(contentsOf: $0) }
        }
        return data
    }
    static func jpeg(_ image: CGImage) -> Data? {
        for side in [1280, 960, 640, 320] {
            let ratio = min(1, Double(side) / Double(max(image.width, image.height)))
            let width = max(1, Int(Double(image.width) * ratio)), height = max(1, Int(Double(image.height) * ratio))
            guard let ctx = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                                      space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue) else { return nil }
            ctx.interpolationQuality = .medium
            ctx.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
            guard let scaled = ctx.makeImage() else { return nil }
            let rep = NSBitmapImageRep(cgImage: scaled)
            for quality in [0.7, 0.5, 0.3, 0.1] {
                if let data = rep.representation(using: .jpeg, properties: [.compressionFactor: quality]), data.count < 190_000 { return data }
            }
        }
        return nil
    }
}

@MainActor
enum CandidateBackground {
    static var file: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent(DevBuild.supportFolder).appendingPathComponent("candidate-background.md")
    }
    static func read() -> String { (try? String(contentsOf: file, encoding: .utf8)) ?? "" }
    static func save(_ text: String) throws {
        let fm = FileManager.default
        try fm.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        if !fm.fileExists(atPath: file.path) {
            guard fm.createFile(atPath: file.path, contents: nil, attributes: [.posixPermissions: 0o600]) else { throw CocoaError(.fileWriteUnknown) }
        }
        try fm.setAttributes([.posixPermissions: 0o600], ofItemAtPath: file.path)
        try Data(text.utf8).write(to: file)
        var url = file
        var values = URLResourceValues(); values.isExcludedFromBackup = true
        try url.setResourceValues(values)
    }
    static func imported(_ raw: String) -> String {
        guard let object = try? JSONSerialization.jsonObject(with: Data(raw.utf8)) as? [String: Any],
              let resume = object["candidate_resume"] as? [String] else { return raw }
        return "Candidate resume\n" + resume.joined(separator: "\n") + "\nCompany brief (user supplied)\n"
            + ((object["company_brief_user_supplied"] as? [String]) ?? []).joined(separator: "\n")
    }
}
