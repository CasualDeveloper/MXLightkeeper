# Plan: observable, agent-operable MXLightkeeper

**Status:** proposed implementation. This task changes documentation and makes the agent entrypoint trackable. The interfaces and checks below must not be advertised as shipped until implemented and verified.

**Baseline:** `234135a` on `main`. At inspection, tracked files were clean; `tmp/` was untracked and outside this work. A machine-local `.memory-bank` link was unavailable and is not needed to execute this plan. Recheck `git status --short --branch` and the relevant source before each slice; preserve unrelated work.

**Design owner:** [system design](../system-design.md#target-design-one-observable-control-loop). That document owns the abstractions and their rationale. This plan owns dependency order, implementation locations, and acceptance evidence. [Development](../development.md) owns current commands.

## Completion criteria

A fresh agent can locate a behavior's owner without surveying the whole repository, inspect receiver candidates without starting control, select an unambiguous address, and distinguish intent from transmission, readback, and physical observations. Machine results describe their actual timing and identity limits. A future agent can reproduce software failures from deterministic tests rather than rediscovering the hardware protocol.

The accepted native panel, language/RTL behavior, macOS 15 floor, and alpha boundaries remain intact. There is one core implementation behind both frontends. No daemon, remote endpoint, new package hierarchy, app-control IPC, persistent event database, or protocol-strategy change is needed for this plan.

## Evidence driving the order

- `MXLightkeeperController.refreshKeepAlive` uses raw pulses. Commit `9bb0855` deliberately restored them; tests of `Backlight2Codec.keepAliveRequest` cover a different path.
- The keeper now records complete and partial pulse results, and `.active` requires both reports to return transport success. App-model lifecycle and rendered-state integration still need broader fixture coverage.
- Target selection is implicit; `Backlight2Codec` fixes the feature index to `0x0b`. Only device-name and battery features use root discovery.
- The ownership guard covers keepers but not one-shot mutations. Creation followed by PID writing races with empty-file cleanup, allowing concurrent owners. Keeper teardown also needs explicit lifetime coverage.
- CLI output is text-only. Its strict parser now rejects unknown or surplus arguments before constructing the controller; proposed machine-control flags remain unavailable.
- Language unit tests cover selection and source-catalog placeholders, not every packaged lookup. Packaging now requires the compiled resource bundle, but CI does not run the bundle lane.
- Settings recovery, Chinese percent placeholders, alpha-suffix lookup, status cancellation, and debug overlap now fail safely in source. Packaged conflicting-language and rendered rapid-transition checks remain outstanding.

Implement in the order below, in independently verified increments. Keep the app and existing valid human CLI invocations usable. Tests and documentation accompany each increment; they are not a final phase. Promote implemented contracts into current documentation and remove superseded proposal text as slices land.

## 1. Make the current system safe to interpret

**Owners:** `Sources/mxlightkeeper/main.swift`; `BacklightKeeper.swift`, `MXLightkeeperController.swift`, `HIDPPProbeSession.swift`, `BacklightStatus.swift`, and `AppState.swift` in core; `AppModel.swift`, `AppStrings.swift`, `MenuBarContentView.swift`, and `Resources/Localizable.xcstrings` in the app; corresponding tests.

1. Correlate HID++ errors to the request and propagate them as failures. Validate setter readback against the requested enabled/mode/level semantics, not unrelated fields. Add fixtures for unrelated and late replies as well as explicit errors.
2. Preserve refresh failure causes through successful metadata polling and keep sample freshness/target association explicit. Keep login-service errors separate from keeper health.
3. Reconcile launch-at-login presentation with service status through a narrow app adapter without automatically undoing a user's external disablement.
4. Remove unreferenced catalog fragments only after checking their consumers. Preserve whole-string localization and the accepted layout.
5. Verify rapid subtitle transitions under Reduce Motion changes and view dismissal. Verify global-language selection against conflicting app preferences in the packaged app. Shared production/debug transaction ownership follows in slice 2.

**Acceptance:** preserve regressions for invalid CLI input, complete/partial pulse results, and active-only-after-success reducer behavior. Add recovery, metadata success after write failure, protocol rejection, and mismatched readback coverage. Advance virtual time for cadence checks. App-model fixtures use isolated defaults and injected platform effects so initialization cannot probe hardware or register login items.

Also cover absent/valid/partial/wrong-type/malformed settings; fake login-service states; probe failure versus unchanged successful samples; and receiver replacement. Format compiled strings at 0 and 100 in all supported locales and with conflicting app/global language preferences. After rapid active–disabled–active transitions, text must settle to current status and remain visible. Two concurrent debug requests admit only one sequence. Check invalid battery values without clamping them into plausible telemetry.

**Preserve:** the current pulse bytes, synchronous 50 ms gap, 180-second cadence, and distinction between disabling refresh and writing `off`. Keep the main-run-loop adapter. Async mid-pulse cancellation and stronger ownership guarantees belong together in slice 2. Qualify source comments about physical wake behavior and MX Keys S support using the scoped hardware notes; comments must not claim stronger evidence than the docs.

This slice is a useful narrow release on its own. It improves truthful feedback without claiming robust cross-process automated control.

## 2. Establish one transaction and lifetime contract

**Depends on:** slice 1's outcome and transport tests. A small native-I/O feasibility investigation precedes deadline or cancellation guarantees.

**Owners:** `ReceiverCatalog.swift`, `HIDReceiverService.swift`, `HIDPPProbeSession.swift`, `HIDPP.swift`, `BacklightStatus.swift`, `MXLightkeeperController.swift`, and `BacklightKeeper.swift` in core; targeting/transport/ownership tests.

1. Establish which native enumeration/open/write/response operations can actually be bounded, and how callbacks, buffers, handles, and ownership remain alive until work finishes. A timer around synchronous IOHID is not a hard timeout. Record the supported timing contract before changing scheduling.
2. Resolve a supplied receiver among all matches rather than comparing it with the globally preferred one. Define an opaque address ID using catalog identity/location and explicit slot 1. Reject ambiguous or insufficient address data. Bind the whole operation to one live target and invalidate capabilities on detected disconnect.
3. Resolve structured `BACKLIGHT2` through root discovery and pass its index into the codec. Keep the raw strategy's fixed slot/index explicit. Preserve currently enabled alpha paths; new capability restrictions require a support decision. Do not add an unverified structured fallback.
4. Add one shared transaction gate across controller instances, covering complete read–modify–write–read operations and both pulse reports plus their gap. Include polling and debug actions. This is a narrow coordinator, not a new executor framework or package hierarchy.
5. Replace sentinel-file ownership with a held OS advisory lock for compatible versions, retaining the descriptor and persistent inode. Keep one per-user owner initially. A keeper owns it for its lifetime; one-shot transactions acquire it for their duration; same-owner polling reuses the lease and transaction gate.
6. Retain ownership until admitted effects finish. Cancellation before a pulse prevents it; after the first accepted report, attempt the second against the same live target before release. Define stop/quit cleanup and owner-loss teardown together. Tag results by keeper/target generation to reject late health updates after disable or retargeting.

**Acceptance:** tests cover a requested receiver that no longer sorts first, duplicate/zero addresses, detectable reconnects, non-`0x0b` structured features, unsupported capabilities, and late replies. Competing-process tests cover normal exit, termination, legacy empty/stale files, and both launch directions of old/new versions. Lifetime tests cover stopping before/between/after reports, dropped keepers, same-process transaction exclusion, and late results. A fake clock proves scheduling logic; native integration evidence is required for any advertised wall-clock bound. Recheck hardware behavior when device/session lifetime changes.

**Version policy:** mixed sentinel/advisory operation is unsupported. App and CLI must use compatible ownership versions, including processes launched after an upgrade. Stop old owners and establish that legacy locks are stale before transition; never silently delete a potentially live lock. New locking cannot make an old one-shot CLI cooperate because it never checks a lock. If mixed versions must coexist, pause for a deliberate compatibility design and tests. Advisory ownership covers cooperating same-user processes, not arbitrary software or other users.

**Identity limit:** a replacement receiver at the same address or a changed keyboard pairing may be indistinguishable. Promise rejection of detectable target changes, not permanent physical identity. Stronger guarantees need an attachment-generation or device-identity mechanism and evidence.

## 3. Publish machine control over established guarantees

**Depends on:** reliable outcomes for JSON and slice 2 for stronger mutation/lifetime guarantees. Inventory can ship independently once strict parsing and address semantics are established.

**Owners:** `Sources/mxlightkeeper/main.swift`, testable parsing/formatting code within that frontend, shared core outcome types, CLI tests, and the CLI section of `README.md`.

Implement these proposed surfaces:

- `receivers --json`: enumerate candidates and their opaque IDs without starting a keeper or probing backlight state. An empty list is a successful inventory result.
- `diagnose --receiver <id> --json`: incrementally add useful capability/state probes. Define required versus optional observations and report busy/skipped probes explicitly. Its scope is this invocation, not the running app's private state.
- Existing `read`, `on`, `off`, `manual`, and `keep`: accept `--receiver <id>` and `--json`. With no target, require exactly one candidate. Preserve existing simple invocations when that condition holds.
- `keep --duration <seconds>`: expose only after lifecycle guarantees are verified. A positive finite duration is the monotonic scheduling window; document the separately validated cleanup allowance and stop admitting new pulses at expiry. Ctrl-C remains available for unbounded human use. JSON `keep` requires a duration and emits one final result.
- `--timeout <seconds>`: defer publication until the native feasibility result establishes the exact bound. Distinguish response wait, whole transaction, and cleanup time. Never return and release ownership while a native mutation continues. Validate a positive finite value before access and test the documented default against the supported operation sequence.

Extend slice 1's strict parser as each surface ships; proposed flags remain rejected until implemented. Keep human output the default and avoid prompts in automation.

Freeze schema version 1 with fixtures before publishing it. Its JSON object contains `schemaVersion`, `command`, `scope`, nullable `target`, `outcome`, `observations`, and `errors`. Observations include their evidence level and time; absent, unsupported, stale, and failed values are distinguishable. Error entries have a stable code, failed stage, and human message. Initial codes cover `invalid_argument`, `receiver_missing`, `ambiguous_target`, `target_changed`, `busy`, `unsupported_feature`, `unsupported_strategy`, `timeout`, `transport_error`, `protocol_error`, and `readback_mismatch`. Native IOHID codes may be optional detail, not the portable error contract. Do not serialize local lock paths or host user identity.

Use stable outcome values `success`, `partial`, and `failure`. Use exit 0 for a complete requested result, 2 for invalid invocation, and 1 for operational failure or partial completion; scripts inspect error codes for detail. A diagnosis that conclusively finds an unsupported optional feature is complete; a busy or timed-out required probe is incomplete. Emit a JSON error object on stdout whenever `--json` is recognized, including validation failures, with diagnostics only on stderr. `--help` is the explicit text-output exception. `keep` fails if any refresh failed, even if a later cycle recovered; report both the failure count and latest result. A deadline reached after all successful cycles is normal bounded completion. Handle SIGINT/SIGTERM with bounded cleanup and conventional interrupted exit status.

**Acceptance:** parser and subprocess tests prove stdout is one valid object, stderr cannot corrupt it, exit statuses agree with outcomes, and invalid input never invokes transport. Scripted receiver loss, busy ownership, partial pulse, and verified duration expiry produce stable results. Human `--help` and existing valid command examples remain understandable. CLI diagnosis never presents stored defaults or a PID file as the running app's current health.

## Verification and knowledge accompany every slice

Packaging and catalog checks are independent improvements, not prerequisites for or successors to the entire runtime plan. Fixtures grow with the boundaries they exercise.

**Owners:** `Tests/MXLightkeeperAppTests`, core and CLI tests, `scripts/build-app-bundle.sh`, `.github/workflows/ci.yml`, and new repo-local verification scripts. Keep procedures in [development](../development.md).

1. Keep a small `scripts/check.sh` entrypoint for hardware-free build/tests. Add useful catalog and local-link checks without creating a checker framework. Check used-key coverage, argument types/positions, and escaped literal percent signs; allow legitimate positional reordering and keep intentional untranslated names explicit. Avoid snapshots that merely copy source literals.
2. Add a bundle-check mode verifying both architectures, metadata, ad-hoc signature, and compiled localizations. Keep the fast lane separate from the universal build.
3. Build a fixture-driven app presentation path using slice 1's injected dependencies. Exercise long text, Arabic RTL, stale telemetry, ownership conflict, and different failure causes while status remains degraded, as well as transitions in both directions. Avoid hardware, global-preference writes, and login-item registration. Retain a separate real system-language/relaunch check.
4. Route CI through the same verification entrypoint. Use the bundle lane when packaging/resources change and before distribution. Keep live hardware validation outside generic CI.
5. Add a deterministic regression for each fixed control failure and update the owning current docs. Test production paths: awaited pulse results, reducer event sequences, actual string formatting, and independently mismatched receiver fields. Retire unused helpers only after checking public-core consumers. Keep measured hardware observations in the protocol notes, without a parallel task database or transcript collection.

**Acceptance:** one fast command produces a clear failing boundary without hardware. Removing a compiled localization makes the bundle lane fail. Simulated controller/CLI scenarios distinguish success from failure without sleeping. Rendered inspection verifies the accepted panel and RTL behavior; test assertions alone do not establish visual correctness.

## Evidence and completion discipline

For each implemented slice, run its focused tests, then `swift build` and `swift test` until the new shared gate replaces those commands. Run packaging and rendered checks for changes affecting the app artifact or presentation. Record actual commands and decisive results with the change; do not claim a proposed scenario passed.

No Swift build, test, hardware operation, or new CLI interface is executed or implemented by this documentation revision. Its verification is source/history cross-checking and local-document validation. Existing CI and packaging commands were inspected.

After substantial routing changes, use a fresh-context agent exercise: locate the keeper strategy, explain what `.active` proves, choose a hardware-free check for an Arabic string change, then use any implemented inventory/diagnosis flow against a fixture. Record wrong assumptions and unnecessary retrievals. Retain guidance that prevented a real error; trim guidance that added cost without helping. This is not a ritual for every patch, and link checks alone do not establish successful agent use.

Pause for a specific decision if a required device/slot is unavailable, hardware evidence would be needed to change the pulse strategy, identity is ambiguous, or requested scope expands into app IPC. An ordinary failing test calls for diagnosis. Nothing in this plan authorizes silently weakening an assertion, alpha boundary, or result contract to make verification pass.
