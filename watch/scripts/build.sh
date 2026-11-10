#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/../.."
python3 watch/scripts/prepare.py
# Pass an explicit UDID destination and signing options to install on a device.
# With no arguments this only compiles; it does not boot or create simulators.
if [[ $# -eq 0 ]]; then
  set -- -destination 'generic/platform=watchOS' CODE_SIGNING_ALLOWED=NO
fi
exec xcodebuild -project watch/CicadaWatch.xcodeproj -scheme 'Cicada Watch App' \
  -configuration Debug -derivedDataPath build/watch "$@" build
