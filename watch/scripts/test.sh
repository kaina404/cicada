#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/../.."
mkdir -p build/watch-tests
xcrun swiftc watch/Shared/ControlPacket.swift watch/Tests/Standalone/Packet/main.swift -o build/watch-tests/packet
build/watch-tests/packet
xcrun swiftc watch/Shared/ControlPacket.swift watch/Mac/CursorState.swift watch/App/TouchState.swift \
  watch/Tests/Standalone/State/main.swift -o build/watch-tests/state
build/watch-tests/state
xcrun swiftc watch/Shared/ControlPacket.swift watch/Mac/CursorState.swift watch/Mac/CursorRenderer.swift \
  watch/Tests/Standalone/Renderer/main.swift -o build/watch-tests/renderer
build/watch-tests/renderer
xcrun swiftc watch/App/TouchMotion.swift watch/App/TouchState.swift watch/Shared/ControlPacket.swift \
  watch/Tests/Standalone/Precision/main.swift -o build/watch-tests/precision
build/watch-tests/precision
xcrun swiftc -parse-as-library watch/App/TransportState.swift watch/App/BluetoothTransport.swift \
  watch/Shared/ControlPacket.swift watch/App/WatchLink.swift watch/Tests/Standalone/Transport/main.swift \
  -o build/watch-tests/transport
build/watch-tests/transport
