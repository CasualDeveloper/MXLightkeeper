import Foundation

public enum HIDPPFeatureID: UInt16, CaseIterable, Sendable {
  case root = 0x0000
  case featureSet = 0x0001
  case deviceInfo = 0x0003
  case deviceName = 0x0005
  case batteryStatus = 0x1000
  case batteryUnified = 0x1004
  case changeHost = 0x1814
  case backlight = 0x1981
  case backlight2 = 0x1982
  case backlight3 = 0x1983
  case reprogControls = 0x1b00
  case reprogControlsV2 = 0x1b01
  case reprogControlsV22 = 0x1b02
  case reprogControlsV3 = 0x1b03
  case reprogControlsV4 = 0x1b04
  case smartShift = 0x2110
  case smartShiftEnhanced = 0x2111
  case hiResWheel = 0x2121
  case thumbWheel = 0x2150
  case adjustableDPI = 0x2201
  case gestureV2 = 0x6501

  public var displayName: String {
    switch self {
    case .root: return "Root"
    case .featureSet: return "FeatureSet"
    case .deviceInfo: return "DeviceInfo"
    case .deviceName: return "DeviceName"
    case .batteryStatus: return "BatteryStatus"
    case .batteryUnified: return "BatteryUnified"
    case .changeHost: return "ChangeHost"
    case .backlight: return "Backlight"
    case .backlight2: return "Backlight2"
    case .backlight3: return "Backlight3"
    case .reprogControls: return "ReprogControls"
    case .reprogControlsV2: return "ReprogControlsV2"
    case .reprogControlsV22: return "ReprogControlsV2.2"
    case .reprogControlsV3: return "ReprogControlsV3"
    case .reprogControlsV4: return "ReprogControlsV4"
    case .smartShift: return "SmartShift"
    case .smartShiftEnhanced: return "SmartShiftEnhanced"
    case .hiResWheel: return "HiResWheel"
    case .thumbWheel: return "ThumbWheel"
    case .adjustableDPI: return "AdjustableDPI"
    case .gestureV2: return "GestureV2"
    }
  }
}

public struct HIDPPReport: Sendable, Equatable {
  public static let shortReportID: UInt8 = 0x10
  public static let longReportID: UInt8 = 0x11
  public static let shortSize = 7
  public static let longSize = 20

  public let reportID: UInt8
  public let deviceIndex: UInt8
  public let featureIndex: UInt8
  public let functionID: UInt8
  public let softwareID: UInt8
  public let parameters: [UInt8]

  public init(
    reportID: UInt8,
    deviceIndex: UInt8,
    featureIndex: UInt8,
    functionID: UInt8,
    softwareID: UInt8,
    parameters: [UInt8]
  ) {
    self.reportID = reportID
    self.deviceIndex = deviceIndex
    self.featureIndex = featureIndex
    self.functionID = functionID
    self.softwareID = softwareID
    self.parameters = parameters
  }

  public var packedFunctionAndSoftwareID: UInt8 {
    ((functionID & 0x0f) << 4) | (softwareID & 0x0f)
  }

  public var serializedData: Data {
    switch reportID {
    case Self.longReportID:
      var bytes = [UInt8](repeating: 0, count: Self.longSize)
      bytes[0] = reportID
      bytes[1] = deviceIndex
      bytes[2] = featureIndex
      bytes[3] = packedFunctionAndSoftwareID
      for (index, value) in parameters.prefix(16).enumerated() {
        bytes[4 + index] = value
      }
      return Data(bytes)
    case Self.shortReportID:
      var bytes = [UInt8](repeating: 0, count: Self.shortSize)
      bytes[0] = reportID
      bytes[1] = deviceIndex
      bytes[2] = featureIndex
      bytes[3] = packedFunctionAndSoftwareID
      for (index, value) in parameters.prefix(3).enumerated() {
        bytes[4 + index] = value
      }
      return Data(bytes)
    default:
      return Data()
    }
  }

  public static func parse(_ data: Data) -> HIDPPReport? {
    guard let reportID = data.first else {
      return nil
    }

    switch reportID {
    case shortReportID:
      guard data.count >= shortSize else {
        return nil
      }
      return HIDPPReport(
        reportID: reportID,
        deviceIndex: data[1],
        featureIndex: data[2],
        functionID: data[3] >> 4,
        softwareID: data[3] & 0x0f,
        parameters: Array(data[4..<shortSize])
      )
    case longReportID:
      guard data.count >= longSize else {
        return nil
      }
      return HIDPPReport(
        reportID: reportID,
        deviceIndex: data[1],
        featureIndex: data[2],
        functionID: data[3] >> 4,
        softwareID: data[3] & 0x0f,
        parameters: Array(data[4..<longSize])
      )
    default:
      return nil
    }
  }

  public var isError: Bool {
    featureIndex == 0xff
  }

  public var hexString: String {
    serializedData.map { String(format: "%02x", $0) }.joined(separator: " ")
  }
}

public enum HIDPPDeviceIndex {
  public static let direct: UInt8 = 0xff
  public static let receiverSlot1: UInt8 = 0x01
}

public enum HIDPPSoftwareID {
  public static let mxLightkeeper: UInt8 = 0x01
}

public enum HIDPPRoot {
  public static func getFeatureIDRequest(featureID: HIDPPFeatureID) -> HIDPPReport {
    HIDPPReport(
      reportID: HIDPPReport.shortReportID,
      deviceIndex: HIDPPDeviceIndex.receiverSlot1,
      featureIndex: 0x00,
      functionID: 0x00,
      softwareID: HIDPPSoftwareID.mxLightkeeper,
      parameters: [
        UInt8(featureID.rawValue >> 8),
        UInt8(featureID.rawValue & 0xff),
        0x00,
      ]
    )
  }
}
