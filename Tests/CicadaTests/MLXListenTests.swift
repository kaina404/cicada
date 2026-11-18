import Foundation
import Testing
@testable import Cicada

/// The lines `mlx_listen_worker.py` writes, as the Qwen+Hy recognizer reads them.
struct MLXListenTests {
    @Test func readyLine() {
        guard case .ready = MLXListenEvent(["ready": true]) else { Issue.record("not ready"); return }
    }

    @Test func draftAndFinalBecomePieces() {
        guard case .heard(let draft) = MLXListenEvent(["draft": "Can you walk me", "start": 0.5, "end": 1.5]) else {
            Issue.record("no draft"); return
        }
        #expect(draft.text == "Can you walk me" && !draft.isFinal && draft.start == 0.5 && draft.end == 1.5)
        guard case .heard(let final) = MLXListenEvent(["final": "Can you walk me through it?", "start": 0.5, "end": 3.0]) else {
            Issue.record("no final"); return
        }
        #expect(final.isFinal && final.translation == nil)
    }

    /// A line can't end before it starts, whatever the worker's clock said.
    @Test func endNeverBeforeStart() {
        guard case .heard(let piece) = MLXListenEvent(["final": "Okay.", "start": 4.0, "end": 3.2]) else {
            Issue.record("no final"); return
        }
        #expect(piece.end == 4.0)
    }

    @Test func translationsByID() {
        guard case .translated(let id, let zh) = MLXListenEvent(["id": 7, "zh": " 你好。\n"]) else {
            Issue.record("no translation"); return
        }
        #expect(id == 7 && zh == "你好。")
        // A draft replaced while it waited, or a failed generation, comes back empty.
        guard case .translated(_, let none) = MLXListenEvent(["id": 8, "zh": NSNull()]) else {
            Issue.record("no translation"); return
        }
        #expect(none == nil)
        guard case .translated(_, let blank) = MLXListenEvent(["id": 9, "zh": "  "]) else {
            Issue.record("no translation"); return
        }
        #expect(blank == nil)
    }

    @Test func unknownLinesIgnored() {
        #expect(MLXListenEvent(["something": 1]) == nil)
        #expect(MLXListenEvent(["draft": "x", "start": Double.nan, "end": 1.0]) == nil)
    }
}
