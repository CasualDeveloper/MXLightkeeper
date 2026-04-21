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

  private let userDefaults: UserDefaults
  private let receiverService: ReceiverEnumerating & ReceiverWriting
  private let logger = Logger(subsystem: "MXLightkeeper", category: "AppModel")
  private let settingsEncoder = JSONEncoder()
  private var backlightKeeper: BacklightKeeper?

  private(set) var isEnabled: Bool
  private(set) var launchAtLogin: Bool
  private(set) var experimentalBoltEnabled: Bool

  var status: AppStatus
  var activeReceiver: ReceiverSnapshot?
  var activeMatch: HIDReceiverMatch?
  var availableReceivers: [HIDReceiverMatch] = []
  var lastErrorMessage: String?
  var isRunningDebugAction = false
  var retryAttempt = 0

  init(
    userDefaults: UserDefaults = .standard,
    receiverService: some ReceiverEnumerating & ReceiverWriting = HIDReceiverService()
  ) {
    self.userDefaults = userDefaults
    self.receiverService = receiverService

    let settings = Self.loadSettings(from: userDefaults)
    isEnabled = settings.isEnabled
    launchAtLogin = settings.launchAtLogin
    experimentalBoltEnabled = settings.enableExperimentalBolt
    status = settings.isEnabled ? .waiting : .disabled

    refreshReceivers()
  }

  var settingsSnapshot: MXLightkeeperSettings {
    MXLightkeeperSettings(
      isEnabled: isEnabled,
      launchAtLogin: launchAtLogin,
      enableExperimentalBolt: experimentalBoltEnabled
    )
  }

  var receiverLabel: String {
    guard let activeMatch else {
      return "No receiver connected"
    }

    return "\(activeMatch.matcher.kind.displayName) receiver"
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
    ReceiverCatalog
      .enabledMatchers(includeExperimentalBolt: experimentalBoltEnabled)
      .map { matcher in
        let suffix = matcher.experimental ? " (experimental)" : ""
        return "\(matcher.kind.displayName) \(suffix)"
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

  func setExperimentalBoltEnabled(_ enabled: Bool) {
    experimentalBoltEnabled = enabled
    persistSettings()
    logger.info("Experimental Bolt changed to \(enabled, privacy: .public)")
    refreshReceivers()
  }

  func refreshReceivers() {
    do {
      availableReceivers = try receiverService.listReceivers(includeExperimentalBolt: experimentalBoltEnabled)
      if let firstMatch = availableReceivers.first {
        markReceiverActive(firstMatch)
        if isEnabled {
          startKeeperIfPossible()
        }
      } else {
        markReceiverMissing()
      }
    } catch {
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

    if backlightKeeper?.isRunning == true {
      return
    }

    do {
      let target = try HIDReceiverService.firstMatchedDevice(includeExperimentalBolt: experimentalBoltEnabled)
      guard target.match.snapshot == activeReceiver else {
        return
      }

      backlightKeeper = try BacklightKeeper(target: target)
      backlightKeeper?.start()
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

    let receiverService = receiverService
    let includeExperimentalBolt = experimentalBoltEnabled

    isRunningDebugAction = true
    lastErrorMessage = nil

    Task {
      do {
        for step in steps {
          try receiverService.sendOutputReport(
            step.payload,
            to: activeReceiver,
            includeExperimentalBolt: includeExperimentalBolt
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
    activeReceiver = nil
    activeMatch = nil
    lastErrorMessage = nil
    status = AppStatusReducer.reduce(from: status, event: .receiverMissing)
  }

  func markReceiverActive(_ match: HIDReceiverMatch) {
    activeReceiver = match.snapshot
    activeMatch = match
    lastErrorMessage = nil
    retryAttempt = 0
    status = AppStatusReducer.reduce(from: status, event: .receiverAcquired)
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
