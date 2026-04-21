import MXLightkeeperCore
import Testing

@Test func shippingMatchersExcludeExperimentalBoltByDefault() {
  #expect(ReceiverCatalog.enabledMatchers(includeExperimentalBolt: false) == [ReceiverCatalog.unifying])
}

@Test func matcherRequiresExactVendorProductUsagePageAndUsage() {
  let snapshot = ReceiverSnapshot(
    vendorID: 0x046d,
    productID: 0xc52b,
    usagePage: 0xFF00,
    usage: 1,
    productName: "USB Receiver",
    transport: "USB",
    locationID: 0x1420_0000,
    maxInputReportSize: 32,
    maxOutputReportSize: 32,
    maxFeatureReportSize: 1,
    reportDescriptorLength: 98
  )

  #expect(ReceiverCatalog.unifying.matches(snapshot))
  #expect(!ReceiverCatalog.bolt.matches(snapshot))
}
