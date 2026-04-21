import Foundation

@MainActor
public final class BacklightKeeper {
  private let receiverService = HIDReceiverService()
  private let snapshot: ReceiverSnapshot
  private let refreshIntervalNanoseconds: UInt64
  private var keepAliveTask: Task<Void, Never>?
  private var isClosed = false

  public private(set) var isRunning = false

  public init(
    target: HIDReceiverTarget,
    refreshIntervalSeconds: TimeInterval = TimeInterval(KeepAliveProtocol.keepAliveIntervalSeconds)
  ) throws {
    snapshot = target.match.snapshot
    refreshIntervalNanoseconds = UInt64(refreshIntervalSeconds * 1_000_000_000)
  }

  public func close() {
    guard !isClosed else {
      return
    }

    keepAliveTask?.cancel()
    keepAliveTask = nil
    isClosed = true
  }

  public func start() {
    guard !isRunning else {
      return
    }

    keepAliveTask?.cancel()
    keepAliveTask = Task.detached { [receiverService, snapshot, refreshIntervalNanoseconds] in
      while !Task.isCancelled {
        try? receiverService.sendOutputReport(KeepAliveProtocol.onSignal, to: snapshot)
        try? await Task.sleep(nanoseconds: refreshIntervalNanoseconds)
      }
    }

    isRunning = true
  }

  public func stop() {
    keepAliveTask?.cancel()
    keepAliveTask = nil
    isRunning = false
  }
}
