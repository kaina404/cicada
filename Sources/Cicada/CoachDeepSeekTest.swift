import Foundation

/// DeepSeek handles answer validity and text generation; local models handle microphone reading.
enum CoachDeepSeekTest {
    static var enabled: Bool {
        ProcessInfo.processInfo.environment["CICADA_COACH_PROVIDER"] != "local"
    }
    static let model = "deepseek-flash"

    static func body(_ messages: [[String: Any]]) -> [String: Any] {
        var references: [String] = []
        var pictures: [[String: Any]] = []
        for message in messages {
            if let text = message["content"] as? String { references.append(text) }
            if let parts = message["content"] as? [[String: Any]] {
                for part in parts {
                    if part["type"] as? String == "text", let text = part["text"] as? String { references.append(text) }
                    if part["type"] as? String == "image_url" { pictures.append(part) }
                }
            }
        }
        pictures.append(["type": "text", "text": "Follow the system task and its exact output protocol using the reference material and attached screen images."])
        return ["model": model, "stream": true, "temperature": 0, "max_tokens": 1600,
                "thinking": ["type": "disabled"],
                "messages": [["role": "system", "content": references.joined(separator: "\n\n")],
                             ["role": "user", "content": pictures]]]
    }
}
