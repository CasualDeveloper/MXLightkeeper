import Darwin
import Foundation

public enum BacklightKeeperError: Error, LocalizedError, Sendable, Equatable {
  case alreadyRunning
  case lockSetupFailed(Int32)

  public var errorDescription: String? {
    switch self {
    case .alreadyRunning:
      return "Keep-alive is already running in another MXLightkeeper process"
    case .lockSetupFailed(let code):
      return "Failed to create the keep-alive lock (errno \(code))"
    }
  }
}

private final class KeepAliveOwnership {
  private let lockURL: URL
  private var isHeld = false

  init(lockURL: URL? = nil) {
    self.lockURL = lockURL ?? Self.defaultLockURL()
  }

  deinit {
    release()
  }

  func acquire() throws {
    guard !isHeld else {
      return
    }

    try Self.ensureParentDirectory(for: lockURL)
    if try createLockFile() {
      isHeld = true
      return
    }

    if try Self.removeStaleLockIfNeeded(at: lockURL), try createLockFile() {
      isHeld = true
      return
    }

    throw BacklightKeeperError.alreadyRunning
  }

  func release() {
    guard isHeld else {
      return
    }

    try? FileManager.default.removeItem(at: lockURL)
    isHeld = false
  }

  private func createLockFile() throws -> Bool {
    let descriptor = open(lockURL.path, O_WRONLY | O_CREAT | O_EXCL, S_IRUSR | S_IWUSR)
    if descriptor >= 0 {
      let metadata = "pid=\(getpid())\nstarted=\(Date().timeIntervalSince1970)\n"
      if let data = metadata.data(using: .utf8) {
        _ = data.withUnsafeBytes { rawBuffer in
          write(descriptor, rawBuffer.baseAddress, rawBuffer.count)
        }
      }
      close(descriptor)
      return true
    }

    let code = errno
    if code == EEXIST {
      return false
    }

    throw BacklightKeeperError.lockSetupFailed(code)
  }

  private static func defaultLockURL() -> URL {
    let baseURL = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
      ?? FileManager.default.temporaryDirectory
    return baseURL
      .appendingPathComponent("MXLightkeeper", isDirectory: true)
      .appendingPathComponent("keepalive.lock", isDirectory: false)
  }

  private static func ensureParentDirectory(for url: URL) throws {
    try FileManager.default.createDirectory(
      at: url.deletingLastPathComponent(),
      withIntermediateDirectories: true
    )
  }

  private static func removeStaleLockIfNeeded(at url: URL) throws -> Bool {
    guard let data = try? Data(contentsOf: url) else {
      return false
    }

    if data.isEmpty {
      try FileManager.default.removeItem(at: url)
      return true
    }

    guard
      let contents = String(data: data, encoding: .utf8),
      let pidLine = contents.split(separator: "\n").first(where: { $0.hasPrefix("pid=") }),
      let pid = pid_t(pidLine.dropFirst(4))
    else {
      return false
    }

    guard processIsRunning(pid) == false else {
      return false
    }

    try FileManager.default.removeItem(at: url)
    return true
  }

  private static func processIsRunning(_ pid: pid_t) -> Bool {
    if kill(pid, 0) == 0 {
      return true
    }

    return errno == EPERM
  }
}

@MainActor
public final class BacklightKeeper {
  public typealias RefreshOperation = @MainActor @Sendable (ReceiverSnapshot) throws -> Void
  public typealias RefreshResultHandler = @MainActor @Sendable (KeepAliveRefreshResult) -> Void

  public let receiverSnapshot: ReceiverSnapshot

  private let refreshIntervalNanoseconds: UInt64
  private let refreshOperation: RefreshOperation
  private let resultHandler: RefreshResultHandler
  private let now: @MainActor @Sendable () -> Date
  private let lockURL: URL?
  private var keepAliveTask: Task<Void, Never>?
  private var ownership: KeepAliveOwnership?
  private var isClosed = false

  public private(set) var isRunning = false
  public private(set) var lastRefreshResult: KeepAliveRefreshResult?

  public init(
    target: HIDReceiverTarget,
    refreshIntervalSeconds: TimeInterval = TimeInterval(KeepAliveProtocol.keepAliveIntervalSeconds),
    resultHandler: @escaping RefreshResultHandler = { _ in }
  ) {
    receiverSnapshot = target.match.snapshot
    refreshIntervalNanoseconds = UInt64(refreshIntervalSeconds * 1_000_000_000)
    refreshOperation = { snapshot in
      let controller = MXLightkeeperController()
      try controller.refreshKeepAlive(matching: snapshot)
    }
    self.resultHandler = resultHandler
    now = Date.init
    lockURL = nil
  }

  init(
    snapshot: ReceiverSnapshot,
    refreshIntervalSeconds: TimeInterval = TimeInterval(KeepAliveProtocol.keepAliveIntervalSeconds),
    lockURL: URL? = nil,
    refreshOperation: @escaping RefreshOperation = { _ in },
    resultHandler: @escaping RefreshResultHandler = { _ in },
    now: @escaping @MainActor @Sendable () -> Date = Date.init
  ) {
    receiverSnapshot = snapshot
    refreshIntervalNanoseconds = UInt64(refreshIntervalSeconds * 1_000_000_000)
    self.lockURL = lockURL
    self.refreshOperation = refreshOperation
    self.resultHandler = resultHandler
    self.now = now
  }

  public func close() {
    guard !isClosed else {
      return
    }

    stop()
    isClosed = true
  }

  public func start() throws {
    guard !isClosed else {
      return
    }

    guard !isRunning else {
      return
    }

    let ownership = KeepAliveOwnership(lockURL: lockURL)
    try ownership.acquire()
    self.ownership = ownership

    keepAliveTask?.cancel()
    isRunning = true
    keepAliveTask = Task { [weak self, refreshIntervalNanoseconds] in
      while !Task.isCancelled {
        guard self != nil else {
          break
        }

        self?.performRefresh()

        do {
          try await Task.sleep(nanoseconds: refreshIntervalNanoseconds)
        } catch {
          break
        }
      }
    }
  }

  @discardableResult
  func performRefresh() -> KeepAliveRefreshResult {
    let attemptedAt = now()
    let result: KeepAliveRefreshResult

    do {
      try refreshOperation(receiverSnapshot)
      result = KeepAliveRefreshResult(
        receiver: receiverSnapshot,
        attemptedAt: attemptedAt,
        completedStage: .complete
      )
    } catch let error as KeepAliveRefreshError {
      result = KeepAliveRefreshResult(
        receiver: receiverSnapshot,
        attemptedAt: attemptedAt,
        completedStage: error.completedStage,
        failureDescription: error.failureDescription
      )
    } catch {
      result = KeepAliveRefreshResult(
        receiver: receiverSnapshot,
        attemptedAt: attemptedAt,
        completedStage: .notStarted,
        failureDescription: error.localizedDescription
      )
    }

    lastRefreshResult = result
    resultHandler(result)
    return result
  }

  public func stop() {
    keepAliveTask?.cancel()
    keepAliveTask = nil
    ownership?.release()
    ownership = nil
    isRunning = false
  }
}
