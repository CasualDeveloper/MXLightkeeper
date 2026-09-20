import Dispatch
import Foundation
@preconcurrency import IOKit.hid

public enum HIDPPProbeError: Error, LocalizedError, Sendable {
  case receiverOpenFailed(IOReturn)
  case reportWriteFailed(IOReturn)
  case featureCallFailed(request: HIDPPReport, response: HIDPPErrorReply)
  case noMatchingResponse

  public var errorDescription: String? {
    switch self {
    case .receiverOpenFailed(let code):
      return "Failed to open matched receiver: \(code)"
    case .reportWriteFailed(let code):
      return "Failed to write HID++ report: \(code)"
    case .featureCallFailed(let request, let response):
      let feature = String(format: "%02x", request.featureIndex)
      let function = String(format: "%x", request.functionID)
      let code = String(format: "%02x", response.code)
      return "HID++ feature 0x\(feature) function 0x\(function) failed with error 0x\(code)"
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
  private let softwareIDAllocator: HIDPPSoftwareIDAllocator
  private let context: Context
  private let retainedContext: Unmanaged<Context>
  private var isClosed = false

  public convenience init(target: HIDReceiverTarget) throws {
    try self.init(target: target, softwareIDAllocator: HIDPPSoftwareIDAllocator())
  }

  init(target: HIDReceiverTarget, softwareIDAllocator: HIDPPSoftwareIDAllocator) throws {
    device = target.device
    snapshot = target.match.snapshot
    self.softwareIDAllocator = softwareIDAllocator

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

    let wireRequest = request.assigningSoftwareID(softwareIDAllocator.next())
    let payload = wireRequest.serializedData
    let writeResult = payload.withUnsafeBytes { rawBuffer -> IOReturn in
      let pointer = rawBuffer.bindMemory(to: UInt8.self).baseAddress!
      return IOHIDDeviceSetReport(
        device,
        kIOHIDReportTypeOutput,
        CFIndex(wireRequest.reportID),
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
      if let match = try HIDPPResponseResolver.resolve(in: context.reports, to: wireRequest) {
        return match
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

enum HIDPPResponseResolver {
  static func resolve(
    in reports: [HIDPPReport],
    to request: HIDPPReport
  ) throws -> HIDPPReport? {
    guard let response = reports.first(where: { $0.matchesResponse(to: request) }) else {
      return nil
    }

    if let errorReply = response.errorReply {
      throw HIDPPProbeError.featureCallFailed(request: request, response: errorReply)
    }

    return response
  }
}
