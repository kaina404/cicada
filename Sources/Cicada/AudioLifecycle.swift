import Foundation

/// Hardware input creation, disposal and format queries share one lane. None may wait on UI.
enum AudioLifecycle {
    static let queue = DispatchQueue(label: "com.wquguru.cicada.audio-lifecycle", qos: .userInitiated)
}

/// A newer device event replaces pending work; stopping also invalidates callbacks from old sources.
struct AudioRevision {
    private(set) var value: UInt64 = 0

    @discardableResult
    mutating func advance() -> UInt64 {
        value &+= 1
        return value
    }

    func accepts(_ revision: UInt64) -> Bool { value == revision }
}

@MainActor
final class AudioReconnect {
    private var revision = AudioRevision()
    private var work: DispatchWorkItem?

    func schedule(after delay: TimeInterval = 0.2, _ action: @escaping () -> Void) {
        let current = revision.advance()
        work?.cancel()
        let next = DispatchWorkItem { [weak self] in
            MainActor.assumeIsolated {
                guard let self, self.revision.accepts(current) else { return }
                self.work = nil
                action()
            }
        }
        work = next
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: next)
    }

    func cancel() {
        revision.advance()
        work?.cancel()
        work = nil
    }
}
