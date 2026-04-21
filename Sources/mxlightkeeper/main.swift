import Dispatch
import Foundation
import MXLightkeeperCore

enum BacklightToolError: LocalizedError {
  case invalidLevel(String)
  case unsupportedCommand(String)
  case stateDecodeFailed

  var errorDescription: String? {
    switch self {
    case .invalidLevel(let value):
      return "Invalid level: \(value). Expected 0-255."
    case .unsupportedCommand(let value):
      return "Unsupported command: \(value). Run without arguments to see usage."
    case .stateDecodeFailed:
      return "Failed to decode BACKLIGHT2 state from the receiver response"
    }
  }
}

func usage() {
  print("""
    mxlightkeeper — Logitech MX Keys backlight control.

    Usage:
      mxlightkeeper read                   Print current backlight state
      mxlightkeeper on                     Turn the backlight on
      mxlightkeeper off                    Turn the backlight off
      mxlightkeeper manual --level N       Set manual brightness level (1-7)
      mxlightkeeper keep                   Keep the backlight on until interrupted

    Matches Logitech Unifying receivers. Bolt support is present but alpha quality
    (verified via protocol inference, not on real hardware).
    """)
}

@MainActor
func readCurrentState(with session: HIDPPProbeSession) throws -> Backlight2State {
  let response = try session.sendRequest(Backlight2Codec.readRequest(), timeout: 1.0)
  guard let state = Backlight2Codec.decodeState(from: response) else {
    throw BacklightToolError.stateDecodeFailed
  }
  return state
}

@MainActor
func writeEnabled(_ enabled: Bool, level: UInt8?, mode: UInt8?, with session: HIDPPProbeSession, from current: Backlight2State) throws {
  var options = current.options
  if let mode {
    options = (options & ~0x18) | ((mode & 0x03) << 3)
  }

  let newState = Backlight2State(
    enabled: enabled ? 0x01 : 0x00,
    options: options,
    supported: current.supported,
    effects: current.effects,
    level: level ?? current.level,
    durationHandsOut: current.durationHandsOut,
    durationHandsIn: current.durationHandsIn,
    durationPowered: current.durationPowered
  )

  _ = try session.sendRequest(Backlight2Codec.writeRequest(from: newState), timeout: 1.0)
}

let arguments = Array(CommandLine.arguments.dropFirst())
let nonFlagArguments = arguments.filter { !$0.hasPrefix("--") }

guard let command = nonFlagArguments.first else {
  usage()
  exit(0)
}

let target: HIDReceiverTarget
do {
  target = try HIDReceiverService.firstMatchedDevice()
} catch {
  fputs("Failed to find a matched Logitech receiver: \(error.localizedDescription)\n", stderr)
  exit(1)
}

if command == "keep" {
  let receiverService = HIDReceiverService()
  let snapshot = target.match.snapshot
  let intervalSeconds = TimeInterval(KeepAliveProtocol.keepAliveIntervalSeconds)

  let alphaSuffix = target.match.matcher.experimental ? " (alpha)" : ""
  print("Keeping backlight on via \(target.match.matcher.kind.displayName) receiver\(alphaSuffix).")
  print("Writing keep-alive every \(Int(intervalSeconds))s. Press Ctrl-C to stop.")

  signal(SIGINT, SIG_IGN)
  let signalSource = DispatchSource.makeSignalSource(signal: SIGINT, queue: .main)
  signalSource.setEventHandler {
    print("\nStopped.")
    exit(0)
  }
  signalSource.resume()

  Task.detached {
    while !Task.isCancelled {
      do {
        try receiverService.sendOutputReport(
          KeepAliveProtocol.onSignal,
          to: snapshot
        )
      } catch {
        fputs("Write failed: \(error.localizedDescription)\n", stderr)
      }
      try? await Task.sleep(nanoseconds: UInt64(intervalSeconds * 1_000_000_000))
    }
  }

  RunLoop.main.run()
}

let session: HIDPPProbeSession
do {
  session = try HIDPPProbeSession(target: target)
} catch {
  fputs("Failed to open BACKLIGHT2 session: \(error.localizedDescription)\n", stderr)
  exit(1)
}

defer { session.close() }

do {
  let current = try readCurrentState(with: session)

  switch command {
  case "read":
    print(current.summary)
    exit(0)

  case "on":
    try writeEnabled(true, level: max(current.level, 1), mode: nil, with: session, from: current)

  case "off":
    try writeEnabled(false, level: nil, mode: nil, with: session, from: current)

  case "manual":
    guard let levelIndex = arguments.firstIndex(of: "--level"), arguments.indices.contains(levelIndex + 1) else {
      throw BacklightToolError.invalidLevel("")
    }
    guard let level = UInt8(arguments[levelIndex + 1]) else {
      throw BacklightToolError.invalidLevel(arguments[levelIndex + 1])
    }

    try writeEnabled(true, level: level, mode: 0x03, with: session, from: current)

  default:
    throw BacklightToolError.unsupportedCommand(command)
  }

  let updated = try readCurrentState(with: session)
  print(updated.summary)
} catch {
  fputs("\(error.localizedDescription)\n", stderr)
  exit(1)
}
