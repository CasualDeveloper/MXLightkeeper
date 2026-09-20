import Foundation

public enum KeepAliveRefreshStage: String, Sendable, Equatable {
  case notStarted
  case offReportSent
  case complete
}

public struct KeepAliveRefreshResult: Sendable, Equatable {
  public let receiver: ReceiverSnapshot
  public let attemptedAt: Date
  public let completedStage: KeepAliveRefreshStage
  public let failureDescription: String?

  public var isSuccess: Bool {
    completedStage == .complete && failureDescription == nil
  }

  public init(
    receiver: ReceiverSnapshot,
    attemptedAt: Date,
    completedStage: KeepAliveRefreshStage,
    failureDescription: String? = nil
  ) {
    self.receiver = receiver
    self.attemptedAt = attemptedAt
    self.completedStage = completedStage
    self.failureDescription = failureDescription
  }
}

public struct KeepAliveRefreshError: Error, LocalizedError, Sendable, Equatable {
  public let completedStage: KeepAliveRefreshStage
  public let failureDescription: String

  public var errorDescription: String? {
    failureDescription
  }

  public init(completedStage: KeepAliveRefreshStage, failureDescription: String) {
    self.completedStage = completedStage
    self.failureDescription = failureDescription
  }
}
