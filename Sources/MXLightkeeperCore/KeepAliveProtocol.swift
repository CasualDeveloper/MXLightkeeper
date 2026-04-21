import Foundation

public enum KeepAliveProtocol {
  public static let offSignal = Data([0x10, 0x01, 0x0b, 0x1f, 0x00, 0x00, 0xff])
  public static let onSignal = Data([0x10, 0x01, 0x0b, 0x1f, 0x01, 0x00, 0xff])
  public static let keepAliveIntervalSeconds = 180
  public static let pulseDelayMilliseconds = 50
}
