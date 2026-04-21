import Foundation

public enum MXLightkeeperControllerError: Error, LocalizedError, Sendable, Equatable {
  case receiverChanged
  case stateDecodeFailed
  case invalidManualLevel(UInt8)

  public var errorDescription: String? {
    switch self {
    case .receiverChanged:
      return "Matched receiver changed while performing the request"
    case .stateDecodeFailed:
      return "Failed to decode the current BACKLIGHT2 state"
    case .invalidManualLevel(let level):
      return "Invalid manual brightness level '\(level)'. Expected a value from 1 to 7."
    }
  }
}

public struct MXLightkeeperDeviceDetails: Equatable, Sendable {
  public let keyboardName: String?
  public let batteryStatus: BatteryStatus?

  public init(keyboardName: String?, batteryStatus: BatteryStatus?) {
    self.keyboardName = keyboardName
    self.batteryStatus = batteryStatus
  }
}

public struct MXLightkeeperRuntimeState: Sendable {
  public let receiver: HIDReceiverMatch
  public let keeper: BacklightKeeper

  public init(receiver: HIDReceiverMatch, keeper: BacklightKeeper) {
    self.receiver = receiver
    self.keeper = keeper
  }
}

@MainActor
public struct MXLightkeeperController: Sendable {
  private let probeTimeoutSeconds: TimeInterval

  public init(probeTimeoutSeconds: TimeInterval = 1.0) {
    self.probeTimeoutSeconds = probeTimeoutSeconds
  }

  public func listReceivers() throws -> [HIDReceiverMatch] {
    try HIDReceiverService().listReceivers()
  }

  public func firstMatchedReceiver() throws -> HIDReceiverMatch {
    try resolveTarget(matching: nil).match
  }

  public func makeKeeper(
    matching snapshot: ReceiverSnapshot? = nil,
    refreshIntervalSeconds: TimeInterval = TimeInterval(KeepAliveProtocol.keepAliveIntervalSeconds)
  ) throws -> BacklightKeeper {
    let target = try resolveTarget(matching: snapshot)
    return BacklightKeeper(
      snapshot: target.match.snapshot,
      refreshIntervalSeconds: refreshIntervalSeconds,
      refreshOperation: { snapshot in
        try self.refreshKeepAlive(matching: snapshot)
      }
    )
  }

  public func prepareRuntimeState(
    matching snapshot: ReceiverSnapshot? = nil,
    refreshIntervalSeconds: TimeInterval = TimeInterval(KeepAliveProtocol.keepAliveIntervalSeconds)
  ) throws -> MXLightkeeperRuntimeState {
    let target = try resolveTarget(matching: snapshot)
    let keeper = BacklightKeeper(
      snapshot: target.match.snapshot,
      refreshIntervalSeconds: refreshIntervalSeconds,
      refreshOperation: { keeperSnapshot in
        try self.refreshKeepAlive(matching: keeperSnapshot)
      }
    )

    return MXLightkeeperRuntimeState(receiver: target.match, keeper: keeper)
  }

  public func readBacklightState(matching snapshot: ReceiverSnapshot? = nil) throws -> Backlight2State {
    try withSession(matching: snapshot) { _, session in
      try readCurrentState(with: session)
    }
  }

  public func setBacklightEnabled(
    _ enabled: Bool,
    matching snapshot: ReceiverSnapshot? = nil
  ) throws -> Backlight2State {
    try withSession(matching: snapshot) { _, session in
      let current = try readCurrentState(with: session)
      let updated = updatedState(
        from: current,
        enabled: enabled,
        level: enabled ? max(current.level, UInt8(1)) : nil,
        mode: nil
      )

      _ = try session.sendRequest(
        Backlight2Codec.writeRequest(from: updated),
        timeout: probeTimeoutSeconds
      )

      return try readCurrentState(with: session)
    }
  }

  public func setManualLevel(
    _ level: UInt8,
    matching snapshot: ReceiverSnapshot? = nil
  ) throws -> Backlight2State {
    guard (1...7).contains(level) else {
      throw MXLightkeeperControllerError.invalidManualLevel(level)
    }

    return try withSession(matching: snapshot) { _, session in
      let current = try readCurrentState(with: session)
      let updated = updatedState(
        from: current,
        enabled: true,
        level: level,
        mode: 0x03
      )

      _ = try session.sendRequest(
        Backlight2Codec.writeRequest(from: updated),
        timeout: probeTimeoutSeconds
      )

      return try readCurrentState(with: session)
    }
  }

  public func readDeviceDetails(matching snapshot: ReceiverSnapshot? = nil) throws -> MXLightkeeperDeviceDetails {
    try withSession(matching: snapshot) { _, session in
      MXLightkeeperDeviceDetails(
        keyboardName: try? readKeyboardName(with: session),
        batteryStatus: try? readBatteryStatus(with: session)
      )
    }
  }

  public func sendRawOutputReport(_ payload: Data, to snapshot: ReceiverSnapshot) throws {
    try HIDReceiverService().sendOutputReport(payload, to: snapshot)
  }

  public func refreshKeepAlive(matching snapshot: ReceiverSnapshot) throws {
    try withSession(matching: snapshot) { _, session in
      let current = try readCurrentState(with: session)
      _ = try session.sendRequest(
        Backlight2Codec.keepAliveRequest(from: current),
        timeout: probeTimeoutSeconds
      )
    }
  }

  private func resolveTarget(matching snapshot: ReceiverSnapshot?) throws -> HIDReceiverTarget {
    let target = try HIDReceiverService.firstMatchedDevice()
    if let snapshot, target.match.snapshot != snapshot {
      throw MXLightkeeperControllerError.receiverChanged
    }
    return target
  }

  private func withSession<T>(
    matching snapshot: ReceiverSnapshot? = nil,
    _ work: (HIDReceiverTarget, HIDPPProbeSession) throws -> T
  ) throws -> T {
    let target = try resolveTarget(matching: snapshot)
    let session = try HIDPPProbeSession(target: target)
    defer { session.close() }
    return try work(target, session)
  }

  private func readCurrentState(with session: HIDPPProbeSession) throws -> Backlight2State {
    let response = try session.sendRequest(Backlight2Codec.readRequest(), timeout: probeTimeoutSeconds)
    guard let state = Backlight2Codec.decodeState(from: response) else {
      throw MXLightkeeperControllerError.stateDecodeFailed
    }
    return state
  }

  private func updatedState(
    from current: Backlight2State,
    enabled: Bool,
    level: UInt8?,
    mode: UInt8?
  ) -> Backlight2State {
    var options = current.options
    if let mode {
      options = (options & ~0x18) | ((mode & 0x03) << 3)
    }

    return Backlight2State(
      enabled: enabled ? 0x01 : 0x00,
      options: options,
      supported: current.supported,
      effects: current.effects,
      level: level ?? current.level,
      durationHandsOut: current.durationHandsOut,
      durationHandsIn: current.durationHandsIn,
      durationPowered: current.durationPowered
    )
  }

  private func readKeyboardName(with session: HIDPPProbeSession) throws -> String? {
    guard let featureIndex = try resolveFeatureIndex(.deviceName, with: session) else {
      return nil
    }

    let countRequest = HIDPPReport(
      reportID: HIDPPReport.shortReportID,
      deviceIndex: HIDPPDeviceIndex.receiverSlot1,
      featureIndex: featureIndex,
      functionID: 0x00,
      softwareID: HIDPPSoftwareID.mxLightkeeper,
      parameters: [0x00, 0x00, 0x00]
    )
    let countResponse = try session.sendRequest(countRequest, timeout: probeTimeoutSeconds)
    let count = Int(countResponse.parameters.first ?? 0)
    guard count > 0, count < 64 else {
      return nil
    }

    var bytes: [UInt8] = []
    var offset = 0
    while offset < count {
      let nameRequest = HIDPPReport(
        reportID: HIDPPReport.shortReportID,
        deviceIndex: HIDPPDeviceIndex.receiverSlot1,
        featureIndex: featureIndex,
        functionID: 0x01,
        softwareID: HIDPPSoftwareID.mxLightkeeper,
        parameters: [UInt8(offset), 0x00, 0x00]
      )
      let nameResponse = try session.sendRequest(nameRequest, timeout: probeTimeoutSeconds)
      let remaining = count - offset
      let chunk = Array(nameResponse.parameters.prefix(remaining))
      guard !chunk.isEmpty else {
        break
      }

      bytes.append(contentsOf: chunk)
      offset += chunk.count
    }

    let decodedName = String(decoding: bytes, as: UTF8.self)
    let trimmedName = decodedName.trimmingCharacters(in: .controlCharacters)
    return trimmedName.isEmpty ? nil : trimmedName
  }

  private func readBatteryStatus(with session: HIDPPProbeSession) throws -> BatteryStatus? {
    guard let featureIndex = try resolveFeatureIndex(.batteryStatus, with: session) else {
      return nil
    }

    let statusRequest = HIDPPReport(
      reportID: HIDPPReport.shortReportID,
      deviceIndex: HIDPPDeviceIndex.receiverSlot1,
      featureIndex: featureIndex,
      functionID: 0x00,
      softwareID: HIDPPSoftwareID.mxLightkeeper,
      parameters: [0x00, 0x00, 0x00]
    )
    let response = try session.sendRequest(statusRequest, timeout: probeTimeoutSeconds)
    guard response.parameters.count >= 3 else {
      return nil
    }

    return BatteryStatus(
      dischargeLevel: response.parameters[0],
      nextLevel: response.parameters[1],
      powerStatus: BatteryPowerStatus.fromByte(response.parameters[2])
    )
  }

  private func resolveFeatureIndex(
    _ featureID: HIDPPFeatureID,
    with session: HIDPPProbeSession
  ) throws -> UInt8? {
    let response = try session.sendRequest(
      HIDPPRoot.getFeatureIDRequest(featureID: featureID),
      timeout: probeTimeoutSeconds
    )
    let featureIndex = response.parameters.first ?? 0
    return featureIndex == 0 ? nil : featureIndex
  }
}
