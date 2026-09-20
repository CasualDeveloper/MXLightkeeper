@testable import MXLightkeeperCore
import Testing

@Test func enabledExpectationIgnoresModeAndLevel() {
  #expect(Backlight2Expectation.enabled(false).isSatisfied(by: state(enabled: 0x00, options: 0x18, level: 5)))
  #expect(Backlight2Expectation.enabled(true).isSatisfied(by: state(enabled: 0x01, options: 0x00, level: 0)))
}

@Test func manualExpectationChecksEnabledModeAndLevel() {
  let expectation = Backlight2Expectation.manualLevel(5)

  #expect(expectation.isSatisfied(by: state(enabled: 0x01, options: 0x18, level: 5)))
  #expect(expectation.isSatisfied(by: state(enabled: 0x01, options: 0x9b, level: 5)))
  #expect(!expectation.isSatisfied(by: state(enabled: 0x00, options: 0x18, level: 5)))
  #expect(!expectation.isSatisfied(by: state(enabled: 0x01, options: 0x10, level: 5)))
  #expect(!expectation.isSatisfied(by: state(enabled: 0x01, options: 0x18, level: 4)))
}

@MainActor
@Test func controllerRejectsMismatchedReadback() {
  let controller = MXLightkeeperController()
  let observed = state(enabled: 0x01, options: 0x10, level: 5)
  let expected = Backlight2Expectation.manualLevel(5)

  #expect(
    throws: MXLightkeeperControllerError.readbackMismatch(
      expected: expected,
      observed: observed
    )
  ) {
    try controller.validatedReadback(observed, expected: expected)
  }
}

private func state(enabled: UInt8, options: UInt8, level: UInt8) -> Backlight2State {
  Backlight2State(
    enabled: enabled,
    options: options,
    supported: 0x7f,
    effects: 0x1234,
    level: level,
    durationHandsOut: 0x000b,
    durationHandsIn: 0x000d,
    durationPowered: 0x003c
  )
}
