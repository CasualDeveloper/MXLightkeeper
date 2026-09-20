@testable import MXLightkeeperCore
import Foundation
import Testing

@Test func errorReplyDecodesEchoedRequestBytes() throws {
  let bytes = data("10 01 ff 0b 12 02 00")
  let report = try #require(HIDPPReport.parse(bytes))
  let error = try #require(report.errorReply)

  #expect(error.deviceIndex == 0x01)
  #expect(error.originalFeatureIndex == 0x0b)
  #expect(error.originalPackedFunctionAndSoftwareID == 0x12)
  #expect(error.originalFunctionID == 0x01)
  #expect(error.originalSoftwareID == 0x02)
  #expect(error.code == 0x02)
  #expect(error.rawData == bytes)
}

@Test func normalAndErrorResponsesMatchTransmittedRequest() throws {
  let request = structuredRequest(softwareID: 0x02)
  let normal = try #require(HIDPPReport.parse(data("10 01 0b 12 00 00 00")))
  let shortError = try #require(HIDPPReport.parse(data("10 01 ff 0b 12 02 00")))
  let longError = try #require(
    HIDPPReport.parse(data("11 01 ff 0b 12 02 00 00 00 00 00 00 00 00 00 00 00 00 00 00"))
  )

  #expect(normal.matchesResponse(to: request))
  #expect(shortError.matchesResponse(to: request))
  #expect(longError.matchesResponse(to: request))
}

@Test(
  arguments: [
    "10 02 ff 0b 12 02 00",
    "10 01 ff 1b 12 02 00",
    "10 01 ff 0b 22 02 00",
    "10 01 ff 0b 13 02 00",
    "10 01 0b 10 00 00 00",
    "10 01 0b 1f 00 00 00",
    "10 01 ff 0b 1f 02 00",
  ]
)
func unrelatedResponseDoesNotMatch(hex: String) throws {
  let response = try #require(HIDPPReport.parse(data(hex)))
  #expect(!response.matchesResponse(to: structuredRequest(softwareID: 0x02)))
}

@Test func rootFeatureErrorUsesEchoedPackedByte() throws {
  let request = HIDPPReport(
    reportID: HIDPPReport.shortReportID,
    deviceIndex: 0x01,
    featureIndex: 0x00,
    functionID: 0x00,
    softwareID: 0x04,
    parameters: [0x19, 0x82, 0x00]
  )
  let response = try #require(HIDPPReport.parse(data("10 01 ff 00 04 02 00")))

  #expect(response.matchesResponse(to: request))
  #expect(response.errorReply?.originalSoftwareID == 0x04)
}

@Test func orderedResolverThrowsFirstMatchingError() throws {
  let request = structuredRequest(softwareID: 0x02)
  let error = try #require(HIDPPReport.parse(data("10 01 ff 0b 12 02 00")))
  let normal = try #require(HIDPPReport.parse(data("10 01 0b 12 00 00 00")))

  do {
    _ = try HIDPPResponseResolver.resolve(in: [error, normal], to: request)
    Issue.record("Expected the first matching error to throw")
  } catch HIDPPProbeError.featureCallFailed(let failedRequest, let response) {
    #expect(failedRequest == request)
    #expect(response.code == 0x02)
  } catch {
    Issue.record("Unexpected error: \(error)")
  }
  #expect(try HIDPPResponseResolver.resolve(in: [normal, error], to: request) == normal)
}

@Test func resolverPreservesUnknownErrorCode() throws {
  let request = structuredRequest(softwareID: 0x02)
  let error = try #require(HIDPPReport.parse(data("10 01 ff 0b 12 e7 00")))

  do {
    _ = try HIDPPResponseResolver.resolve(in: [error], to: request)
    Issue.record("Expected unknown error code to throw")
  } catch HIDPPProbeError.featureCallFailed(_, let response) {
    #expect(response.code == 0xe7)
  } catch {
    Issue.record("Unexpected error: \(error)")
  }
}

@MainActor
@Test func softwareIDAllocatorUsesConservativePoolAndWraps() {
  let allocator = HIDPPSoftwareIDAllocator()
  let values = (0..<11).map { _ in allocator.next() }

  #expect(values == [0x01, 0x02, 0x03, 0x04, 0x05, 0x06, 0x08, 0x09, 0x0c, 0x0e, 0x01])
}

@Test func parserRequiresExactStandardFrameSize() {
  #expect(HIDPPReport.parse(data("10 01 0b 12 00 00")) == nil)
  #expect(HIDPPReport.parse(data("10 01 0b 12 00 00 00 00")) == nil)
  #expect(HIDPPReport.parse(data("12 01 0b 12 00 00 00")) == nil)
}

@Test func receivedBytesDoNotChangeReportValueEquality() throws {
  let parsed = try #require(HIDPPReport.parse(data("10 01 0b 12 00 00 00")))
  let constructed = HIDPPReport(
    reportID: 0x10,
    deviceIndex: 0x01,
    featureIndex: 0x0b,
    functionID: 0x01,
    softwareID: 0x02,
    parameters: [0x00, 0x00, 0x00]
  )

  #expect(parsed == constructed)
  #expect(parsed.rawData == data("10 01 0b 12 00 00 00"))
}

private func structuredRequest(softwareID: UInt8) -> HIDPPReport {
  HIDPPReport(
    reportID: HIDPPReport.longReportID,
    deviceIndex: 0x01,
    featureIndex: 0x0b,
    functionID: 0x01,
    softwareID: softwareID,
    parameters: [0x01, 0x18, 0xff, 0x05]
  )
}

private func data(_ hex: String) -> Data {
  Data(hex.split(separator: " ").compactMap { UInt8($0, radix: 16) })
}
