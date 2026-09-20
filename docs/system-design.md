# System design

MXLightkeeper is a user-session backlight keeper. The app and CLI share an implementation, not a running process or authoritative runtime state. They maintain a user's backlight intent through a local receiver without measuring illumination. The system is understandable only when it keeps four facts separate: what the user requested, which device was selected, what operation completed, and what was actually observed.

The **current implementation** sections describe source at `234135a`. The **target design** is a specification for the linked [implementation plan](plans/2026-09-16-agent-operation.md), not a claim that those interfaces already exist. Reconcile this document with source when either changes.

## Product contracts

- Support macOS 15+ with SwiftPM. The app uses SwiftUI `MenuBarExtra` with `.menuBarExtraStyle(.window)`.
- A persisted user setting controls keep-alive; a fresh installation defaults to enabled. Disabling the app toggle stops refreshes; it does not send the CLI's `off` command or restore a saved hardware state.
- Both frontends share receiver matching, packet handling, and keep-alive ownership. No network service is needed.
- Limit HID matching to the catalog's vendor-specific interface. Do not turn this into keyboard-input capture.
- Receiver, keyboard, OS, and operation coverage are separate evidence dimensions. Existing alpha labels remain until the relevant hardware behavior is reproduced.

### Accepted presentation

[MenuBarContentView.swift](../Sources/MXLightkeeperApp/MenuBarContentView.swift) owns the single release panel with section dividers. The native window provides its surface; the panel adds no custom material, border, shadow, or mask. The accepted geometry is width 320, `menuInset = 0`, and `headerContentHeight = 60` before header padding. `HERO.png` in the repository root is a visual reference, not proof of every state or locale.

[AppLanguage.swift](../Sources/MXLightkeeperApp/AppLanguage.swift) resolves global `AppleLanguages` through `CFPreferencesCopyAppValue(..., kCFPreferencesAnyApplication)`, then matches a supported localization. There is no in-app language override. The catalog supports `en`, `fr`, `es`, `de`, `pt-BR`, `zh-Hans`, `hi`, and `ar`, with English fallback. Live language-change observation is not implemented; validate after relaunch.

[AppStrings.swift](../Sources/MXLightkeeperApp/AppStrings.swift) owns release UI strings and localized status projections. Keep subtitles as whole translated strings and catalog entries grouped by feature. Rows manually reorder children for RTL while their stacks use left-to-right layout; controls receive their own direction. A global layout-direction change could double-flip these rows. Status layout animates on both `displayedStatus` and `model.status`; reduced motion removes the transition. Debug-only copy is not fully localized.

## Current implementation

### Boundaries and ownership

1. **Presentation and platform integration.** [AppModel.swift](../Sources/MXLightkeeperApp/AppModel.swift) owns persisted intent, polling, keeper lifetime, and `SMAppService` calls. The views format its state. [main.swift](../Sources/mxlightkeeper/main.swift) parses commands, invokes the core, and prints results.
2. **Operations.** [MXLightkeeperController.swift](../Sources/MXLightkeeperCore/MXLightkeeperController.swift) selects a receiver, scopes probe sessions, reads details, and performs mutations. Both frontends use this controller.
3. **Lifetime and ownership.** [BacklightKeeper.swift](../Sources/MXLightkeeperCore/BacklightKeeper.swift) runs periodic refreshes and holds a per-user lock for the long-running loop.
4. **Device access.** [HIDReceiverService.swift](../Sources/MXLightkeeperCore/HIDReceiverService.swift) matches, enumerates, and writes to IOHID devices. [HIDPPProbeSession.swift](../Sources/MXLightkeeperCore/HIDPPProbeSession.swift) opens a device, registers its callback, sends requests, and correlates replies.
5. **Values and protocol.** [ReceiverCatalog.swift](../Sources/MXLightkeeperCore/ReceiverCatalog.swift), [HIDPP.swift](../Sources/MXLightkeeperCore/HIDPP.swift), [BacklightStatus.swift](../Sources/MXLightkeeperCore/BacklightStatus.swift), and [KeepAliveProtocol.swift](../Sources/MXLightkeeperCore/KeepAliveProtocol.swift) define matches, report formats, state, and pulse constants.

The dependency direction is frontend to core to IOHID. Core does not import SwiftUI or ServiceManagement. Controller, keeper, and probe session run on `@MainActor`. Probe requests synchronously pump the main run loop; the pulse delay uses `Thread.sleep`. These are relevant when diagnosing responsiveness or reentrancy.

### Startup and refresh flow

1. `AppModel.init` decodes `MXLightkeeperSettings` from the `mxlightkeeper.settings` defaults key. Defaults are enabled and no launch at login.
2. `refreshReceivers` enumerates exact matches, preferring nonexperimental receivers and then lower location IDs. The first result becomes the active receiver. `markReceiverActive` also emits `.receiverAcquired`, which the reducer maps to `.active` whenever the prior status is not disabled, before keeper startup. There is no user-selectable receiver or paired-slot discovery.
3. If enabled, `prepareRuntimeState` resolves the first match again and rejects a snapshot mismatch. `BacklightKeeper.start` acquires ownership and schedules the task; the model then sets `.active`.
4. The keeper attempts a refresh immediately, then every 180 seconds. `refreshKeepAlive` writes `offSignal`, waits 50 ms, then writes `onSignal`. Both packets use receiver slot `0x01` and feature index `0x0b`.
5. Independently, the app polls every 60 seconds, including while disabled. It re-enumerates receivers and reads keyboard name and battery. A missing receiver stops the keeper and clears device details. A newly selected receiver clears old details.

The CLI's `keep` uses the same keeper and exits cleanly on Ctrl-C. It does not run the app's receiver poll, although raw writes re-enumerate the saved snapshot and may resume after a matching reconnection. Its other commands open short-lived sessions: `read` reads structured state; `on`, `off`, and `manual` read, write, then read again. `manual` accepts levels 1 through 7. These operations currently use fixed slot `0x01` and `BACKLIGHT2` index `0x0b`. Name and battery feature indexes are dynamically resolved.

### What current feedback proves

- `isEnabled` is persisted intent. `BacklightKeeper.isRunning` means its task and ownership were established. Neither proves a successful refresh.
- `.active` can mean receiver acquisition alone; it is also assigned after keeper startup. Neither assignment waits for a refresh outcome. Refresh errors are discarded with `try?`, so later write failure does not update app status or CLI health. Successful enumeration can clear a prior error and promote degraded status independently of writes.
- `.waiting` represents enabled intent without a receiver. `.degraded` can represent enumeration or ownership/start errors, not just a missing receiver. The current localized degraded subtitle does not distinguish those causes.
- `readDeviceDetails` turns individual name/battery failures into `nil`, clearing those samples. An outer session failure retains previous details and their timestamp. Enumeration failure clears receiver fields but retains samples internally; the view hides their rows because no active match exists. `batteryLastUpdatedAt` is a sample time, not a liveness guarantee.
- A setter's returned state is a subsequent decoded response. The controller does not explicitly compare it against the requested change. `sendRequest` accepts error reports by software ID alone, and setters discard the write response. An ignored protocol error can therefore precede a normal-looking readback. Neither a response nor an accepted HID write proves visible LED behavior.
- `lastErrorMessage` exists in the model but is not rendered in the release panel. OSLog currently records selected app lifecycle events, not each keeper result.
- The lock file attempts to exclude concurrent keepers; it does not exclude one-shot CLI writes or debug pulses. There is a source-visible race: another process can delete the newly created empty file before the first process writes its PID, allowing both to acquire ownership. Cleanup is also separate from stale detection.
- Keeper lifetime requires explicit `stop`/`close`. The task captures values independently of the keeper, while ownership releases when its object is destroyed. Dropping a running keeper without stopping it risks a surviving unowned task; normal app stop/quit paths do explicitly stop it. This teardown case still needs a regression test.
- A supplied snapshot is checked against the first preferred receiver, not resolved among all matches. A still-attached target can fail when another receiver sorts first. Each pulse report instead resolves its snapshot independently, so the pair is not bound to one live attachment.
- The CLI ignores some extra arguments. Proposed flags such as receiver selection or duration must not be passed to it: they can be ignored while a real mutation or unbounded keeper starts.
- `RetryPolicy` and `Backlight2Codec.keepAliveRequest` have unit tests but no production callers. Their tests do not establish retry behavior or the shipping keep-alive mechanism.

These findings come from source inspection, not a reproduced hardware failure. `HIDPPProbeSession` starts its wall-clock response timeout after the synchronous native write; it does not bound enumeration, opening, or that write.

### Presentation limits

All 31 catalog keys referenced by current Swift literals have eight-language entries. The remaining 11 keys are unreferenced fragments, including old language-picker text. Their presence does not imply a language override. Two Chinese accessibility formats (`battery.accessibility.charging` and `battery.accessibility.percent`) have an unescaped ASCII percent after `%lld`; [Apple's format contract](https://developer.apple.com/library/archive/documentation/Cocoa/Conceptual/Strings/Articles/formatSpecifiers.html) requires `%%` for a literal percent. Actual formatting symptoms have not been exercised.

The release active subtitle says “Will keep backlight on.” Unused English presentation properties in `AppStatus` are not the release copy. However, the menu-bar accessibility label describes disabled keeping as “backlight off,” and the degraded subtitle describes ownership failures as missing receivers. Both conflate distinct facts.

Two source paths need focused runtime verification: `alphaSuffix` bypasses the explicit global-language resolver, and `updateDisplayedStatus` ignores sleep cancellation before assigning its captured status. Mixed-language suffixes or stale/hidden text after rapid transitions are risks, not observed rendered failures. Debug Pulse/Demo controls also lack the Probe button's disabling modifier, and the model has no concurrent-sequence admission guard.

### Persistence and packaging

Settings persist only `isEnabled` and `launchAtLogin`. The latter reflects the stored setting and successful registration calls, not a startup reconciliation with System Settings. Runtime receiver snapshots and device details are in memory. The ownership file normally lives at `~/Library/Application Support/MXLightkeeper/keepalive.lock`.

`MXLightkeeperSettings` uses synthesized decoding of two required Booleans. `loadSettings` treats unreadable existing data like first installation and returns enabled defaults. A partial record containing valid disabled intent but missing another field can therefore fall back to enabled. This is a source-derived recovery-policy issue, not evidence that healthy stored settings spontaneously corrupt.

[Package.swift](../Package.swift) defines the core, two executables, and two test targets without external package dependencies. [build-app-bundle.sh](../scripts/build-app-bundle.sh) builds a universal release executable, replaces `dist/MXLightkeeper.app`, copies the SwiftPM resource bundle if present, and ad-hoc signs it. Resource copying is currently conditional. [CI](../.github/workflows/ci.yml) builds and tests, but does not package or validate hardware.

## Target design: one observable control loop

The design goal is to let a person or agent answer, from one operation result: **Which target? Which intent? Which effect? What evidence? What next?** The core owns those answers. Frontends format them rather than reconstructing them from timers, logs, or localized text.

### Linked abstractions

1. **Intent:** enable periodic refresh, stop refreshing, or perform a one-shot read/set. Keep the distinction between stopping a keeper and turning the light off.
2. **Target and capabilities:** resolve an exact receiver address and slot, then resolve the requested feature. A detectable missing or changed target is an outcome, never permission to silently switch devices during an operation. An address is not permanent physical identity.
3. **Operation:** acquire ownership, execute a complete transaction, and return a typed result. One shared transaction gate serializes same-process operations; cross-process ownership coordinates compatible processes belonging to the same user. Publish timing guarantees only after establishing native-I/O bounds.
4. **Observation:** retain the result's target, time, stage, error, and evidence level. Keep attempted, transmitted, and read-back-confirmed effects distinct. Physical illumination remains a hardware observation.
5. **Projection:** app state, human CLI output, JSON, and logs derive from those values. User-facing text is localized at the frontend boundary; machine identifiers stay stable.
6. **Verification:** simulated transactions prove control logic, bundle checks prove artifact contents, and hardware exercises prove physical behavior. Each claim names the layer it was checked at.

These are responsibilities within the existing targets, not six new packages. Add an interface only where it enables a concrete test or isolates a platform effect.

### Runtime contract

A runtime snapshot separates desired mode, selected target, ownership, last refresh attempt, last successful transmission, latest device samples, and failure reason. Unknown and stale values remain explicit. Use a monotonic clock for scheduling/deadlines and wall time for human-readable timestamps.

Keeper startup first establishes ownership, then reports the first refresh result. A failed cycle records the failed stage, including a partial pulse where the first report succeeded and the second failed. Poll success cannot erase a write failure; only a successful refresh establishes recovery. Tag results with the keeper/target generation so late completion cannot reactivate a stopped or retargeted keeper.

The transaction gate covers both pulse reports and their gap, or the complete structured read–modify–write–read operation. Its lifetime is shared across controller instances and includes polling and debug actions. Reuse the existing enumeration/writing protocols and refresh-operation seam. A new actor or separate gate per controller does not by itself establish transaction exclusion.

Disabling or quitting stops admission of new work and retains ownership until admitted effects finish. Cancellation before the first report prevents a pulse. After its first accepted report, normal cancellation requests completion of the second attempt against the same live target, recording partial transmission if it fails. This is completion, not rollback. Establish that lifetime contract before replacing the synchronous gap with cancellable sleep; keep app termination behind cleanup.

Start with the existing cadence and pulse behavior. A monotonic budget can bound response waits and admission, but a timer or cancelled Swift task cannot establish a hard bound on synchronous native calls. Investigate native timeout/callback behavior and resource lifetime before exposing whole-command or shutdown deadlines. Never release ownership while an in-flight write may continue. A timed-out mutation may have taken effect; report uncertainty rather than replaying it.

### Agent control contract

Use the existing CLI as the local automation boundary. Planned inventory and diagnosis commands report receiver candidates, capability results, and evidence without changing backlight settings or starting a keeper. HID queries still send output reports; “read-only” describes device-state intent, not absence of USB traffic.

Machine output is opt-in, versioned JSON with stable error codes and explicit scope. Each result contains a schema version, command, target, outcome, observations, and errors. Separate stdout data from stderr diagnostics. Unknown options and conflicting flags fail before hardware access. Help, parsing tests, and schema fixtures use no hardware.

Targeted commands accept the receiver ID returned by inventory. Without an ID, require exactly one candidate. Reject duplicate or insufficient address information and detectable target changes. Pin a live target for the whole operation, but do not claim to detect an indistinguishable replacement or a changed keyboard pairing without additional identity evidence. Keep slot 1 as the explicit supported scope until other slots are verified. Resolve structured `BACKLIGHT2` indexes dynamically after fixing protocol-error handling. Preserve existing alpha paths; any new raw-pulse capability restriction requires an explicit support decision rather than silently narrowing the product.

All device transactions in compatible versions use the same ownership boundary. Another compatible process's keeper yields `busy`; same-owner polling and refreshes serialize within that boundary. Inventory may still enumerate without acquiring control. Diagnosis reports skipped busy probes explicitly. Advisory ownership does not exclude unrelated software or other users. Mixed sentinel/advisory versions are unsupported unless a tested compatibility requirement is added; stopping old owners once is not a guarantee against later old-process launches.

A proposed `keep --duration <seconds>` supports automation only after transaction lifetime and cleanup limits are established. Define its duration as the scheduling window and document any validated cleanup allowance separately. Existing unbounded `keep` remains available to a person using Ctrl-C. Grow diagnosis from actual missing observations rather than building a comprehensive report first.

CLI diagnosis describes that invocation and detectable ownership, not the running app's in-memory state. Add app IPC only if a required workflow needs that keeper's health, persistent-intent changes, or coordinated pause–mutation–resume. Such a contract should reuse established results and expose app operations, not arbitrary HID access. Launch-at-login reconciliation remains an app/platform concern, not part of the HID runtime model.

### Low-cost verification and accumulated knowledge

Tests inject receiver enumeration, request/response transport, time, and ownership at their owning boundaries. Use scripted replies and failures, not real hardware or 180-second sleeps. A UI fixture uses these seams to exercise disabled, waiting, active, degraded, stale battery, and RTL states without touching preferences or a keyboard.

Verification accompanies each change. Keep a small build/test entrypoint; add catalog and local-link checks where they prevent demonstrated drift. Resource presence can be enforced independently of runtime changes. The release gate also verifies both architectures, signing, metadata, and compiled localization resources. Hardware checks remain explicit and scoped to a named device/OS/operation.

Knowledge belongs beside the contract it strengthens: a regression fixture for a failure, this document for system behavior, the development guide for a procedure, or the protocol notes for measured hardware evidence. Replace stale assertions instead of appending contradictory notes. Plans stop owning a contract once it is implemented; source, tests, and current docs become authoritative.

### Tradeoffs and evidence gaps

**Decision:** strengthen the existing core and CLI before adding a daemon, remote API, MCP server, or persistent event database. Confidence is high that current silent failures and documentation drift justify this order. More adapters would currently expose the same uncertainty through more interfaces.

The weakest assumption is that the legacy pulse should remain the keeper strategy. Commit `9bb0855` restored it because structured writes did not visibly wake LEDs, but its verification note stops short of a fresh hardware result. Older notes describe structured writes as visibly successful. Preserve both observations with their scope, retain shipping behavior, and resolve the conflict through the [hardware procedure](development.md#hardware-evidence).

The main design risk is turning a small utility into a framework. A new type must remove duplicated reasoning or enable a named test. Reject abstractions that do neither. Start with strict parsing and truthful outcomes; establish transaction lifetime before advertising stronger machine-control guarantees. Deterministic ordering tests and native-I/O evidence must precede new cancellation/deadline promises or moving IOHID work between executors.
