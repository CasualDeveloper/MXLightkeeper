import Foundation

public struct BacklightStatus: Equatable, Sendable {
  public let brightnessLevel: UInt8
  public let modeCode: UInt8

  public init(brightnessLevel: UInt8, modeCode: UInt8) {
    self.brightnessLevel = brightnessLevel
    self.modeCode = modeCode
  }

  public var isOff: Bool {
    brightnessLevel == 0 && modeCode == 0
  }

  public var summary: String {
    if isOff {
      return "off"
    }

    return "level \(brightnessLevel), mode 0x\(String(format: "%02x", modeCode))"
  }
}

public enum BacklightStatusDecoder {
  public static let statusQuery = Data([0x10, 0x01, 0x0b, 0x1f, 0x01, 0x00, 0xff])

  public static func decode(from report: Data) -> BacklightStatus? {
    let expectedCount = 7
    guard report.count >= expectedCount else {
      return nil
    }

    let header = (report[0], report[1], report[2], report[4])
    guard header.0 == 0x11, header.1 == 0x01, header.2 == 0x0b else {
      return nil
    }

    guard header.3 == 0x08 else {
      return nil
    }

    return BacklightStatus(brightnessLevel: report[5], modeCode: report[6])
  }
}

public struct Backlight2State: Equatable, Sendable {
  public let enabled: UInt8
  public let options: UInt8
  public let supported: UInt8
  public let effects: UInt16
  public let level: UInt8
  public let durationHandsOut: UInt16
  public let durationHandsIn: UInt16
  public let durationPowered: UInt16

  public init(
    enabled: UInt8,
    options: UInt8,
    supported: UInt8,
    effects: UInt16,
    level: UInt8,
    durationHandsOut: UInt16,
    durationHandsIn: UInt16,
    durationPowered: UInt16
  ) {
    self.enabled = enabled
    self.options = options
    self.supported = supported
    self.effects = effects
    self.level = level
    self.durationHandsOut = durationHandsOut
    self.durationHandsIn = durationHandsIn
    self.durationPowered = durationPowered
  }

  public var mode: UInt8 {
    (options >> 3) & 0x03
  }

  public var summary: String {
    "enabled=0x\(String(format: "%02x", enabled)) options=0x\(String(format: "%02x", options)) mode=0x\(String(format: "%02x", mode)) supported=0x\(String(format: "%02x", supported)) effects=0x\(String(format: "%04x", effects)) level=\(level) dho=\(durationHandsOut) dhi=\(durationHandsIn) dpow=\(durationPowered)"
  }
}

public enum Backlight2Codec {
  public static let featureIndex: UInt8 = 0x0b
  public static let readFunctionID: UInt8 = 0x00
  public static let writeFunctionID: UInt8 = 0x01

  static func keepAliveRequest(from state: Backlight2State) -> HIDPPReport {
    writeRequest(
      from: Backlight2State(
        enabled: 0x01,
        options: state.options,
        supported: state.supported,
        effects: state.effects,
        level: max(state.level, UInt8(1)),
        durationHandsOut: state.durationHandsOut,
        durationHandsIn: state.durationHandsIn,
        durationPowered: state.durationPowered
      )
    )
  }

  public static func decodeState(from report: HIDPPReport) -> Backlight2State? {
    guard report.featureIndex == featureIndex, report.functionID == readFunctionID else {
      return nil
    }

    let parameters = report.parameters
    guard parameters.count >= 12 else {
      return nil
    }

    let effects = UInt16(parameters[3]) | (UInt16(parameters[4]) << 8)
    let dho = UInt16(parameters[6]) | (UInt16(parameters[7]) << 8)
    let dhi = UInt16(parameters[8]) | (UInt16(parameters[9]) << 8)
    let dpow = UInt16(parameters[10]) | (UInt16(parameters[11]) << 8)

    return Backlight2State(
      enabled: parameters[0],
      options: parameters[1],
      supported: parameters[2],
      effects: effects,
      level: parameters[5],
      durationHandsOut: dho,
      durationHandsIn: dhi,
      durationPowered: dpow
    )
  }

  public static func readRequest() -> HIDPPReport {
    HIDPPReport(
      reportID: HIDPPReport.longReportID,
      deviceIndex: HIDPPDeviceIndex.receiverSlot1,
      featureIndex: featureIndex,
      functionID: readFunctionID,
      softwareID: HIDPPSoftwareID.mxLightkeeper,
      parameters: []
    )
  }

  public static func writeRequest(from state: Backlight2State) -> HIDPPReport {
    let level = state.mode == 0x03 ? state.level : 0

    // BACKLIGHT2 write payload per Solaar hidpp20.py:
    //   enabled(B) options(B) 0xFF(B) level(B) dho(H LE) dhi(H LE) dpow(H LE)
    // = 10 bytes. The containing HID++ long report serializes to 20 bytes
    // total with the remaining 6 trailing bytes zero-padded; MX Keys S
    // requires the full 16-byte payload, which this padding produces.
    return HIDPPReport(
      reportID: HIDPPReport.longReportID,
      deviceIndex: HIDPPDeviceIndex.receiverSlot1,
      featureIndex: featureIndex,
      functionID: writeFunctionID,
      softwareID: HIDPPSoftwareID.mxLightkeeper,
      parameters: [
        state.enabled,
        state.options,
        0xff,
        level,
        UInt8(state.durationHandsOut & 0xff),
        UInt8((state.durationHandsOut >> 8) & 0xff),
        UInt8(state.durationHandsIn & 0xff),
        UInt8((state.durationHandsIn >> 8) & 0xff),
        UInt8(state.durationPowered & 0xff),
        UInt8((state.durationPowered >> 8) & 0xff),
      ]
    )
  }
}
