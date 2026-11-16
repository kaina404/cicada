import Foundation

public struct FloatingAnswerState: Codable, Equatable {
  public let windowID: UUID?
  public let answerID: String
  public let sentences: [String]
  public let currentSentence: Int?
  public let canSelectSentence: Bool
  public let playback: Playback
  public let word: ReadingWord?
  public let canRefreshAnswer: Bool?

  public struct ReadingWord: Codable, Equatable {
    public let location: Int
    public let length: Int
    public let progress: Double
    public let fillsPrefix: Bool

    public init(range: NSRange, progress: Double, fillsPrefix: Bool) {
      self.location = range.location
      self.length = range.length
      self.progress = progress
      self.fillsPrefix = fillsPrefix
    }

    public func range(in sentence: String) -> Range<String.Index>? {
      guard location >= 0, length > 0, location <= sentence.utf16.count,
            length <= sentence.utf16.count - location else { return nil }
      return Range(NSRange(location: location, length: length), in: sentence)
    }
  }

  public enum Playback: String, Codable {
    case off, headphones, preparing, guiding, waiting, failed, ended
  }

  public init(windowID: UUID? = nil, answerID: String = "", sentences: [String] = [],
              currentSentence: Int? = nil, canSelectSentence: Bool = false, playback: Playback = .off,
              word: ReadingWord? = nil, canRefreshAnswer: Bool? = nil) {
    self.windowID = windowID
    self.answerID = answerID
    self.sentences = sentences
    self.currentSentence = currentSentence
    self.canSelectSentence = canSelectSentence
    self.playback = playback
    self.word = word
    self.canRefreshAnswer = canRefreshAnswer
  }

  func scoped(to windowID: UUID) -> Self {
    Self(windowID: windowID, answerID: answerID, sentences: sentences, currentSentence: currentSentence,
         canSelectSentence: canSelectSentence, playback: playback, word: word, canRefreshAnswer: canRefreshAnswer)
  }
}

struct FloatingAnswerPairing {
  static let scheme = "cicada-answer"
  static let tokenHeader = "X-Cicada-Phone-Token"
  static let windowHeader = "X-Cicada-Window"
  static let statePath = "floating-answer"
  static let controlPath = "floating-control"
  static let refreshPath = "floating-refresh"
  static let requestHeader = "X-Cicada-Request"
  static let screenPath = "mac-screen"

  static func isValidToken(_ token: String) -> Bool {
    token.utf8.count == 64 &&
      token.utf8.allSatisfy { (48...57).contains($0) || (97...102).contains($0) }
  }

  let host: String
  let port: UInt16
  let token: String

  init(host: String, port: UInt16, token: String) {
    self.host = host
    self.port = port
    self.token = token
  }

  var link: URL? {
    var components = URLComponents()
    components.scheme = Self.scheme
    components.host = host
    components.port = Int(port)
    components.queryItems = [URLQueryItem(name: "token", value: token)]
    return components.url
  }

  /// A fragment keeps the credential out of HTTP request URLs and access logs.
  var webLink: URL? {
    guard let endpoint = endpoint("remote"),
          var components = URLComponents(url: endpoint, resolvingAgainstBaseURL: false) else { return nil }
    components.fragment = "token=" + token
    return components.url
  }

  init?(link: URL) {
    guard let parts = URLComponents(url: link, resolvingAgainstBaseURL: false),
          let host = parts.host, host.lowercased().hasSuffix(".local"),
          let number = parts.port, let port = UInt16(exactly: number), port > 0,
          parts.user == nil, parts.password == nil else { return nil }
    let token: String
    if parts.scheme == Self.scheme, parts.path.isEmpty, parts.fragment == nil,
       let items = parts.queryItems, items.count == 1, items[0].name == "token", let value = items[0].value {
      token = value
    } else if parts.scheme == "http", parts.path == "/remote", parts.query == nil,
              let fragment = parts.fragment, fragment.hasPrefix("token=") {
      token = String(fragment.dropFirst(6))
    } else { return nil }
    guard Self.isValidToken(token) else { return nil }
    self.init(host: host, port: port, token: token)
  }

  func endpoint(_ path: String) -> URL? {
    var components = URLComponents()
    components.scheme = "http"
    components.host = host
    components.port = Int(port)
    components.path = "/" + path
    return components.url
  }
}
