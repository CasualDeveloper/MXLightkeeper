import Foundation
import IOKit.hid

public enum HIDReceiverServiceError: Error, LocalizedError, Sendable {
  case managerOpenFailed(IOReturn)
  case deviceOpenFailed(IOReturn)
  case reportWriteFailed(IOReturn)
  case unsupportedPayload

  public var errorDescription: String? {
    switch self {
    case .managerOpenFailed(let code):
      return "Failed to open IOHID manager (\(code))"
    case .deviceOpenFailed(let code):
      return "Failed to open matched HID device (\(code))"
    case .reportWriteFailed(let code):
      return "Failed to write HID report (\(code))"
    case .unsupportedPayload:
      return "Refusing to write an empty HID payload"
    }
  }
}

public struct HIDReceiverMatch: Sendable, Equatable {
  public let matcher: ReceiverMatcher
  public let snapshot: ReceiverSnapshot

  public init(matcher: ReceiverMatcher, snapshot: ReceiverSnapshot) {
    self.matcher = matcher
    self.snapshot = snapshot
  }
}

public struct HIDReceiverTarget {
  public let device: IOHIDDevice
  public let match: HIDReceiverMatch

  public init(device: IOHIDDevice, match: HIDReceiverMatch) {
    self.device = device
    self.match = match
  }
}

public protocol ReceiverEnumerating: Sendable {
  func listReceivers() throws -> [HIDReceiverMatch]
}

public protocol ReceiverWriting: Sendable {
  func sendOutputReport(
    _ payload: Data,
    to snapshot: ReceiverSnapshot
  ) throws
}

public struct HIDReceiverService: ReceiverEnumerating, ReceiverWriting {
  public init() {}

  private static func matchingDictionaries() -> [[String: Any]] {
    ReceiverCatalog.allMatchers.map { matcher in
      [
        kIOHIDVendorIDKey: matcher.vendorID,
        kIOHIDProductIDKey: matcher.productID,
        kIOHIDPrimaryUsagePageKey: matcher.usagePage,
        kIOHIDPrimaryUsageKey: matcher.usage,
      ]
    }
  }

  private static func configureManager(_ manager: IOHIDManager) {
    let matchingArray = matchingDictionaries()
    IOHIDManagerSetDeviceMatchingMultiple(manager, matchingArray as CFArray)
  }

  public static func firstMatchedDevice() throws -> HIDReceiverTarget {
    let manager = IOHIDManagerCreate(kCFAllocatorDefault, IOOptionBits(kIOHIDOptionsTypeNone))
    configureManager(manager)

    let openResult = IOHIDManagerOpen(manager, IOOptionBits(kIOHIDOptionsTypeNone))
    guard openResult == kIOReturnSuccess else {
      throw HIDReceiverServiceError.managerOpenFailed(openResult)
    }
    defer { IOHIDManagerClose(manager, IOOptionBits(kIOHIDOptionsTypeNone)) }

    guard let devices = IOHIDManagerCopyDevices(manager) as? Set<IOHIDDevice> else {
      throw HIDReceiverServiceError.deviceOpenFailed(kIOReturnNotFound)
    }

    let matches = devices.compactMap { device -> HIDReceiverTarget? in
      guard let snapshot = snapshot(for: device) else {
        return nil
      }

      guard let matcher = ReceiverCatalog.allMatchers.first(where: { $0.matches(snapshot) }) else {
        return nil
      }

      return HIDReceiverTarget(
        device: device,
        match: HIDReceiverMatch(matcher: matcher, snapshot: snapshot)
      )
    }
    .sorted { lhs, rhs in
      if lhs.match.matcher.experimental != rhs.match.matcher.experimental {
        return lhs.match.matcher.experimental == false
      }

      return lhs.match.snapshot.locationID < rhs.match.snapshot.locationID
    }

    guard let firstMatch = matches.first else {
      throw HIDReceiverServiceError.deviceOpenFailed(kIOReturnNotFound)
    }

    return firstMatch
  }

  public func listReceivers() throws -> [HIDReceiverMatch] {
    let manager = IOHIDManagerCreate(kCFAllocatorDefault, IOOptionBits(kIOHIDOptionsTypeNone))
    Self.configureManager(manager)

    let openResult = IOHIDManagerOpen(manager, IOOptionBits(kIOHIDOptionsTypeNone))
    guard openResult == kIOReturnSuccess else {
      throw HIDReceiverServiceError.managerOpenFailed(openResult)
    }
    defer { IOHIDManagerClose(manager, IOOptionBits(kIOHIDOptionsTypeNone)) }

    guard let devices = IOHIDManagerCopyDevices(manager) as? Set<IOHIDDevice> else {
      return []
    }

    return devices.compactMap { device in
      guard let snapshot = Self.snapshot(for: device) else {
        return nil
      }

      guard let matcher = ReceiverCatalog.allMatchers.first(where: { $0.matches(snapshot) }) else {
        return nil
      }

      return HIDReceiverMatch(matcher: matcher, snapshot: snapshot)
    }
    .sorted { lhs, rhs in
      if lhs.matcher.experimental != rhs.matcher.experimental {
        return lhs.matcher.experimental == false
      }

      return lhs.snapshot.locationID < rhs.snapshot.locationID
    }
  }

  public func sendOutputReport(
    _ payload: Data,
    to snapshot: ReceiverSnapshot
  ) throws {
    guard !payload.isEmpty else {
      throw HIDReceiverServiceError.unsupportedPayload
    }

    let manager = IOHIDManagerCreate(kCFAllocatorDefault, IOOptionBits(kIOHIDOptionsTypeNone))
    Self.configureManager(manager)

    let openResult = IOHIDManagerOpen(manager, IOOptionBits(kIOHIDOptionsTypeNone))
    guard openResult == kIOReturnSuccess else {
      throw HIDReceiverServiceError.managerOpenFailed(openResult)
    }
    defer { IOHIDManagerClose(manager, IOOptionBits(kIOHIDOptionsTypeNone)) }

    guard let devices = IOHIDManagerCopyDevices(manager) as? Set<IOHIDDevice> else {
      throw HIDReceiverServiceError.deviceOpenFailed(kIOReturnNotFound)
    }

    guard ReceiverCatalog.allMatchers.contains(where: { $0.matches(snapshot) }) else {
      throw HIDReceiverServiceError.deviceOpenFailed(kIOReturnNotFound)
    }

    guard let device = devices.first(where: { device in
      guard let candidate = Self.snapshot(for: device) else {
        return false
      }

      return candidate == snapshot
    }) else {
      throw HIDReceiverServiceError.deviceOpenFailed(kIOReturnNotFound)
    }

    let deviceOpenResult = IOHIDDeviceOpen(device, IOOptionBits(kIOHIDOptionsTypeNone))
    guard deviceOpenResult == kIOReturnSuccess else {
      throw HIDReceiverServiceError.deviceOpenFailed(deviceOpenResult)
    }
    defer { IOHIDDeviceClose(device, IOOptionBits(kIOHIDOptionsTypeNone)) }

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
      throw HIDReceiverServiceError.reportWriteFailed(writeResult)
    }
  }

  public static func snapshot(for device: IOHIDDevice) -> ReceiverSnapshot? {
    guard
      let vendorID = property(kIOHIDVendorIDKey as CFString, from: device),
      let productID = property(kIOHIDProductIDKey as CFString, from: device),
      let usagePage = property(kIOHIDPrimaryUsagePageKey as CFString, from: device),
      let usage = property(kIOHIDPrimaryUsageKey as CFString, from: device)
    else {
      return nil
    }

    let productName = stringProperty(kIOHIDProductKey as CFString, from: device) ?? "Unknown HID Device"
    let transport = stringProperty(kIOHIDTransportKey as CFString, from: device) ?? "Unknown"
    let locationID = uint32Property(kIOHIDLocationIDKey as CFString, from: device) ?? 0
    let maxInputReportSize = property(kIOHIDMaxInputReportSizeKey as CFString, from: device) ?? 0
    let maxOutputReportSize = property(kIOHIDMaxOutputReportSizeKey as CFString, from: device) ?? 0
    let maxFeatureReportSize = property(kIOHIDMaxFeatureReportSizeKey as CFString, from: device) ?? 0
    let reportDescriptorLength = dataProperty(kIOHIDReportDescriptorKey as CFString, from: device)?.count ?? 0

    return ReceiverSnapshot(
      vendorID: vendorID,
      productID: productID,
      usagePage: usagePage,
      usage: usage,
      productName: productName,
      transport: transport,
      locationID: locationID,
      maxInputReportSize: maxInputReportSize,
      maxOutputReportSize: maxOutputReportSize,
      maxFeatureReportSize: maxFeatureReportSize,
      reportDescriptorLength: reportDescriptorLength
    )
  }

  private static func property(_ key: CFString, from device: IOHIDDevice) -> Int? {
    (IOHIDDeviceGetProperty(device, key) as? NSNumber)?.intValue
  }

  private static func uint32Property(_ key: CFString, from device: IOHIDDevice) -> UInt32? {
    (IOHIDDeviceGetProperty(device, key) as? NSNumber)?.uint32Value
  }

  private static func stringProperty(_ key: CFString, from device: IOHIDDevice) -> String? {
    IOHIDDeviceGetProperty(device, key) as? String
  }

  private static func dataProperty(_ key: CFString, from device: IOHIDDevice) -> Data? {
    IOHIDDeviceGetProperty(device, key) as? Data
  }
}
