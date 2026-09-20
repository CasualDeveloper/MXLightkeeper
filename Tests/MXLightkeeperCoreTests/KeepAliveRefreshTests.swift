@testable import MXLightkeeperCore
import Foundation
import Testing

@MainActor
@Test func controllerReportsCompletePulse() throws {
  let writer = ScriptedReceiverWriter()
  let controller = makeController(writer: writer)
  let snapshot = receiverSnapshot()

  try controller.refreshKeepAlive(matching: snapshot)

  #expect(writer.payloads == [KeepAliveProtocol.offSignal, KeepAliveProtocol.onSignal])
}

@MainActor
@Test func controllerIdentifiesFirstReportFailure() {
  let writer = ScriptedReceiverWriter(failingAttempt: 1)
  let controller = makeController(writer: writer)
  let snapshot = receiverSnapshot()

  #expect(
    throws: KeepAliveRefreshError(
      completedStage: .notStarted,
      failureDescription: "Failed to send the first keep-alive report: Scripted write failure"
    )
  ) {
    try controller.refreshKeepAlive(matching: snapshot)
  }
  #expect(writer.payloads == [KeepAliveProtocol.offSignal])
}

@MainActor
@Test func controllerIdentifiesSecondReportFailure() {
  let writer = ScriptedReceiverWriter(failingAttempt: 2)
  let controller = makeController(writer: writer)
  let snapshot = receiverSnapshot()

  #expect(
    throws: KeepAliveRefreshError(
      completedStage: .offReportSent,
      failureDescription: "Failed to send the second keep-alive report: Scripted write failure"
    )
  ) {
    try controller.refreshKeepAlive(matching: snapshot)
  }
  #expect(writer.payloads == [KeepAliveProtocol.offSignal, KeepAliveProtocol.onSignal])
}

@MainActor
@Test func keeperPublishesSuccessfulRefreshResult() {
  let snapshot = receiverSnapshot()
  let attemptedAt = Date(timeIntervalSince1970: 1_234)
  var handledResult: KeepAliveRefreshResult?
  let keeper = BacklightKeeper(
    snapshot: snapshot,
    refreshOperation: { _ in },
    resultHandler: { handledResult = $0 },
    now: { attemptedAt }
  )

  let result = keeper.performRefresh()

  #expect(result.isSuccess)
  #expect(result.completedStage == .complete)
  #expect(result.attemptedAt == attemptedAt)
  #expect(keeper.lastRefreshResult == result)
  #expect(handledResult == result)
}

@MainActor
@Test func keeperPublishesPartialRefreshFailure() {
  let snapshot = receiverSnapshot()
  let failure = KeepAliveRefreshError(
    completedStage: .offReportSent,
    failureDescription: "Second report failed"
  )
  let keeper = BacklightKeeper(
    snapshot: snapshot,
    refreshOperation: { _ in throw failure }
  )

  let result = keeper.performRefresh()

  #expect(!result.isSuccess)
  #expect(result.completedStage == .offReportSent)
  #expect(result.failureDescription == "Second report failed")
}

@MainActor
private func makeController(writer: ScriptedReceiverWriter) -> MXLightkeeperController {
  MXLightkeeperController(
    receiverEnumerator: EmptyReceiverEnumerator(),
    receiverWriter: writer,
    pulseDelay: {}
  )
}

private func receiverSnapshot() -> ReceiverSnapshot {
  ReceiverSnapshot(
    vendorID: 0x046d,
    productID: 0xc52b,
    usagePage: 0xFF00,
    usage: 1,
    productName: "USB Receiver",
    transport: "USB"
  )
}

private struct EmptyReceiverEnumerator: ReceiverEnumerating {
  func listReceivers() throws -> [HIDReceiverMatch] {
    []
  }
}

private final class ScriptedReceiverWriter: ReceiverWriting, @unchecked Sendable {
  private let failingAttempt: Int?
  private(set) var payloads: [Data] = []

  init(failingAttempt: Int? = nil) {
    self.failingAttempt = failingAttempt
  }

  func sendOutputReport(_ payload: Data, to snapshot: ReceiverSnapshot) throws {
    payloads.append(payload)
    if payloads.count == failingAttempt {
      throw ScriptedWriteError()
    }
  }
}

private struct ScriptedWriteError: LocalizedError {
  var errorDescription: String? {
    "Scripted write failure"
  }
}
