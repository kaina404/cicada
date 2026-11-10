import Foundation

/// V2: 19 bytes, within the minimum BLE write payload. V1 panel packets are rejected.
struct ControlPacket: Equatable {
  enum Kind: UInt8, CaseIterable {
    case begin = 0x20, move, hold, end, click, cancel, sentence
  }
  static let byteCount = 19
  let kind: Kind
  let session: UInt32
  let sequence: UInt32
  let gesture: UInt16
  let x: Float
  let y: Float

  init(kind: Kind = .move, session: UInt32 = 1, sequence: UInt32 = 0,
       gesture: UInt16 = 0, x: Float = 0, y: Float = 0) {
    self.kind = kind
    self.session = session
    self.sequence = sequence
    self.gesture = gesture
    self.x = x
    self.y = y
  }

  var data: Data {
    var bytes = Data([kind.rawValue])
    for value in [session, sequence] {
      for shift in stride(from: 0, to: 32, by: 8) {
        bytes.append(UInt8(truncatingIfNeeded: value >> shift))
      }
    }
    bytes.append(UInt8(truncatingIfNeeded: gesture))
    bytes.append(UInt8(truncatingIfNeeded: gesture >> 8))
    for value in [x.bitPattern, y.bitPattern] {
      for shift in stride(from: 0, to: 32, by: 8) {
        bytes.append(UInt8(truncatingIfNeeded: value >> shift))
      }
    }
    return bytes
  }

  init?(data: Data) {
    let bytes = Array(data)
    guard bytes.count == Self.byteCount, let kind = Kind(rawValue: bytes[0]) else { return nil }
    func word(_ offset: Int) -> UInt32 {
      (0..<4).reduce(0) { $0 | UInt32(bytes[offset + $1]) << ($1 * 8) }
    }
    let x = Float(bitPattern: word(11)), y = Float(bitPattern: word(15))
    guard x.isFinite, y.isFinite, abs(x) <= 4, abs(y) <= 4 else { return nil }
    self.init(kind: kind, session: word(1), sequence: word(5),
              gesture: UInt16(bytes[9]) | UInt16(bytes[10]) << 8, x: x, y: y)
  }

  /// Only continuous movement with the same button state may replace a queued update.
  func canReplace(_ previous: ControlPacket) -> Bool {
    (kind == .move || kind == .hold) && kind == previous.kind &&
      session == previous.session && gesture == previous.gesture
  }
}
