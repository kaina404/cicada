# Cicada Apple Watch module

The user explicitly expanded scope to Apple Watch. Keep watchOS code and its Xcode project here; the Mac app remains a Swift Package built by Command Line Tools.

- `App/`: watchOS UI, touch gestures and LAN/BLE client.
- `Shared/`: V2 packet definition compiled by both builds.
- `Mac/`: `CicadaWatchControl` library, linked into Cicada. Operate only the visible `cicada.assistant` window passed by the owning app. No system mouse events, Accessibility permission or external IPC helper.
- `Tests/`: packet, motion, transport and window/receiver regressions.
- Run `scripts/prepare.py` before Xcode builds. Local pairing and generated version config are gitignored; never commit tokens or include local pairing in public releases.
- App version comes from repository `VERSION`. Preserve Mac bundle IDs and the existing ad-hoc designated requirement.
- No standalone WatchControl process is required. Port 8765 and BLE UUID/header formats remain compatible with the previous client.
- Build watchOS with `scripts/build.sh`. Generic destination compilation is not device validation. Use the current task's device/tool rules for installation or simulator checks.
