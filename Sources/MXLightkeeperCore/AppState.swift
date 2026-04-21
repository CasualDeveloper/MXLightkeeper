import Foundation

public enum AppStatus: String, CaseIterable, Sendable {
  case disabled
  case waiting
  case active
  case degraded

  public var title: String {
    switch self {
    case .disabled:
      return "Off"
    case .waiting:
      return "Waiting"
    case .active:
      return "On"
    case .degraded:
      return "Reconnecting"
    }
  }

  public var subtitle: String {
    switch self {
    case .active:
      return "Backlight stays on"
    case .disabled:
      return "Backlight turns off automatically"
    case .waiting:
      return "Looking for a Logitech receiver"
    case .degraded:
      return "Trouble reaching the receiver"
    }
  }

  public var systemImageName: String {
    switch self {
    case .disabled:
      return "pause.circle"
    case .waiting:
      return "clock.arrow.trianglehead.counterclockwise.rotate.90"
    case .active:
      return "sun.max.circle.fill"
    case .degraded:
      return "exclamationmark.triangle"
    }
  }
}

public enum AppEvent: Sendable, Equatable {
  case setEnabled(Bool)
  case receiverMissing
  case receiverAcquired
  case writeFailed
  case recovered
}

public enum AppStatusReducer {
  public static func reduce(from current: AppStatus, event: AppEvent) -> AppStatus {
    let isDisabled = current == .disabled

    switch event {
    case .setEnabled(false):
      return .disabled
    case .setEnabled(true):
      return .waiting
    case .receiverMissing:
      return isDisabled ? .disabled : .waiting
    case .receiverAcquired, .recovered:
      return isDisabled ? .disabled : .active
    case .writeFailed:
      return isDisabled ? .disabled : .degraded
    }
  }
}

public struct MXLightkeeperSettings: Codable, Equatable, Sendable {
  public var isEnabled: Bool
  public var launchAtLogin: Bool

  public init(
    isEnabled: Bool = true,
    launchAtLogin: Bool = false
  ) {
    self.isEnabled = isEnabled
    self.launchAtLogin = launchAtLogin
  }
}
