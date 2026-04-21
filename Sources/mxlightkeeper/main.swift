import Dispatch
import Foundation
import MXLightkeeperCore

enum BacklightToolError: LocalizedError {
  case invalidLevel(String)
  case unsupportedCommand(String)
  case missingLevelValue

  var errorDescription: String? {
    switch self {
    case .invalidLevel(let value):
      return "Invalid brightness level '\(value)'. Expected a value from 1 to 7."
    case .unsupportedCommand(let value):
      return "Unknown subcommand '\(value)'. Run 'mxlightkeeper --help' to see available commands."
    case .missingLevelValue:
      return "Missing value for '--level'. Example: 'mxlightkeeper manual --level 7'"
    }
  }
}

let validCommands: Set<String> = ["read", "on", "off", "manual", "keep"]

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
  let receiver = try controller.firstMatchedReceiver()
  let keeper = try controller.makeKeeper()
  try keeper.start()

  let alphaSuffix = receiver.matcher.experimental ? " (alpha)" : ""
  print("Keeping backlight on via \(receiver.matcher.kind.displayName) receiver\(alphaSuffix).")
  print("Writing keep-alive every \(KeepAliveProtocol.keepAliveIntervalSeconds)s. Press Ctrl-C to stop.")

  signal(SIGINT, SIG_IGN)
  let signalSource = DispatchSource.makeSignalSource(signal: SIGINT, queue: .main)
  signalSource.setEventHandler {
    Task { @MainActor in
      keeper.stop()
      print("\nStopped.")
      exit(0)
    }
  }
  signalSource.resume()

  RunLoop.main.run()
}

@MainActor
func runCommand(
  _ command: String,
  arguments: [String],
  controller: MXLightkeeperController
) throws {
  switch command {
  case "read":
    print(try controller.readBacklightState().summary)

  case "on":
    print(try controller.setBacklightEnabled(true).summary)

  case "off":
    print(try controller.setBacklightEnabled(false).summary)

  case "manual":
    guard let levelIndex = arguments.firstIndex(of: "--level"), arguments.indices.contains(levelIndex + 1) else {
      throw BacklightToolError.missingLevelValue
    }
    guard let level = UInt8(arguments[levelIndex + 1]) else {
      throw BacklightToolError.invalidLevel(arguments[levelIndex + 1])
    }

    print(try controller.setManualLevel(level).summary)

  case "keep":
    try runKeepCommand(with: controller)

  default:
    throw BacklightToolError.unsupportedCommand(command)
  }
}

let arguments = Array(CommandLine.arguments.dropFirst())
if arguments.contains("-h") || arguments.contains("--help") {
  printUsage()
  exit(0)
}

let nonFlagArguments = arguments.filter { !$0.hasPrefix("--") }

guard let command = nonFlagArguments.first else {
  printUsage()
  exit(0)
}

guard validCommands.contains(command) else {
  fail(BacklightToolError.unsupportedCommand(command).localizedDescription)
}

let controller = MXLightkeeperController()

do {
  try runCommand(command, arguments: arguments, controller: controller)
} catch {
  fail(error.localizedDescription)
}
