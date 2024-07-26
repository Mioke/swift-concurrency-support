//
//  AsyncOperation.swift
//  SwiftConcurrencySupport
//
//  Created by Klein on 2024/6/25.
//

import Foundation

// MARK: - AsyncOperation

/// A wrapper of an asynchronous operation can produce a result value.
/// - Note: Wish to make it like: `AsyncOperation<Success, Failure>` but the initial closure throws an anonymous error
/// type
@available(macOS 10.15, tvOS 13.0, iOS 13.0, watchOS 6.0, *)
public struct AsyncOperation<Success> {
  public typealias Operation = () async throws -> Success

  let operation: Operation

  /// Initilaization method.
  /// - Parameter operation: The operation which will be wrapped.
  public init(operation: @escaping Operation) {
    self.operation = operation
  }

  /// Start this operation. May throws `AsyncOperation.Error` when attemping start a running operation, and `rethrows`
  /// the error which operation throws.
  /// - Returns: The operation's result.
  public func start() async throws -> Success {
    return try await self.operation()
  }

  /// Start this operation and return a `Result` which contains the operation's result or error.
  /// - Returns: The operation's result or error.
  public func startWithResult() async -> Result<Success, Swift.Error> {
    do {
      return .success(try await start())
    } catch {
      return .failure(error)
    }
  }

  /// Create an `AsyncOperation` from a value.
  /// - Parameter value: The value.
  /// - Returns: The operation.
  public static func value(_ value: Success) -> AsyncOperation<Success> {
    return .init { value }
  }

  /// Create an `AsyncOperation` from an error.
  /// - Parameter error: The error.
  /// - Returns: The operation.
  public static func error(_ error: Swift.Error) -> AsyncOperation<Success> {
    return .init { throw error }
  }
}

// MARK: - AsyncOperation's Operators

@available(macOS 10.15, tvOS 13.0, iOS 13.0, watchOS 6.0, *)
extension AsyncOperation {

  /// Flat map to a new `AyncOperation`, usally can chain two operations together.
  /// - Parameter conversion: The new operation producer.
  /// - Returns: The chained operation.
  public func flatMap<T>(_ conversion: @escaping (Success) throws -> AsyncOperation<T>)
    -> AsyncOperation<T>
  {
    return .init {
      let result = try await self.start()
      let next = try conversion(result)
      return try await next.start()
    }
  }

  /// Map the result to a new value.
  /// - Parameter conversion: The result conversion closure.
  /// - Returns: The result mapped operation.
  public func map<T>(_ conversion: @escaping (Success) throws -> T) -> AsyncOperation<T> {
    return .init {
      let result = try await self.start()
      return try conversion(result)
    }
  }

  /// Map the failure to a new operation.
  /// - Parameter conversion: The failure conversion closure.
  /// - Returns: The result mapped operation.
  public func mapError(
    _ conversion: @escaping (Swift.Error) throws -> AsyncOperation<Success>
  ) -> AsyncOperation<Success> {
    return .init {
      do {
        return try await self.start()
      } catch {
        return try await conversion(error).start()
      }
    }
  }

  /// Combine current operation with another operation.
  /// - Parameter operation: Another operation.
  /// - Returns: The combined operation.
  public func combine<T>(_ operation: AsyncOperation<T>) -> AsyncOperation<(Success, T)> {
    return .init {
      async let myResult = self.start()
      async let otherResult = operation.start()
      return (try await myResult, try await otherResult)
    }
  }

  /// Combine multiple operations together and get their results in once. All the operations will run asynchrounously.
  /// - Important: If one operation fails, the whole operation will fail immediately and cancel all other tasks. But
  /// other running operations will continue to run until finished if you don't have any Task.isCancelled check.
  /// - Parameter operations: The operations going to combined.
  /// - Returns: The combined operation.
  public static func combine(_ operations: [AsyncOperation<Success>]) -> AsyncOperation<[Success]> {
    return .init {
      return try await operations.concurrentMap { op in
        try await op.start()
      }
    }
  }

  /// Concatenate multiple operations together and get their results in once, the operations will run one by one.
  /// - Parameter operations: The operations going to concatenated.
  /// - Returns: The concatenated operation.
  public static func concat(_ operations: [AsyncOperation<Success>]) -> AsyncOperation<[Success]> {
    return .init {
      return try await operations.asyncMap { try await $0.start() }
    }
  }

  /// Merge multiple operations into one AsyncThrowingStream. The operations will run one by one.
  /// - Parameter operations: The operations going to be merged.
  /// - Returns: The merged stream.
  public static func merge(_ operations: [AsyncOperation<Success>]) -> AsyncThrowingStream<Success, Swift.Error> {
    var iterator = operations.makeIterator()
    return .init {
      return try await iterator.next()?.start()
    }
  }

  /// Provide a injectable way to handle the result of an operation.
  /// - Parameters:
  ///   - value: The operation when get a success result.
  ///   - error: The operation when get a failure result.
  /// - Returns: A new operation.
  public func on(
    starting: (() async -> Void)? = nil,
    value: ((Success) async -> Void)? = nil,
    error: ((Swift.Error) async -> Void)? = nil,
    final: (() -> Void)? = nil
  ) -> AsyncOperation<Success> {
    return .init {
      defer { final?() }
      do {
        await starting?()
        let result = try await self.start()
        await value?(result)
        return result
      } catch (let e) {
        await error?(e)
        throw e
      }
    }
  }

  /// Retry the operation when it fails.
  /// - Parameters:
  ///   - times: The retry times.
  ///   - interval: The interval between two retries. Default is 0.
  /// - Returns: The transformed operation.
  public func retry(times: Int = 1, interval: TimeInterval = 0) -> AsyncOperation<Success> {
    return .init {
      var retryCount = 0
      var lastError: Swift.Error? = nil
      while retryCount <= times {
        do {
          return try await self.start()
        } catch {
          lastError = error
          retryCount += 1
          try await Task.sleep(nanoseconds: UInt64(interval * Double(NSEC_PER_SEC)))
        }
      }
      guard let lastError = lastError else {
        fatalError("should not be reached.")
      }
      throw lastError
    }
  }

  /// Delay the operation.
  /// - Parameter interval: The delay interval, unit is second.
  /// - Returns: The delayed operation.
  public func delay(_ interval: TimeInterval) -> AsyncOperation<Success> {
    return .init {
      if #available(macOS 13.0, iOS 16.0, watchOS 9.0, tvOS 16.0, *) {
        try await Task.sleep(for: .seconds(interval))
      } else {
        try await Task.sleep(nanoseconds: UInt64(interval * Double(NSEC_PER_SEC)))
      }
      return try await self.start()
    }
  }

  /// Set a timeout for the operation. If the operation does not finish in the given time, it will be cancelled and
  /// throw a ``Task.CustomError.timeout`` error.
  /// - Parameter after: The timeout duration, unit is second.
  /// - Returns: The operation with a timeout limit.
  public func timeout(after: TimeInterval) -> AsyncOperation<Success> {
    return .init {
      try await Task {
        return try await self.start()
      }
      .value(timeout: UInt64(after * Double(NSEC_PER_SEC)))
    }
  }

  /// Check the operation after a given time. If the operation does not finish in the given time, it will run the 
  /// handler.
  /// - Parameters:
  ///   - after: The check duration, unit is second.
  ///   - handler: The handler to run when the operation does not finish in the given time.
  /// - Returns: The operation with a check limit.
  public func check(after: TimeInterval, handler: @escaping () async -> Void) -> AsyncOperation<Success> {
    return .init {
      let isFinished: ActorAtomic<Bool> = .init(value: false)
      Task {
        try await Task.sleep(nanoseconds: UInt64(after * Double(NSEC_PER_SEC)))
        if await isFinished.value == false { await handler() }
      }
      let result = try await self.start()
      await isFinished.modify { $0 = true }
      return result
    }
  }

  /// Run the operation in a detached task context.
  /// - Parameter priority: The detached task's priority. Default is nil.
  /// - Returns: The detached operation.
  public func detached(priority: TaskPriority? = nil) -> Self {
    return .init {
      let task = Task.detached(priority: priority) {
        try await self.start()
      }
      return try await task.value
    }
  }

  /// Adjust the operation's priority using ``Task``.
  /// - Parameter priority: The new priority. Default is nil, means the same as the current task.
  /// - Returns: The adjusted operation.
  public func priority(_ priority: TaskPriority? = nil) -> Self {
    return .init {
      let task = Task(priority: priority) {
        try await self.start()
      }
      return try await task.value
    }
  }
}

// MARK: - AsyncOperationQueue

/// An operation queue to run `AsyncOperation`.
@available(macOS 10.15, tvOS 13.0, iOS 13.0, watchOS 6.0, *)
final public class AsyncOperationQueue {

  /// The operation's state.
  public enum State: Equatable {
    case running(concurrentCount: Int)
    case waiting
  }

  /// The operation's concurrency mode.
  public enum Mode {
    case serial
    case concurrent(limit: Int)
  }

  /// Concurrency mode.
  public private(set) var mode: Mode
  /// Current state.
  public private(set) var state: AsyncOperationQueue.State = .waiting

  /// The queue of operations. The operations will be executed in the order of enqueue. The `id` is used to identify the
  /// operation in the queue, only used for debugging purpose.
  @ThreadSafe
  var queue: [(id: UUID, continuation: CheckedContinuation<Void, Never>)] = []

  /// Intialization. Not suggest to use `.concurrent(limit: 1)` for serial execution, the `.serial` mode will have
  /// better performance.
  /// - Parameter mode: The concurrency mode of this operation queue, default is `.serial`
  public init(mode: Mode = .serial) {
    self.mode = mode
  }

  /// Enqueue an operation and wait for its result.
  /// - Parameter operation: The operation will be enqueued.
  /// - Returns: The operation's result.
  public func operation<S>(_ operation: AsyncOperation<S>) async throws -> S {
    await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) -> Void in
      _queue.write { q in
        q.append((id: UUID(), continuation: continuation))
        processNextIfNeeded(queue: &q)
      }
    }
    defer {
      _queue.write { q in
        handleCompletion()
        processNextIfNeeded(queue: &q)
      }
    }
    return try await operation.start()
  }

  /// Enqueue an operation and wait for its result.
  /// - Parameter block: The operation's build block.
  /// - Returns: The operation's result.
  public func operation<S>(block: @escaping AsyncOperation<S>.Operation) async throws -> S {
    let asyncOperation: AsyncOperation<S> = .init(operation: block)
    return try await operation(asyncOperation)
  }

  // MARK: - Internal functions.

  func processNextIfNeeded(
    queue: inout [(id: UUID, continuation: CheckedContinuation<Void, Never>)]
  ) {
    if case .serial = mode {
      processSerial(queue: &queue)
    } else {
      processConcurrent(queue: &queue)
    }
  }

  func processSerial(queue: inout [(id: UUID, continuation: CheckedContinuation<Void, Never>)]) {
    guard case .waiting = state else { return }
    guard let head = queue.isEmpty ? nil : queue.removeFirst() else { return }
    state = .running(concurrentCount: 1)
    head.continuation.resume(returning: ())
  }

  func processConcurrent(queue: inout [(id: UUID, continuation: CheckedContinuation<Void, Never>)]) {
    guard case .concurrent(let limit) = mode else {
      return
    }
    let concurrentCount = state.runningCount() ?? 0
    if state != .waiting && concurrentCount >= limit {
      return
    }
    guard let head = queue.isEmpty ? nil : queue.removeFirst() else { return }
    state = .running(concurrentCount: concurrentCount + 1)
    head.continuation.resume(returning: ())
  }

  func handleCompletion() {
    if case .serial = mode {
      state = .waiting
    } else if case .running(let concurrentCount) = state {
      state = (concurrentCount - 1 > 0) ? .running(concurrentCount: concurrentCount - 1) : .waiting
    }
  }
}

@available(macOS 10.15, tvOS 13.0, iOS 13.0, watchOS 6.0, *)
extension AsyncOperationQueue.State {
  func runningCount() -> Int? {
    guard case .running(let concurrentCount) = self else {
      return nil
    }
    return concurrentCount
  }
}

// MARK: - AsyncOperation Metrics

@available(macOS 10.15, tvOS 13.0, iOS 13.0, watchOS 6.0, *)
extension AsyncOperation {

  /// The operation's metrics.
  public struct Metrics: CustomStringConvertible {
    /// The operation's start time.
    public internal(set) var beginTime: CFAbsoluteTime? = nil

    /// The operation's end time.
    public internal(set) var endTime: CFAbsoluteTime? = nil

    /// The operation's duration.
    public var duration: TimeInterval? {
      guard let beginTime, let endTime else { return nil }
      return endTime - beginTime
    }

    mutating func metrics<T>(around closure: () async throws -> T) async rethrows -> T {
      self.beginTime = CFAbsoluteTimeGetCurrent()
      let result = try await closure()
      self.endTime = CFAbsoluteTimeGetCurrent()
      return result
    }

    public var description: String {
      var description = "------------------------\n"
      if let duration = duration {
        description += "duration: \(duration)\n"
      }
      if let beginTime = beginTime, let endTime = endTime {
        description +=
          "beginTime: \(Date(timeIntervalSinceReferenceDate: beginTime)), endTime: \(Date(timeIntervalSinceReferenceDate: endTime))\n"
      }
      description += "------------------------"
      return description
    }
  }

  /// Add metrics to the operation.
  /// - Parameter closure: The closure will be called when the operation is finished.
  /// - Returns: The operation with metrics.
  public func metrics(_ closure: @escaping (Metrics) -> Void) -> AsyncOperation<Success> {
    return .init {
      var metrics = Metrics()
      defer { closure(metrics) }
      return try await metrics.metrics(around: self.start)
    }
  }
}

// TODO: - involve failure's type into the AsyncOperation like AsyncOperation<Success, Failure>.

/// Now we don't do this because it's ugly when initializing a producer.
/// ```swift
/// let producer = AsyncProducer<Success, Failure>(operation: {
///   do {
///     let result = try await operation()
///     return.success(result)
///   } catch {
///     return.failure(error)
///   }
/// ```
/// Or it only must unsafe cast the throwing error to the `Failure` type, which is not good.
/// After Swift 6 released we can use `throw(ErrorType)` to limit the throwing error type.
///
/// Why `AsyncOperation<Success, Failure>` is good? Because when the operation has no error to throw, the type
/// `AsyncOperation<Success, Never>` can be better understand, and the `start() async` function would have a
/// non-throwing version.
private struct AsyncProducer<Success, Failure> where Failure: Swift.Error {
  typealias Operation = () async -> Result<Success, Failure>

  let operation: Operation

  public init(operation: @escaping Operation) {
    self.operation = operation
  }

  public func start() async throws -> Success {
    try await operation().get()
  }

  public func startWithResult() async -> Result<Success, Failure> {
    await operation()
  }
}

extension AsyncProducer where Failure == Never {
  func start() async -> Success {
    let result = await operation()
    return try! result.get()
  }
}
