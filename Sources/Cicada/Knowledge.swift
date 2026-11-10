import Foundation

/// The candidate's fixed reference material: Markdown files the user keeps up to date in one
/// folder, read whole into the interview prompt. No retrieval: a line-level search lost key
/// numbers and split "which project at which company".
enum Knowledge {
    /// File → tag, in prompt order. The tag names the module for the model; the file stays plain Markdown.
    static let parts: [(file: String, tag: String, title: String)] = [
        ("00_profile.md", "profile", "个人简介"),
        ("01_job_target.md", "job_target", "求职需求"),
        ("02_companies_past.md", "past_companies", "历史公司"),
        ("03_projects.md", "projects", "项目经验"),
        ("04_talk_tracks.md", "talk_tracks", "预制回答"),
        ("05_target_company.md", "target_company", "目标公司"),
    ]

    @MainActor static var folder: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent(DevBuild.supportFolder).appendingPathComponent("knowledge")
    }

    /// Empty modules are left out, so a half-filled folder still reads cleanly.
    static func assemble(_ texts: [String: String]) -> String {
        parts.compactMap { part in
            let text = (texts[part.file] ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            return text.isEmpty ? nil : "<\(part.tag)>\n\(text)\n</\(part.tag)>"
        }.joined(separator: "\n")
    }

    @MainActor static func read() -> String {
        var texts: [String: String] = [:]
        for part in parts {
            texts[part.file] = try? String(contentsOf: folder.appendingPathComponent(part.file), encoding: .utf8)
        }
        return assemble(texts)
    }

    /// Personal data: the folder is 0700 and new files 0600, kept out of backups like AI keys.
    @MainActor static func prepareFolder() throws {
        let fm = FileManager.default
        try fm.createDirectory(at: folder, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        for part in parts {
            let file = folder.appendingPathComponent(part.file)
            if !fm.fileExists(atPath: file.path) {
                guard fm.createFile(atPath: file.path, contents: Data("# \(part.title)\n".utf8),
                                    attributes: [.posixPermissions: 0o600]) else { throw CocoaError(.fileWriteUnknown) }
            }
        }
        var url = folder
        var values = URLResourceValues(); values.isExcludedFromBackup = true
        try url.setResourceValues(values)
    }
}
