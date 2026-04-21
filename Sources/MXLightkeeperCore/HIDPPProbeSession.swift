import Dispatch
import Foundation
@preconcurrency import IOKit.hid

public enum HIDPPProbeError: Error, LocalizedError, Sendable {
  case receiverOpenFailed(IOReturn)
  case reportWriteFailed(IOReturn)
  case noMatchingResponse

  public var errorDescription: String? {
    switch self {
    case .receiverOpenFailed(let code):
      return "Failed to open matched receiver: \(code)"
    case .reportWriteFailed(let code):
      return "Failed to write HID++ report: \(code)"
    case .noMatchingResponse:
      return "No matching HID++ response arrived before the timeout"
    }
  }
}

@MainActor
public final class HIDPPProbeSession {
  private final class Context {
    let buffer: UnsafeMutablePointer<UInt8>
    let bufferSize: Int
    var reports: [HIDPPReport] = []

    init(bufferSize: Int) {
      self.bufferSize = bufferSize
      buffer = .allocate(capacity: bufferSize)
      buffer.initialize(repeating: 0, count: bufferSize)
    }

    deinit {
      buffer.deinitialize(count: bufferSize)
      buffer.deallocate()
    }
  }

  private let device: IOHIDDevice
  public let snapshot: ReceiverSnapshot
  private let context: Context
  private let retainedContext: Unmanaged<Context>
  private var isClosed = false

  public init(target: HIDReceiverTarget) throws {
    device = target.device
    snapshot = target.match.snapshot

    let openResult = IOHIDDeviceOpen(device, IOOptionBits(kIOHIDOptionsTypeNone))
    guard openResult == kIOReturnSuccess else {
      throw HIDPPProbeError.receiverOpenFailed(openResult)
    }

    context = Context(bufferSize: max(snapshot.maxInputReportSize, 32))
    retainedContext = Unmanaged.passRetained(context)

    let callback: IOHIDReportCallback = { contextPointer, result, _, reportType, _, report, reportLength in
      guard result == kIOReturnSuccess, reportType == kIOHIDReportTypeInput else {
        return
      }

      let context = Unmanaged<Context>.fromOpaque(contextPointer!).takeUnretainedValue()
      let data = Data(bytes: report, count: reportLength)
      if let parsed = HIDPPReport.parse(data) {
        context.reports.append(parsed)
      }
    }

    IOHIDDeviceRegisterInputReportCallback(
      device,
      context.buffer,
      context.bufferSize,
      callback,
      retainedContext.toOpaque()
    )
    IOHIDDeviceScheduleWithRunLoop(device, CFRunLoopGetMain(), CFRunLoopMode.defaultMode.rawValue)
  }

  public func close() {
    guard !isClosed else {
      return
    }

    IOHIDDeviceUnscheduleFromRunLoop(device, CFRunLoopGetMain(), CFRunLoopMode.defaultMode.rawValue)
    IOHIDDeviceClose(device, IOOptionBits(kIOHIDOptionsTypeNone))
    retainedContext.release()
    isClosed = true
  }

  public func sendRequest(
    _ request: HIDPPReport,
    timeout: TimeInterval = 0.5
  ) throws -> HIDPPReport {
    context.reports.removeAll(keepingCapacity: true)

    let payload = request.serializedData
    let writeResult = payload.withUnsafeBytes { rawBuffer -> IOReturn in
      let pointer = rawBuffer.bindMemory(to: UInt8.self).baseAddress!
      return IOHIDDeviceSetReport(
        device,
        kIOHIDReportTypeOutput,
        CFIndex(request.reportID),
        pointer,
        payload.count
      )
    }

    guard writeResult == kIOReturnSuccess else {
      throw HIDPPProbeError.reportWriteFailed(writeResult)
    }

    let deadline = Date().addingTimeInterval(timeout)
    while Date() < deadline {
      RunLoop.main.run(mode: .default, before: deadline)
      if let match = context.reports.first(where: { report in
        report.deviceIndex == request.deviceIndex &&
          report.featureIndex == request.featureIndex &&
          report.functionID == request.functionID &&
          report.softwareID == request.softwareID
      }) {
        return match
      }

      if let errorReport = context.reports.first(where: { $0.isError && $0.softwareID == request.softwareID }) {
        return errorReport
      }
    }

    throw HIDPPProbeError.noMatchingResponse
  }

  public func sendRawOutputReport(_ payload: Data) throws {
    let reportID = CFIndex(payload.first ?? 0)
    let writeResult = payload.withUnsafeBytes { rawBuffer -> IOReturn in
      let pointer = rawBuffer.bindMemory(to: UInt8.self).baseAddress!
      return IOHIDDeviceSetReport(
        device,
        kIOHIDReportTypeOutput,
        reportID,
        pointer,
        payload.count
      )
    }

    guard writeResult == kIOReturnSuccess else {
      throw HIDPPProbeError.reportWriteFailed(writeResult)
    }
  }
}
