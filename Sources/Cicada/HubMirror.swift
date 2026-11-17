import Foundation
import os

/// huggingface.co (Gemma, Smart Turn, Kokoro weights) and PyPI are often unreachable or very slow
/// from mainland China. hf-mirror.com serves the same Hub API, which huggingface_hub and mlx-vlm
/// follow through HF_ENDPOINT, and Aliyun mirrors PyPI. The official hosts stay first: the mirrors
/// are used only when huggingface.co does not answer. Pinned revisions and SHA-256 checks in the
/// workers still decide what is loaded.
enum HubMirror {
    static let hub = "https://hf-mirror.com"
    static let pip = "https://mirrors.aliyun.com/pypi/simple/"
    /// nil until probed; a forced value (debug `hubMirror:`) is never re-probed.
    private static let state = OSAllocatedUnfairLock<(mirrored: Bool?, forced: Bool)>(initialState: (nil, false))

    static var mirrored: Bool { state.withLock { $0.mirrored } == true }

    /// Probes once per launch; later calls return at once.
    static func resolve() async {
        guard state.withLock({ $0.mirrored }) == nil else { return }
        var request = URLRequest(url: URL(string: "https://huggingface.co/api/models/pipecat-ai/smart-turn-v3")!,
                                 timeoutInterval: 4)
        request.httpMethod = "HEAD"
        let reachable = (try? await URLSession.shared.data(for: request)) != nil
        state.withLock { if !$0.forced { $0.mirrored = !reachable } }
        debugLog("hub: huggingface.co \(reachable ? "reachable" : "unreachable, downloads use \(hub)")")
    }

    /// nil probes again at the next `resolve`.
    static func force(_ mirrored: Bool?) {
        state.withLock { $0 = (mirrored, mirrored != nil) }
    }

    /// For a process that may download models or packages. The user's own variables win.
    static func environment(_ base: [String: String] = ProcessInfo.processInfo.environment) -> [String: String] {
        environment(base, mirrored: mirrored)
    }

    static func environment(_ base: [String: String], mirrored: Bool) -> [String: String] {
        guard mirrored else { return base }
        var environment = base
        if environment["HF_ENDPOINT"] == nil { environment["HF_ENDPOINT"] = hub }
        if environment["PIP_INDEX_URL"] == nil { environment["PIP_INDEX_URL"] = pip }
        return environment
    }
}
