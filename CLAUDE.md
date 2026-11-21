# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project

Small SwiftUI iOS 16+ app ("Buds Battery") showing Galaxy Buds left/right/case battery (Liquid Glass UI on iOS 26+). Sources: BLE advertisements and GATT Battery Service. Installed via Feather. Not affiliated with Samsung.

## Build / test

`.xcodeproj` is generated from `project.yml` (XcodeGen); needs macOS/Xcode, so CI (`.github/workflows/build.yml`, `macos-26`) is the real verification and produces an unsigned IPA.

- Decoder tests (plain executable, `precondition`-based): `swiftc Sources/BudsDecoder.swift Sources/History.swift Tests/main.swift -o /tmp/buds-tests && /tmp/buds-tests`
- App: `xcodegen generate`, then `xcodebuild -project BudsBattery.xcodeproj -scheme BudsBattery -configuration Release -destination 'generic/platform=iOS' CODE_SIGNING_ALLOWED=NO build`

## Architecture

- `BudsDecoder.swift` — pure parser (Foundation only; tests compile it standalone). Samsung manufacturer data, header `75 00 42 09 81 02 14 15 03 21 01`; status at offset 26, 6-byte token 27..<33, then case/left/right percentages, 3-byte suffix. Values >100 = unavailable. Layout inferred from Buds3 Pro captures, not a published protocol.
- `History.swift` — Foundation-only history samples plus trend and remaining-time estimate (also compiled by the tests).
- `BudsStore.swift` — two sources merged per channel via `update()`: GATT Battery Service (180F/2A19, labelled by 2904 description ids 0x010D left / 0x010E right / 0x0110 case only for model SM-R630; preferred; the Samsung device is found among system-connected peripherals by its vendor service `A7A473E9-…`, so renamed earbuds work) and the foreground broadcast scan. Setup lists nearby sets as `Candidate`s; `choose()` locks onto one by token. Keeps last-known level + timestamp per channel and a capped change history in UserDefaults.
- `Theme.swift` — `glassCard()` / `glassButton()` use Liquid Glass on iOS 26+ (behind `#if compiler(>=6.2)` so older Xcode still builds) and a material fallback; `AuroraBackground`.
- `Localization.swift` — `L("English text", args…)`; translations live in `Sources/Resources/<lang>.lproj/Localizable.strings` (English text is the key, so a missing translation falls back to English) plus `InfoPlist.strings` for the Bluetooth permission text. New UI text must go through `L(...)` and be added to every language file. Durations use `DateComponentsFormatter`.
- `PairingView.swift` (first run), `ContentView.swift` (battery screen + history sheet), `BudsBatteryApp.swift` (scenePhase toggles scanning).

## Constraints

- GalaxyBudsClient uses RFCOMM/SPP, which iOS does not allow third-party apps to open; ANC, wear detection and charging state are therefore out of scope (a TrollStore/private-API investigation found nothing more than a single battery percentage). Don't display state that isn't backed by real data.
- Keep iOS 17+/26+ APIs behind `#available`; deployment target is iOS 16.
- Version lives in `project.yml`; on release also update the IPA name in the workflow and CHANGELOG. CI runs on `macos-26`.
