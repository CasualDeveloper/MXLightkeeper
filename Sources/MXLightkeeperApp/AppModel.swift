import AppKit
import Foundation
import MXLightkeeperCore
import Observation
import OSLog
import ServiceManagement

@MainActor
@Observable
final class AppModel {
  private struct DebugSequenceStep: Sendable {
    let payload: Data
    let delayAfterMilliseconds: UInt64
  }

  private enum DefaultsKey {
    static let settings = "mxlightkeeper.settings"
  }

  private static let verifiedKeyboards: Set<String> = ["MX Keys for Mac"]

  private let userDefaults: UserDefaults
  private let controller: MXLightkeeperController
  private let logger = Logger(subsystem: "MXLightkeeper", category: "AppModel")
  private let settingsEncoder = JSONEncoder()
  private var backlightKeeper: BacklightKeeper?
  private var devicePollTask: Task<Void, Never>?
  private static let devicePollIntervalNanoseconds: UInt64 = 60 * 1_000_000_000

  private(set) var isEnabled: Bool
  private(set) var launchAtLogin: Bool

  var status: AppStatus
  var activeReceiver: ReceiverSnapshot?
  var activeMatch: HIDReceiverMatch?
  var availableReceivers: [HIDReceiverMatch] = []
  var lastErrorMessage: String?
  var keyboardName: String?
  var batteryStatus: BatteryStatus?
  var batteryLastUpdatedAt: Date?
  var isRunningDebugAction = false
  var retryAttempt = 0

  init(
    userDefaults: UserDefaults = .standard,
    controller: MXLightkeeperController = MXLightkeeperController()
  ) {
    self.userDefaults = userDefaults
    self.controller = controller

    let settings = Self.loadSettings(from: userDefaults)
    isEnabled = settings.isEnabled
    launchAtLogin = settings.launchAtLogin
    status = settings.isEnabled ? .waiting : .disabled

    refreshReceivers()
    if activeMatch != nil {
      refreshDeviceDetails()
    }
    startDevicePolling()
  }

  private func startDevicePolling() {
    devicePollTask?.cancel()
    devicePollTask = Task { @MainActor [weak self] in
      while !Task.isCancelled {
        do {
          try await Task.sleep(nanoseconds: Self.devicePollIntervalNanoseconds)
        } catch {
          break
        }

        if let self {
          self.refreshReceivers()
          if self.activeMatch != nil {
            self.refreshDeviceDetails()
          }
        }
      }
    }
  }

  var settingsSnapshot: MXLightkeeperSettings {
    MXLightkeeperSettings(
      isEnabled: isEnabled,
      launchAtLogin: launchAtLogin
    )
  }

  var keyboardLabel: String? {
    guard let keyboardName, !keyboardName.isEmpty else {
      return nil
    }
    return isKeyboardAlpha(keyboardName) ? "\(keyboardName) (alpha)" : keyboardName
  }

  private func isKeyboardAlpha(_ name: String) -> Bool {
    // Only "MX Keys for Mac" has been verified end-to-end on real hardware.
    // Everything else — MX Keys S, MX Keys Mini, original MX Keys, etc. —
    // runs against an unverified code path even though the HID++ BACKLIGHT2
    // protocol family should cover them. Flag them as alpha until confirmed.
    !Self.verifiedKeyboards.contains(name)
  }

  var receiverLabel: String {
    guard let activeMatch else {
      return "No receiver connected"
    }

    let suffix = activeMatch.matcher.experimental ? " (alpha)" : ""
    return "\(activeMatch.matcher.kind.displayName) receiver\(suffix)"
  }

  var batteryLabel: String? {
    guard let batteryStatus else {
      return nil
    }

    switch batteryStatus.powerStatus {
    case .chargingComplete:
      return "Charged"
    case .recharging, .almostFull, .wiredCharging:
      return "\(batteryStatus.dischargeLevel)% · Charging"
    case .discharging:
      return "\(batteryStatus.dischargeLevel)%"
    case .critical:
      return "Critical"
    case .invalidBattery, .thermalError, .unknown:
      return nil
    }
  }

  var batteryAccessibilityLabel: String? {
    guard let batteryStatus else {
      return nil
    }

    switch batteryStatus.powerStatus {
    case .chargingComplete:
      return "Charged"
    case .recharging, .almostFull, .wiredCharging:
      return "\(batteryStatus.dischargeLevel) percent, charging"
    case .discharging:
      return "\(batteryStatus.dischargeLevel) percent"
    case .critical:
      return "Critical"
    case .invalidBattery, .thermalError, .unknown:
      return nil
    }
  }

  var receiverSummary: String {
    guard let activeReceiver else {
      return "—"
    }

    return "\(activeReceiver.productName) • \(activeReceiver.shortIdentifier) • loc \(activeReceiver.locationIdentifier)"
  }

  var reportSummary: String {
    guard let activeReceiver else {
      return "—"
    }

    return "in \(activeReceiver.maxInputReportSize) • out \(activeReceiver.maxOutputReportSize) • feat \(activeReceiver.maxFeatureReportSize) • desc \(activeReceiver.reportDescriptorLength)B"
  }

  var matcherSummary: String {
    ReceiverCatalog.allMatchers
      .map { matcher in
        let suffix = matcher.experimental ? " (alpha)" : ""
        return "\(matcher.kind.displayName)\(suffix)"
      }
      .joined(separator: ", ")
  }

  var runModeSummary: String {
    backlightKeeper?.isRunning == true ? "Keeping backlight on" : "Idle"
  }

  var canRunDebugAction: Bool {
    activeReceiver != nil && !isRunningDebugAction
  }

  func setEnabled(_ enabled: Bool) {
    isEnabled = enabled
    status = AppStatusReducer.reduce(from: status, event: .setEnabled(enabled))

    persistSettings()
    logger.info("Enabled changed to \(enabled, privacy: .public)")

    if enabled {
      refreshReceivers()
    } else {
      stopKeeperIfNeeded()
      lastErrorMessage = nil
      retryAttempt = 0
    }
  }

  func setLaunchAtLogin(_ enabled: Bool) {
    do {
      if enabled {
        try SMAppService.mainApp.register()
      } else {
        try SMAppService.mainApp.unregister()
      }

      launchAtLogin = enabled
      persistSettings()
      logger.info("Launch at login changed to \(enabled, privacy: .public)")
      lastErrorMessage = nil
    } catch {
      lastErrorMessage = error.localizedDescription
      logger.error("Failed to update launch at login: \(error.localizedDescription, privacy: .public)")
    }
  }

  func refreshReceivers() {
    do {
      availableReceivers = try controller.listReceivers()
      if let firstMatch = availableReceivers.first {
        markReceiverActive(firstMatch)
        if isEnabled {
          startKeeperIfPossible()
        }
      } else {
        markReceiverMissing()
      }
    } catch {
      stopKeeperIfNeeded()
      availableReceivers = []
      activeReceiver = nil
      activeMatch = nil
      lastErrorMessage = error.localizedDescription
      status = isEnabled ? .degraded : .disabled
      logger.error("Receiver refresh failed: \(error.localizedDescription, privacy: .public)")
    }
  }

  private func startKeeperIfPossible() {
    guard isEnabled else {
      return
    }

    guard let activeReceiver else {
      return
    }

    if backlightKeeper?.receiverSnapshot != activeReceiver {
      stopKeeperIfNeeded()
    }

    if backlightKeeper?.isRunning == true {
      return
    }

    do {
      let runtimeState = try controller.prepareRuntimeState(matching: activeReceiver)
      try runtimeState.keeper.start()
      backlightKeeper = runtimeState.keeper
      status = .active
      lastErrorMessage = nil
      logger.info("Backlight keeper started")
    } catch {
      backlightKeeper = nil
      markDegraded(error.localizedDescription)
      logger.error("Failed to start backlight keeper: \(error.localizedDescription, privacy: .public)")
    }
  }

  private func stopKeeperIfNeeded() {
    guard let backlightKeeper else {
      return
    }

    backlightKeeper.stop()
    logger.info("Backlight keeper stopped")
    self.backlightKeeper = nil
  }

  #if DEBUG
  func sendProofPulse() {
    runDebugSequence(
      named: "Proof pulse",
      steps: [
        DebugSequenceStep(
          payload: KeepAliveProtocol.offSignal,
          delayAfterMilliseconds: UInt64(KeepAliveProtocol.pulseDelayMilliseconds)
        ),
        DebugSequenceStep(payload: KeepAliveProtocol.onSignal, delayAfterMilliseconds: 0),
      ]
    )
  }

  func sendVisibleDemo() {
    runDebugSequence(
      named: "Visible demo",
      steps: [
        DebugSequenceStep(payload: KeepAliveProtocol.offSignal, delayAfterMilliseconds: 1_500),
        DebugSequenceStep(payload: KeepAliveProtocol.onSignal, delayAfterMilliseconds: 1_000),
        DebugSequenceStep(payload: KeepAliveProtocol.offSignal, delayAfterMilliseconds: 1_000),
        DebugSequenceStep(payload: KeepAliveProtocol.onSignal, delayAfterMilliseconds: 1_000),
        DebugSequenceStep(payload: KeepAliveProtocol.offSignal, delayAfterMilliseconds: 1_000),
        DebugSequenceStep(payload: KeepAliveProtocol.onSignal, delayAfterMilliseconds: 1_000),
        DebugSequenceStep(payload: KeepAliveProtocol.offSignal, delayAfterMilliseconds: 1_500),
        DebugSequenceStep(payload: KeepAliveProtocol.onSignal, delayAfterMilliseconds: 0),
      ]
    )
  }

  func sendOnOnlyProbe() {
    runDebugSequence(
      named: "On-only probe",
      steps: [
        DebugSequenceStep(payload: KeepAliveProtocol.onSignal, delayAfterMilliseconds: 0),
      ]
    )
  }

  private func runDebugSequence(named name: String, steps: [DebugSequenceStep]) {
    guard let activeReceiver else {
      lastErrorMessage = "No matched receiver available for \(name.lowercased())"
      return
    }

    guard !steps.isEmpty else {
      return
    }

    isRunningDebugAction = true
    lastErrorMessage = nil

    Task {
      do {
        for step in steps {
          try controller.sendRawOutputReport(
            step.payload,
            to: activeReceiver
          )

          if step.delayAfterMilliseconds > 0 {
            let delay = step.delayAfterMilliseconds * 1_000_000
            try await Task.sleep(nanoseconds: delay)
          }
        }

        await MainActor.run {
          self.isRunningDebugAction = false
          self.lastErrorMessage = nil
          self.logger.info("\(name, privacy: .public) completed")
        }
      } catch {
        await MainActor.run {
          self.isRunningDebugAction = false
          self.markDegraded(error.localizedDescription)
          self.logger.error("\(name, privacy: .public) failed: \(error.localizedDescription, privacy: .public)")
        }
      }
    }
  }
  #endif

  func markReceiverMissing() {
    stopKeeperIfNeeded()
    activeReceiver = nil
    activeMatch = nil
    keyboardName = nil
    batteryStatus = nil
    batteryLastUpdatedAt = nil
    lastErrorMessage = nil
    status = AppStatusReducer.reduce(from: status, event: .receiverMissing)
  }

  func markReceiverActive(_ match: HIDReceiverMatch) {
    if activeReceiver != match.snapshot {
      keyboardName = nil
      batteryStatus = nil
      batteryLastUpdatedAt = nil
    }

    activeReceiver = match.snapshot
    activeMatch = match
    lastErrorMessage = nil
    retryAttempt = 0
    status = AppStatusReducer.reduce(from: status, event: .receiverAcquired)
  }

  private func refreshDeviceDetails() {
    do {
      let details = try controller.readDeviceDetails(matching: activeReceiver)
      let previousKeyboardName = keyboardName
      let previousBatteryStatus = batteryStatus
      let refreshedAt = details.batteryStatus == nil ? nil : Date()

      if previousKeyboardName != details.keyboardName {
        keyboardName = details.keyboardName

        if let keyboardName = details.keyboardName {
          logger.info("Discovered keyboard name: \(keyboardName, privacy: .public)")
        }
      }

      if previousBatteryStatus != details.batteryStatus {
        batteryStatus = details.batteryStatus

        if let batteryStatus = details.batteryStatus {
          logger.info("Battery: \(batteryStatus.dischargeLevel, privacy: .public)%, status=\(batteryStatus.powerStatus.rawValue, privacy: .public)")
        }
      }

      batteryLastUpdatedAt = refreshedAt
    } catch {
      logger.error("Device details refresh failed: \(error.localizedDescription, privacy: .public)")
    }
  }

  func markDegraded(_ message: String) {
    lastErrorMessage = message
    retryAttempt += 1
    status = AppStatusReducer.reduce(from: status, event: .writeFailed)
  }

  func quit() {
    stopKeeperIfNeeded()
    NSApplication.shared.terminate(nil)
  }

  private func persistSettings() {
    guard let encoded = try? settingsEncoder.encode(settingsSnapshot) else {
      logger.error("Failed to encode settings")
      return
    }

    userDefaults.set(encoded, forKey: DefaultsKey.settings)
  }

  private static func loadSettings(from userDefaults: UserDefaults) -> MXLightkeeperSettings {
    guard let data = userDefaults.data(forKey: DefaultsKey.settings) else {
      return MXLightkeeperSettings()
    }

    return (try? JSONDecoder().decode(MXLightkeeperSettings.self, from: data)) ?? MXLightkeeperSettings()
  }
}
