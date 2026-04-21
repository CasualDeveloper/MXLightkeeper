import Foundation

public enum ReceiverKind: String, CaseIterable, Sendable {
  case unifying
  case bolt

  public var displayName: String {
    switch self {
    case .unifying:
      return "Logitech Unifying"
    case .bolt:
      return "Logitech Bolt"
    }
  }
}

public struct ReceiverSnapshot: Sendable, Equatable {
  public let vendorID: Int
  public let productID: Int
  public let usagePage: Int
  public let usage: Int
  public let productName: String
  public let transport: String
  public let locationID: UInt32
  public let maxInputReportSize: Int
  public let maxOutputReportSize: Int
  public let maxFeatureReportSize: Int
  public let reportDescriptorLength: Int

  public init(
    vendorID: Int,
    productID: Int,
    usagePage: Int,
    usage: Int,
    productName: String,
    transport: String,
    locationID: UInt32 = 0,
    maxInputReportSize: Int = 0,
    maxOutputReportSize: Int = 0,
    maxFeatureReportSize: Int = 0,
    reportDescriptorLength: Int = 0
  ) {
    self.vendorID = vendorID
    self.productID = productID
    self.usagePage = usagePage
    self.usage = usage
    self.productName = productName
    self.transport = transport
    self.locationID = locationID
    self.maxInputReportSize = maxInputReportSize
    self.maxOutputReportSize = maxOutputReportSize
    self.maxFeatureReportSize = maxFeatureReportSize
    self.reportDescriptorLength = reportDescriptorLength
  }

  public var shortIdentifier: String {
    String(format: "0x%04x:0x%04x", vendorID, productID)
  }

  public var locationIdentifier: String {
    String(format: "0x%08x", locationID)
  }
}

public struct ReceiverMatcher: Sendable, Equatable {
  public let kind: ReceiverKind
  public let vendorID: Int
  public let productID: Int
  public let usagePage: Int
  public let usage: Int
  public let productName: String
  public let experimental: Bool

  public init(
    kind: ReceiverKind,
    vendorID: Int,
    productID: Int,
    usagePage: Int,
    usage: Int,
    productName: String,
    experimental: Bool
  ) {
    self.kind = kind
    self.vendorID = vendorID
    self.productID = productID
    self.usagePage = usagePage
    self.usage = usage
    self.productName = productName
    self.experimental = experimental
  }

  public func matches(_ snapshot: ReceiverSnapshot) -> Bool {
    snapshot.vendorID == vendorID &&
      snapshot.productID == productID &&
      snapshot.usagePage == usagePage &&
      snapshot.usage == usage
  }
}

public enum ReceiverCatalog {
  public static let unifying = ReceiverMatcher(
    kind: .unifying,
    vendorID: 0x046d,
    productID: 0xc52b,
    usagePage: 0xFF00,
    usage: 1,
    productName: "USB Receiver",
    experimental: false
  )

  public static let bolt = ReceiverMatcher(
    kind: .bolt,
    vendorID: 0x046d,
    productID: 0xc548,
    usagePage: 0xFF00,
    usage: 1,
    productName: "Logitech USB Input Device",
    experimental: true
  )

  public static let allMatchers: [ReceiverMatcher] = [unifying, bolt]
}
