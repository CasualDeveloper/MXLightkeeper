@testable import MXLightkeeperCore
import Testing

@Test func keepAliveRequestEnablesBacklightAndPreservesDurations() {
  let state = Backlight2State(
    enabled: 0x00,
    options: 0x18,
    supported: 0x7f,
    effects: 0x1234,
    level: 0,
    durationHandsOut: 0x000b,
    durationHandsIn: 0x000d,
    durationPowered: 0x003c
  )

  let request = Backlight2Codec.keepAliveRequest(from: state)

  #expect(request.reportID == HIDPPReport.longReportID)
  #expect(request.functionID == Backlight2Codec.writeFunctionID)
  #expect(request.parameters == [0x01, 0x18, 0xff, 0x01, 0x0b, 0x00, 0x0d, 0x00, 0x3c, 0x00])
  #expect(request.serializedData.count == HIDPPReport.longSize)
  #expect(Array(request.serializedData.suffix(6)) == [0, 0, 0, 0, 0, 0])
}

@Test func keepAliveRequestLeavesAutomaticModesWithZeroLevelPayload() {
  let state = Backlight2State(
    enabled: 0x00,
    options: 0x00,
    supported: 0x7f,
    effects: 0x1234,
    level: 7,
    durationHandsOut: 0x000b,
    durationHandsIn: 0x000d,
    durationPowered: 0x003c
  )

  let request = Backlight2Codec.keepAliveRequest(from: state)

  #expect(request.parameters[0] == 0x01)
  #expect(request.parameters[3] == 0x00)
}
