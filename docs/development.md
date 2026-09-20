# Development and diagnosis

Start from the [system design](system-design.md) for behavior and state semantics. This guide contains **commands available today**. Proposed CLI commands and verification scripts belong to the [implementation plan](plans/2026-09-16-agent-operation.md).

## Orient without touching hardware

Run from the repository root:

```bash
git status --short --branch
git log -5 --oneline
swift --version
```

Read only the owner for the task:

- Keeper behavior or status: `BacklightKeeper.swift`, `MXLightkeeperController.swift`, `AppModel.swift`, then `BacklightKeeperTests.swift` and `AppStateTests.swift`.
- Targeting or packets: `ReceiverCatalog.swift`, `HIDReceiverService.swift`, `HIDPPProbeSession.swift`, `HIDPP.swift`, `BacklightStatus.swift`, then the protocol notes.
- UI or language: `MenuBarContentView.swift`, `AppLanguage.swift`, `AppStrings.swift`, `Resources/Localizable.xcstrings`, and `AppLanguageTests.swift`.
- CLI: `Sources/mxlightkeeper/main.swift` and the controller operation it calls.
- Artifact or deployment: `Package.swift`, `scripts/build-app-bundle.sh`, `Packaging/Info.plist`, and `.github/workflows/ci.yml`.

Paths without a prefix above are within their corresponding `Sources/MXLightkeeperCore`, `Sources/MXLightkeeperApp`, or `Tests` target. Search symbols rather than loading `.build`, `dist`, or temporary captures. Machine-local memory links are not required project context.

## Verification

### Source changes

The current CI gates are:

```bash
swift build
swift test
```

They run on `macos-15` with Xcode 16.4 and on `macos-latest` with its selected Xcode. They establish compilation and unit-test behavior, not hardware support. Use a focused test during iteration, then the full gates for the final source state. For example:

```bash
swift test --filter rtlLayoutFollowsSystemLanguage
```

Existing tests cover reducer cases, receiver matching, retry-delay calculation, structured codec payloads, keeper exclusion/release, early manual-level validation, and language resolution. There is currently no simulated controller transaction suite, app-model lifecycle suite, CLI contract suite, or automated visual test. The codec keep-alive tests exercise an unused helper, not the runtime pulse sequence.

Read assertions as well as test names: the matcher test does not independently vary vendor/page/usage, keeper tests do not await refresh results, and app tests do not call `AppStrings` formatting functions. See the system design's [presentation limits](system-design.md#presentation-limits) for the concrete catalog and transition cases needing coverage.

### CLI parsing and help

```bash
swift run mxlightkeeper --help
```

Help exits before constructing the controller. Current CLI output is human-readable; there is no `--json`, `diagnose`, receiver-selection flag, or duration limit. Do not pass proposed flags to the shipping CLI: its parser does not consistently reject extra arguments.

### Bundle and UI changes

The packaging script replaces only the generated `dist/MXLightkeeper.app`, builds both architectures, and ad-hoc signs the result:

```bash
./scripts/build-app-bundle.sh
codesign --verify --deep --strict dist/MXLightkeeper.app
lipo -archs dist/MXLightkeeper.app/Contents/MacOS/MXLightkeeperApp
plutil -lint dist/MXLightkeeper.app/Contents/Info.plist
```

Expect `arm64` and `x86_64`. Inspect `dist/MXLightkeeper.app/Contents/Resources/MXLightkeeper_MXLightkeeperApp.bundle` for the compiled localizations. The current script can succeed when the resource bundle is absent; signing alone does not verify localization contents.

Launching the packaged app loads persisted intent and can start keep-alive immediately. With an appropriate hardware/UI test session, check:

- Enabled and disabled states, no receiver, and reconnect after unplug/replug.
- English, a long translation such as German, and Arabic using real system language followed by app relaunch. Restore the tester's prior system setting afterward. Per-app `AppleLanguages` launch arguments are not an end-to-end test of global-language selection.
- Header growth and shrink, native panel surface, RTL icon/text order, control direction, keyboard access, VoiceOver labels, and Reduce Motion.
- Release layout, which excludes the debug section. Use `HERO.png` as the accepted composition reference.

Pure language helpers already accept injected preferences. A proposed UI fixture will avoid changing system settings for most visual checks; it does not exist yet.

### Documentation-only changes

Check relative links, referenced symbols, command spelling against source/help, and the diff for unsupported claims. A docs-only change does not require rebuilding the app. Label checks as executed, inspected, or unavailable; do not repeat earlier handoff verification as if it were fresh.

## Diagnose the current system

**“On” but no visible light:** confirm enabled intent separately from light. Enumeration alone can set `.active`, and the keeper discards refresh errors. Review the reducer and `refreshKeepAlive`, check the exact receiver, and gather hardware observations; `.active` cannot settle this question.

**No receiver or unexpected receiver:** matching requires vendor ID, product ID, usage page, and usage. Current selection prefers Unifying over experimental Bolt and then lower location ID. A second receiver or a keyboard paired outside slot 1 needs explicit investigation. There is no shipping CLI selector.

**Another keeper already running:** disable keep-alive in the owning app or stop the owning CLI normally before retrying. The lock file's presence is not sufficient proof of a live owner; inspect its PID if needed. Do not delete a live owner's lock to make a second keeper start. Current one-shot commands bypass this guard and can conflict with a running keeper.

**Battery absent or stale:** a missing value may mean unsupported feature or a swallowed probe error. An outer failure can leave the previous value. Check the sample timestamp and app logs; missing telemetry is not zero battery.

**Wrong language or missing strings:** inspect global preference resolution, supported localization matching, and the packaged resource bundle in that order. A catalog entry in source does not prove it reached the `.app`.

**Launch at login disagrees with the checkbox:** compare System Settings with the stored preference and registration errors. Startup currently does not reconcile `SMAppService` status. Launch-at-login testing requires the packaged app.

For recent app logs:

```bash
/usr/bin/log show --last 5m --style compact --predicate 'subsystem == "MXLightkeeper"'
```

These logs cover app-model events, not all HID writes. Collect the narrow interval needed for the issue rather than a full host log.

## Hardware evidence

Tests and transport acknowledgments cannot establish visible backlight behavior. For a hardware validation, record the revision, app/CLI operation, OS version, receiver IDs, keyboard model, paired slot if known, power state, and initial light state. Distinguish a directly observed value from an inferred one.

1. Identify the exact receiver and stop any existing keeper before a one-shot mutation experiment. Record original backlight settings if restoration is needed.
2. Exercise one operation. For keep-alive, start with visibly timed-out LEDs and observe both wake behavior and sustained illumination across at least two 180-second refresh intervals. State the actual elapsed duration; this does not prove indefinite behavior.
3. Exercise stop and unplug/replug separately. The app polls for reconnect; CLI `keep` does not provide that same recovery path. Confirm ownership can be acquired after normal stop.
4. Restore deliberately changed settings and retain a compact result in [reverse-engineering notes](reverse-engineering.md). Include failures and inconclusive results. Promote only the tested support claim.

For a protocol claim, preserve a minimal request/reply fixture and its interpretation. For a visual claim, preserve the observation conditions. Raw dumps, personal host paths, and a passing build are not substitutes for this evidence.

## Keep knowledge useful

Update the owning test and current documentation in the same behavior change. When an experiment contradicts old notes, mark the old claim's scope and explain the new evidence. Remove obsolete operating instructions rather than asking the next agent to reconcile them. The plan owns sequencing only; source/tests own implemented behavior, this guide owns procedures, and Git owns completed-work history.
