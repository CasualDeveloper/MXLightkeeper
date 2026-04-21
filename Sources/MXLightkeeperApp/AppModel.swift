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
  private var devicePollTask: Task<Void, Never>?
  private static let devicePollIntervalNanoseconds: UInt64 = 60 * 1_000_000_000

  private(set) var isEnabled: Bool
  private(set) var launchAtLogin: Bool
  private(set) var experimentalBoltEnabled: Bool

  var status: AppStatus
  var activeReceiver: ReceiverSnapshot?
  var activeMatch: HIDReceiverMatch?
  var availableReceivers: [HIDReceiverMatch] = []
  var lastErrorMessage: String?
  var keyboardName: String?
  var batteryStatus: BatteryStatus?
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
    startDevicePolling()
  }

  private func startDevicePolling() {
    devicePollTask?.cancel()
    devicePollTask = Task { @MainActor [weak self] in
      while !Task.isCancelled {
        if let self {
          self.refreshReceivers()
          if self.activeMatch != nil {
            self.discoverKeyboardName()
            self.discoverBatteryStatus()
          }
        }
        try? await Task.sleep(nanoseconds: Self.devicePollIntervalNanoseconds)
      }
    }
  }

  var settingsSnapshot: MXLightkeeperSettings {
    MXLightkeeperSettings(
      isEnabled: isEnabled,
      launchAtLogin: launchAtLogin,
      enableExperimentalBolt: experimentalBoltEnabled
    )
  }

  var keyboardLabel: String? {
    guard let keyboardName, !keyboardName.isEmpty else {
      return nil
    }
    return keyboardName
  }

  var receiverLabel: String {
    guard let activeMatch else {
      return "No receiver connected"
    }

    return "\(activeMatch.matcher.kind.displayName) receiver"
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
    keyboardName = nil
    batteryStatus = nil
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

  private func discoverBatteryStatus() {
    do {
      let target = try HIDReceiverService.firstMatchedDevice(
        includeExperimentalBolt: experimentalBoltEnabled
      )
      let session = try HIDPPProbeSession(target: target)
      defer { session.close() }

      let rootRequest = HIDPPReport(
        reportID: HIDPPReport.shortReportID,
        deviceIndex: HIDPPDeviceIndex.receiverSlot1,
        featureIndex: 0x00,
        functionID: 0x00,
        softwareID: HIDPPSoftwareID.mxLightkeeper,
        parameters: [0x10, 0x00, 0x00]
      )
      let rootResponse = try session.sendRequest(rootRequest, timeout: 1.0)
      let batteryFeatureIndex = rootResponse.parameters.first ?? 0
      guard batteryFeatureIndex != 0 else {
        return
      }

      let statusRequest = HIDPPReport(
        reportID: HIDPPReport.shortReportID,
        deviceIndex: HIDPPDeviceIndex.receiverSlot1,
        featureIndex: batteryFeatureIndex,
        functionID: 0x00,
        softwareID: HIDPPSoftwareID.mxLightkeeper,
        parameters: [0x00, 0x00, 0x00]
      )
      let response = try session.sendRequest(statusRequest, timeout: 1.0)
      guard response.parameters.count >= 3 else { return }

      let status = BatteryStatus(
        dischargeLevel: response.parameters[0],
        nextLevel: response.parameters[1],
        powerStatus: BatteryPowerStatus.fromByte(response.parameters[2])
      )

      batteryStatus = status
      logger.info("Battery: \(status.dischargeLevel, privacy: .public)%, status=\(status.powerStatus.rawValue, privacy: .public)")
    } catch {
      logger.error("Battery status discovery failed: \(error.localizedDescription, privacy: .public)")
    }
  }

  private func discoverKeyboardName() {
    do {
      let target = try HIDReceiverService.firstMatchedDevice(
        includeExperimentalBolt: experimentalBoltEnabled
      )
      let session = try HIDPPProbeSession(target: target)
      defer { session.close() }

      let rootRequest = HIDPPReport(
        reportID: HIDPPReport.shortReportID,
        deviceIndex: HIDPPDeviceIndex.receiverSlot1,
        featureIndex: 0x00,
        functionID: 0x00,
        softwareID: HIDPPSoftwareID.mxLightkeeper,
        parameters: [0x00, 0x05, 0x00]
      )
      let rootResponse = try session.sendRequest(rootRequest, timeout: 1.0)
      let deviceNameFeatureIndex = rootResponse.parameters.first ?? 0
      guard deviceNameFeatureIndex != 0 else {
        return
      }

      let countRequest = HIDPPReport(
        reportID: HIDPPReport.shortReportID,
        deviceIndex: HIDPPDeviceIndex.receiverSlot1,
        featureIndex: deviceNameFeatureIndex,
        functionID: 0x00,
        softwareID: HIDPPSoftwareID.mxLightkeeper,
        parameters: [0x00, 0x00, 0x00]
      )
      let countResponse = try session.sendRequest(countRequest, timeout: 1.0)
      let count = Int(countResponse.parameters.first ?? 0)
      guard count > 0, count < 64 else {
        return
      }

      var bytes: [UInt8] = []
      var offset = 0
      while offset < count {
        let nameRequest = HIDPPReport(
          reportID: HIDPPReport.shortReportID,
          deviceIndex: HIDPPDeviceIndex.receiverSlot1,
          featureIndex: deviceNameFeatureIndex,
          functionID: 0x01,
          softwareID: HIDPPSoftwareID.mxLightkeeper,
          parameters: [UInt8(offset), 0x00, 0x00]
        )
        let nameResponse = try session.sendRequest(nameRequest, timeout: 1.0)
        let remaining = count - offset
        let chunk = Array(nameResponse.parameters.prefix(remaining))
        guard !chunk.isEmpty else { break }
        bytes.append(contentsOf: chunk)
        offset += chunk.count
      }

      let name = String(decoding: bytes, as: UTF8.self)
        .trimmingCharacters(in: .controlCharacters)
      guard !name.isEmpty else { return }

      keyboardName = name
      logger.info("Discovered keyboard name: \(name, privacy: .public)")
    } catch {
      logger.error("Keyboard name discovery failed: \(error.localizedDescription, privacy: .public)")
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
