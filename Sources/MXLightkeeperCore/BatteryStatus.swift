import Foundation

public enum BatteryPowerStatus: UInt8, Sendable {
  case discharging = 0
  case recharging = 1
  case almostFull = 2
  case chargingComplete = 3
  case wiredCharging = 4
  case critical = 5
  case invalidBattery = 6
  case thermalError = 7
  case unknown = 0xff

  public static func fromByte(_ byte: UInt8) -> BatteryPowerStatus {
    BatteryPowerStatus(rawValue: byte) ?? .unknown
  }
}

public struct BatteryStatus: Equatable, Sendable {
  public let dischargeLevel: UInt8
  public let nextLevel: UInt8
  public let powerStatus: BatteryPowerStatus

  public init(dischargeLevel: UInt8, nextLevel: UInt8, powerStatus: BatteryPowerStatus) {
    self.dischargeLevel = dischargeLevel
    self.nextLevel = nextLevel
    self.powerStatus = powerStatus
  }
}
