import Foundation
import Observation
import UIKit

@MainActor
@Observable
final class RemoteAnswer {
    enum Connection { case unpaired, connecting, connected, offline, expired }
    enum Gesture { case move, hold }
    enum Screen { case waiting, off, unavailable, image(UIImage) }

    private(set) var connection = Connection.unpaired
    private(set) var answer = FloatingAnswerState()
    private(set) var holding = false
    private(set) var refreshing = false
    private(set) var refreshMessage: String?
    var canRefreshAnswer: Bool {
        connection == .connected && answer.windowID != nil && answer.canRefreshAnswer == true && !refreshing
    }
    @ObservationIgnored private var refreshTask: Task<Void, Never>?
    private(set) var screen = Screen.waiting
    private(set) var pairingStorageError = false

    @ObservationIgnored private var pairing: FloatingAnswerPairing?
    @ObservationIgnored private var pollTask: Task<Void, Never>?
    @ObservationIgnored private var sendTask: Task<Void, Never>?
    @ObservationIgnored private var holdTask: Task<Void, Never>?
    @ObservationIgnored private var pending: [ControlPacket] = []
    @ObservationIgnored private var input: Gesture?
    @ObservationIgnored private var session = UInt32.random(in: 1 ... .max)
    @ObservationIgnored private var sequence: UInt32 = 0
    @ObservationIgnored private var gesture: UInt16 = 0
    @ObservationIgnored private let network: URLSession
    @ObservationIgnored private let pairingFile: PhonePairingFile
    @ObservationIgnored private var saveAfterConnecting = false

    init() {
        pairingFile = PhonePairingFile(directory: URL.applicationSupportDirectory.appendingPathComponent("PhonePairing"))
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = 1.5
        configuration.timeoutIntervalForResource = 2
        configuration.urlCache = nil
        network = URLSession(configuration: configuration, delegate: LocalOnlyRequests(), delegateQueue: nil)
        pairing = pairingFile.read().flatMap(URL.init(string:)).flatMap(FloatingAnswerPairing.init(link:))
        if pairing != nil { connection = .connecting }
    }

    @discardableResult
    func connect(_ link: URL) -> Bool {
        guard let pairing = FloatingAnswerPairing(link: link) else { return false }
        suspend()
        self.pairing = pairing
        saveAfterConnecting = true
        resume()
        return true
    }

    func disconnect() {
        do { try pairingFile.remove() }
        catch { pairingStorageError = true; return }
        suspend()
        pairing = nil
        saveAfterConnecting = false
        connection = .unpaired
    }

    func dismissPairingStorageError() { pairingStorageError = false }

    func resume() {
        guard let pairing, pollTask == nil, connection != .expired else { return }
        connection = .connecting
        pollTask = Task { [weak self] in
            while !Task.isCancelled {
                guard let self else { return }
                let keepPolling = await self.poll(pairing)
                guard keepPolling else { return }
                let delay = self.connection == .offline ? 1000 :
                    (self.answer.playback == .guiding ? 45 : (self.answer.word == nil ? 150 : 80))
                try? await Task.sleep(for: .milliseconds(delay))
            }
        }
    }

    func dismissRefreshMessage() { refreshMessage = nil }

    func regenerate() {
        guard canRefreshAnswer, let pairing, let window = answer.windowID else { return }
        finishHold()
        cancelGesture(.move)
        refreshing = true
        refreshMessage = nil
        refreshTask = Task { [weak self] in
            guard let self else { return }
            defer { self.refreshing = false; self.refreshTask = nil }
            do {
                var request = try self.request(FloatingAnswerPairing.refreshPath, pairing: pairing)
                request.httpMethod = "POST"
                request.setValue(window.uuidString, forHTTPHeaderField: FloatingAnswerPairing.windowHeader)
                request.setValue(UUID().uuidString, forHTTPHeaderField: FloatingAnswerPairing.requestHeader)
                let (_, response) = try await self.network.data(for: request)
                guard !Task.isCancelled, self.answer.windowID == window else { return }
                switch (response as? HTTPURLResponse)?.statusCode {
                case 204: break // The streamed answer arrives through normal state polling.
                case 409: self.refreshMessage = "暂无可回答的问题，请确认 Mac 正在听取问题。"
                case 403: self.refreshMessage = "配对已失效，请重新配对。"
                default: self.refreshMessage = "请求失败，请重试或更新 Mac。"
                }
            } catch {
                guard !Task.isCancelled, self.answer.windowID == window else { return }
                self.refreshMessage = "请求超时，请重试。"
            }
        }
    }

    func suspend() {
        refreshTask?.cancel()
        refreshMessage = nil
        pollTask?.cancel()
        pollTask = nil
        clearInput()
        screen = .waiting
        answer = FloatingAnswerState()
        if pairing != nil, connection != .expired { connection = .connecting }
    }

    func watchScreen() async {
        guard let pairing else { return }
        defer { screen = .waiting }
        while !Task.isCancelled {
            do {
                let (data, response) = try await network.data(for: request(FloatingAnswerPairing.screenPath, pairing: pairing))
                guard !Task.isCancelled else { return }
                switch (response as? HTTPURLResponse)?.statusCode {
                case 200:
                    screen = UIImage(data: data).map(Screen.image) ?? .unavailable
                case 204: break
                case 403: return
                case 404, 409: screen = .off
                default: screen = .unavailable
                }
            } catch {
                guard !Task.isCancelled else { return }
                screen = .unavailable
            }
            let delay: Duration
            if case .image = screen { delay = .milliseconds(125) } else { delay = .milliseconds(500) }
            try? await Task.sleep(for: delay)
        }
    }

    func select(_ offset: Int) {
        guard answer.canSelectSentence, begin() else { return }
        enqueue(.sentence, y: offset < 0 ? -1 : 1)
        enqueue(.end)
    }

    func move(_ translation: CGSize, in size: CGSize) {
        if input == nil {
            guard begin() else { return }
            input = .move
        }
        guard input == .move else { return }
        let (x, y) = normalized(translation, in: size)
        enqueue(.move, x: x, y: y)
    }

    func finishMove(_ translation: CGSize, in size: CGSize) {
        guard input == .move else { return }
        input = nil
        let (x, y) = normalized(translation, in: size)
        enqueue(.end, x: x, y: y)
    }

    func startHold() {
        guard answer.canSelectSentence, answer.playback != .headphones, begin() else { return }
        input = .hold
        holdTask = Task { [weak self] in
            // Match the Watch's stationary hold threshold.
            do { try await Task.sleep(for: .milliseconds(400)) } catch { return }
            guard let self, self.input == .hold else { return }
            self.holding = true
            UISelectionFeedbackGenerator().selectionChanged()
            while !Task.isCancelled {
                self.enqueue(.hold)
                try? await Task.sleep(for: .milliseconds(100))
            }
        }
    }

    func finishHold() {
        guard input == .hold else { return }
        resetGesture()
        pending.removeAll { $0.kind == .hold }
        enqueue(.end)
    }

    func cancelGesture(_ kind: Gesture) {
        guard input == kind else { return }
        resetGesture()
        pending.removeAll { $0.kind == .hold || $0.kind == .move }
        enqueue(.cancel)
    }

    private func resetGesture() {
        holdTask?.cancel()
        holdTask = nil
        holding = false
        input = nil
    }

    private func clearInput() {
        resetGesture()
        sendTask?.cancel()
        sendTask = nil
        pending.removeAll()
    }

    private func begin() -> Bool {
        guard connection == .connected, answer.windowID != nil, input == nil else { return false }
        gesture &+= 1
        enqueue(.begin)
        return true
    }

    private func normalized(_ translation: CGSize, in size: CGSize) -> (Float, Float) {
        let scale = max(size.width, size.height, 1)
        return (Float(min(4, max(-4, translation.width / scale))),
                Float(min(4, max(-4, translation.height / scale))))
    }

    private func enqueue(_ kind: ControlPacket.Kind, x: Float = 0, y: Float = 0) {
        guard let pairing, let windowID = answer.windowID else { return }
        sequence &+= 1
        let packet = ControlPacket(kind: kind, session: session, sequence: sequence, gesture: gesture, x: x, y: y)
        if let last = pending.last, packet.canReplace(last) {
            pending[pending.count - 1] = packet
        } else {
            pending.append(packet)
        }
        guard sendTask == nil else { return }
        sendTask = Task { [weak self] in
            await self?.send(pairing, windowID: windowID)
        }
    }

    private func request(_ path: String, pairing: FloatingAnswerPairing) throws -> URLRequest {
        guard let url = pairing.endpoint(path) else { throw URLError(.badURL) }
        var request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData)
        request.setValue(pairing.token, forHTTPHeaderField: FloatingAnswerPairing.tokenHeader)
        return request
    }

    private func poll(_ pairing: FloatingAnswerPairing) async -> Bool {
        do {
            let (data, response) = try await network.data(for: request(FloatingAnswerPairing.statePath, pairing: pairing))
            guard !Task.isCancelled else { return false }
            let code = (response as? HTTPURLResponse)?.statusCode
            if code == 403 {
                if !saveAfterConnecting { try? pairingFile.remove() }
                clearInput()
                answer = FloatingAnswerState()
                connection = .expired
                pollTask = nil
                return false
            }
            guard code == 200 else { throw URLError(.badServerResponse) }
            let next = try JSONDecoder().decode(FloatingAnswerState.self, from: data)
            if saveAfterConnecting, let link = pairing.link {
                saveAfterConnecting = false
                do { try pairingFile.save(link.absoluteString) }
                catch { pairingStorageError = true }
            }
            if next.windowID != answer.windowID { clearInput() }
            if next.answerID != answer.answerID, input == .hold { finishHold() }
            answer = next
            connection = .connected
        } catch {
            guard !Task.isCancelled else { return false }
            clearInput()
            answer = FloatingAnswerState()
            connection = .offline
        }
        return true
    }

    private func send(_ pairing: FloatingAnswerPairing, windowID: UUID) async {
        while !pending.isEmpty, !Task.isCancelled {
            let packet = pending.removeFirst()
            do {
                var request = try request(FloatingAnswerPairing.controlPath, pairing: pairing)
                request.httpMethod = "POST"
                request.httpBody = packet.data
                request.setValue(windowID.uuidString, forHTTPHeaderField: FloatingAnswerPairing.windowHeader)
                let (_, response) = try await network.data(for: request)
                guard !Task.isCancelled else { return }
                guard (response as? HTTPURLResponse)?.statusCode == 204 else {
                    throw URLError(.badServerResponse)
                }
            } catch {
                guard !Task.isCancelled else { return }
                clearInput()
                answer = FloatingAnswerState()
                connection = .offline
                return
            }
        }
        if !Task.isCancelled { sendTask = nil }
    }
}

private final class LocalOnlyRequests: NSObject, URLSessionTaskDelegate {
    func urlSession(_ session: URLSession, task: URLSessionTask,
                    willPerformHTTPRedirection response: HTTPURLResponse, newRequest request: URLRequest,
                    completionHandler: @escaping @Sendable (URLRequest?) -> Void) {
        completionHandler(nil)
    }
}
