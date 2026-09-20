import Dispatch
import Foundation
import MXLightkeeperCore

enum BacklightToolError: LocalizedError, Equatable {
  case invalidLevel(String)
  case unsupportedCommand(String)
  case missingLevelValue
  case duplicateOption(String)
  case unexpectedArgument(String)

  var errorDescription: String? {
    switch self {
    case .invalidLevel(let value):
      return "Invalid brightness level '\(value)'. Expected a value from 1 to 7."
    case .unsupportedCommand(let value):
      return "Unknown subcommand '\(value)'. Run 'mxlightkeeper --help' to see available commands."
    case .missingLevelValue:
      return "Missing value for '--level'. Example: 'mxlightkeeper manual --level 7'"
    case .duplicateOption(let value):
      return "Option '\(value)' may only be provided once."
    case .unexpectedArgument(let value):
      return "Unexpected argument '\(value)'. Run 'mxlightkeeper --help' to see valid usage."
    }
  }
}

enum BacklightCommand: Equatable {
  case help
  case read
  case on
  case off
  case manual(level: UInt8)
  case keep
}

enum BacklightCommandParser {
  static func parse(_ arguments: [String]) throws -> BacklightCommand {
    guard let command = arguments.first else {
      return .help
    }

    if command == "-h" || command == "--help" {
      guard arguments.count == 1 else {
        throw BacklightToolError.unexpectedArgument(arguments[1])
      }
      return .help
    }

    switch command {
    case "read":
      try requireNoArguments(in: arguments)
      return .read
    case "on":
      try requireNoArguments(in: arguments)
      return .on
    case "off":
      try requireNoArguments(in: arguments)
      return .off
    case "keep":
      try requireNoArguments(in: arguments)
      return .keep
    case "manual":
      return try parseManual(arguments)
    default:
      if command.hasPrefix("-") {
        throw BacklightToolError.unexpectedArgument(command)
      }
      throw BacklightToolError.unsupportedCommand(command)
    }
  }

  private static func requireNoArguments(in arguments: [String]) throws {
    guard arguments.count == 1 else {
      throw BacklightToolError.unexpectedArgument(arguments[1])
    }
  }

  private static func parseManual(_ arguments: [String]) throws -> BacklightCommand {
    let levelOption = "--level"
    if arguments.filter({ $0 == levelOption }).count > 1 {
      throw BacklightToolError.duplicateOption(levelOption)
    }

    guard arguments.count > 1 else {
      throw BacklightToolError.missingLevelValue
    }
    guard arguments[1] == levelOption else {
      throw BacklightToolError.unexpectedArgument(arguments[1])
    }
    guard arguments.count > 2 else {
      throw BacklightToolError.missingLevelValue
    }
    guard arguments.count == 3 else {
      throw BacklightToolError.unexpectedArgument(arguments[3])
    }

    let value = arguments[2]
    guard let level = UInt8(value), (1...7).contains(level) else {
      throw BacklightToolError.invalidLevel(value)
    }
    return .manual(level: level)
  }
}

func printUsage(to stream: UnsafeMutablePointer<FILE> = stdout) {
  fputs("""
    mxlightkeeper — Logitech MX Keys backlight control.

    Usage:
      mxlightkeeper <command> [options]

    Commands:
      read                         Print the current BACKLIGHT2 state
      on                           Turn the backlight on
      off                          Turn the backlight off
      manual --level <1-7>         Set manual brightness level
      keep                         Keep the backlight on until interrupted

    Examples:
      mxlightkeeper read
      mxlightkeeper on
      mxlightkeeper manual --level 7
      mxlightkeeper keep

    Options:
      -h, --help                   Show this help message

    Receiver support:
      Verified on MX Keys for Mac over a Logitech Unifying receiver.
      Bolt receivers and other MX Keys variants are supported as alpha paths
      until confirmed on real hardware.
    """, stream)
}

func fail(_ message: String, code: Int32 = 1) -> Never {
  fputs("Error: \(message)\n", stderr)
  exit(code)
}

@MainActor
func runKeepCommand(with controller: MXLightkeeperController) throws {
  let runtimeState = try controller.prepareRuntimeState()
  try runtimeState.keeper.start()

  let alphaSuffix = runtimeState.receiver.matcher.experimental ? " (alpha)" : ""
  print("Keeping backlight on via \(runtimeState.receiver.matcher.kind.displayName) receiver\(alphaSuffix).")
  print("Writing keep-alive every \(KeepAliveProtocol.keepAliveIntervalSeconds)s. Press Ctrl-C to stop.")

  signal(SIGINT, SIG_IGN)
  let signalSource = DispatchSource.makeSignalSource(signal: SIGINT, queue: .main)
  signalSource.setEventHandler {
    Task { @MainActor in
      runtimeState.keeper.stop()
      print("\nStopped.")
      exit(0)
    }
  }
  signalSource.resume()

  RunLoop.main.run()
}

@MainActor
func runCommand(
  _ command: BacklightCommand,
  controller: MXLightkeeperController
) throws {
  switch command {
  case .help:
    printUsage()

  case .read:
    print(try controller.readBacklightState().summary)

  case .on:
    print(try controller.setBacklightEnabled(true).summary)

  case .off:
    print(try controller.setBacklightEnabled(false).summary)

  case .manual(let level):
    print(try controller.setManualLevel(level).summary)

  case .keep:
    try runKeepCommand(with: controller)
  }
}

@MainActor
func executeInvocation(
  _ arguments: [String],
  makeController: () -> MXLightkeeperController = { MXLightkeeperController() }
) throws {
  let command = try BacklightCommandParser.parse(arguments)
  if command == .help {
    printUsage()
    return
  }

  try runCommand(command, controller: makeController())
}

@main
struct MXLightkeeperCLI {
  @MainActor
  static func main() {
    do {
      try executeInvocation(Array(CommandLine.arguments.dropFirst()))
    } catch {
      fail(error.localizedDescription)
    }
  }
}
