import MXLightkeeperCore
import Testing

@Test func enablingTransitionsToWaiting() {
  let status = AppStatusReducer.reduce(from: .disabled, event: .setEnabled(true))
  #expect(status == .waiting)
}

@Test func receiverAcquiredDoesNotWakeDisabledState() {
  let status = AppStatusReducer.reduce(from: .disabled, event: .receiverAcquired)
  #expect(status == .disabled)
}

@Test func writeFailureMarksEnabledStateDegraded() {
  let status = AppStatusReducer.reduce(from: .active, event: .writeFailed)
  #expect(status == .degraded)
}
