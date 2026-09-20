@testable import mxlightkeeper
import MXLightkeeperCore
import Testing

@Test(
  arguments: [
    ([], BacklightCommand.help),
    (["-h"], .help),
    (["--help"], .help),
    (["read"], .read),
    (["on"], .on),
    (["off"], .off),
    (["keep"], .keep),
    (["manual", "--level", "1"], .manual(level: 1)),
    (["manual", "--level", "7"], .manual(level: 7)),
  ]
)
func validInvocationParses(arguments: [String], expected: BacklightCommand) throws {
  #expect(try BacklightCommandParser.parse(arguments) == expected)
}

@Test(
  arguments: [
    (["read", "extra"], BacklightToolError.unexpectedArgument("extra")),
    (["on", "--json"], .unexpectedArgument("--json")),
    (["off", "--receiver", "receiver-1"], .unexpectedArgument("--receiver")),
    (["keep", "--duration", "5"], .unexpectedArgument("--duration")),
    (["--json", "read"], .unexpectedArgument("--json")),
    (["--help", "read"], .unexpectedArgument("read")),
    (["manual", "7"], .unexpectedArgument("7")),
    (["manual", "--level", "7", "extra"], .unexpectedArgument("extra")),
    (["manual", "--level", "7", "--level", "6"], .duplicateOption("--level")),
  ]
)
func surplusOrUnsupportedArgumentFails(arguments: [String], expected: BacklightToolError) {
  #expect(throws: expected) {
    try BacklightCommandParser.parse(arguments)
  }
}

@Test(
  arguments: [
    ["manual"],
    ["manual", "--level"],
  ]
)
func missingManualLevelFails(arguments: [String]) {
  #expect(throws: BacklightToolError.missingLevelValue) {
    try BacklightCommandParser.parse(arguments)
  }
}

@Test(arguments: ["0", "8", "-1", "abc", "256"])
func invalidManualLevelFails(value: String) {
  #expect(throws: BacklightToolError.invalidLevel(value)) {
    try BacklightCommandParser.parse(["manual", "--level", value])
  }
}

@Test func unknownCommandFails() {
  #expect(throws: BacklightToolError.unsupportedCommand("status")) {
    try BacklightCommandParser.parse(["status"])
  }
}

@MainActor
@Test(
  arguments: [
    ["off", "--json"],
    ["keep", "--duration", "5"],
    ["manual", "--level", "7", "extra"],
  ]
)
func invalidInvocationDoesNotConstructController(arguments: [String]) {
  var didConstructController = false

  do {
    try executeInvocation(arguments) {
      didConstructController = true
      return MXLightkeeperController()
    }
    Issue.record("Expected invalid invocation to fail")
  } catch is BacklightToolError {
    // Expected parser failure.
  } catch {
    Issue.record("Unexpected error: \(error)")
  }

  #expect(!didConstructController)
}
