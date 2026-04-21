import Foundation

public struct RetryPolicy: Sendable, Equatable {
  public let immediateAttempts: Int
  public let baseDelaySeconds: TimeInterval
  public let maxDelaySeconds: TimeInterval

  public init(
    immediateAttempts: Int = 1,
    baseDelaySeconds: TimeInterval = 2,
    maxDelaySeconds: TimeInterval = 30
  ) {
    self.immediateAttempts = immediateAttempts
    self.baseDelaySeconds = baseDelaySeconds
    self.maxDelaySeconds = maxDelaySeconds
  }

  public func delaySeconds(forAttempt attempt: Int) -> TimeInterval {
    guard attempt > immediateAttempts else {
      return 0
    }

    let exponent = attempt - immediateAttempts - 1
    let scaledDelay = baseDelaySeconds * pow(2, Double(max(0, exponent)))
    return min(maxDelaySeconds, scaledDelay)
  }
}
