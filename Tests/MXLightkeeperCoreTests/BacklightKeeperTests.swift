@testable import MXLightkeeperCore
import Foundation
import Testing

@MainActor
@Test func keepAliveOwnershipBlocksConcurrentKeepers() throws {
  let lockURL = FileManager.default.temporaryDirectory
    .appendingPathComponent(UUID().uuidString, isDirectory: true)
    .appendingPathComponent("keepalive.lock", isDirectory: false)
  let snapshot = ReceiverSnapshot(
    vendorID: 0x046d,
    productID: 0xc52b,
    usagePage: 0xFF00,
    usage: 1,
    productName: "USB Receiver",
    transport: "USB"
  )

  let firstKeeper = BacklightKeeper(snapshot: snapshot, lockURL: lockURL)
  try firstKeeper.start()
  defer { firstKeeper.stop() }

  let secondKeeper = BacklightKeeper(snapshot: snapshot, lockURL: lockURL)

  do {
    try secondKeeper.start()
    Issue.record("Expected the second keeper to fail while the first one owns the lock")
  } catch let error as BacklightKeeperError {
    #expect(error == .alreadyRunning)
  }
}

@MainActor
@Test func stoppingKeeperReleasesOwnership() throws {
  let lockURL = FileManager.default.temporaryDirectory
    .appendingPathComponent(UUID().uuidString, isDirectory: true)
    .appendingPathComponent("keepalive.lock", isDirectory: false)
  let snapshot = ReceiverSnapshot(
    vendorID: 0x046d,
    productID: 0xc52b,
    usagePage: 0xFF00,
    usage: 1,
    productName: "USB Receiver",
    transport: "USB"
  )

  let firstKeeper = BacklightKeeper(snapshot: snapshot, lockURL: lockURL)
  try firstKeeper.start()
  firstKeeper.stop()

  let secondKeeper = BacklightKeeper(snapshot: snapshot, lockURL: lockURL)
  try secondKeeper.start()
  #expect(secondKeeper.isRunning)
  secondKeeper.stop()
}

@MainActor
@Test func manualLevelValidationFailsBeforeHardwareAccess() throws {
  let controller = MXLightkeeperController()

  do {
    _ = try controller.setManualLevel(9)
    Issue.record("Expected setManualLevel to reject out-of-range values")
  } catch let error as MXLightkeeperControllerError {
    #expect(error == .invalidManualLevel(9))
  }
}
