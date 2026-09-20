import MXLightkeeperCore
import Foundation
import Testing

@Test func enablingTransitionsToWaiting() {
  let status = AppStatusReducer.reduce(from: .disabled, event: .setEnabled(true))
  #expect(status == .waiting)
}

@Test func receiverAcquiredDoesNotWakeDisabledState() {
  let status = AppStatusReducer.reduce(from: .disabled, event: .receiverAcquired)
  #expect(status == .disabled)
}

@Test func receiverAcquiredStartsEnabledState() {
  let status = AppStatusReducer.reduce(from: .waiting, event: .receiverAcquired)
  #expect(status == .starting)
}

@Test func successfulRefreshActivatesStartingState() {
  let status = AppStatusReducer.reduce(from: .starting, event: .recovered)
  #expect(status == .active)
}

@Test func writeFailureMarksEnabledStateDegraded() {
  let status = AppStatusReducer.reduce(from: .active, event: .writeFailed)
  #expect(status == .degraded)
}

@Test func settingsRoundTripPreservesValues() throws {
  let settings = MXLightkeeperSettings(isEnabled: false, launchAtLogin: true)
  let encoded = try JSONEncoder().encode(settings)

  #expect(try JSONDecoder().decode(MXLightkeeperSettings.self, from: encoded) == settings)
}
