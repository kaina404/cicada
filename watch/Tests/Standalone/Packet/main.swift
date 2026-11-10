import Foundation

for kind in ControlPacket.Kind.allCases {
  let packet = ControlPacket(kind: kind, session: .max, sequence: 0x01020304, gesture: .max, x: -0.5, y: 0.75)
  precondition(packet.data.count == 19)
  precondition(ControlPacket(data: packet.data) == packet)
}
for length in [0, 13, 18, 20] {
  precondition(ControlPacket(data: Data(repeating: 0, count: length)) == nil)
}
precondition(ControlPacket(data: Data(repeating: 0, count: 19)) == nil)
for value: Float in [.nan, .infinity, -.infinity, 5, -5] {
  precondition(ControlPacket(data: ControlPacket(x: value).data) == nil)
  precondition(ControlPacket(data: ControlPacket(y: value).data) == nil)
}
let bytes = Array(ControlPacket(session: 0x01020304, sequence: 0x05060708, gesture: 0x090A, x: 1).data)
precondition(Array(bytes.prefix(11)) == [0x21, 4, 3, 2, 1, 8, 7, 6, 5, 10, 9])
for kind in ControlPacket.Kind.allCases {
  let previous = ControlPacket(kind: kind, gesture: 2)
  for nextKind in ControlPacket.Kind.allCases {
    let next = ControlPacket(kind: nextKind, sequence: 1, gesture: 2)
    precondition(next.canReplace(previous) == (kind == nextKind && (kind == .move || kind == .hold)))
  }
}
precondition(!ControlPacket(session: 2).canReplace(ControlPacket(session: 1)))
print("PASS: V2 round trips, byte order, V1 rejection, malformed coordinates, button-state coalescing barriers")
