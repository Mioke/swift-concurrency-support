//
//  Created by Klein on 2023/6/8.
//

import Foundation

// MARK: - AsyncThrowingSignalStream

/// A signal stream similiar to `AsyncThrowingStream`, but a little different from it.
/// 1. Can await in multiple tasks, and `wait(for:)` can only receive signal once.
/// 2. Send `error` to all waiting callers.
/// 3. Won't terminate when receiving an `error`
/// 4. Send ``SignalError.closed`` error when stream is off.
/// 5. If there's a wait in the stream, the stream won't get deallocated, please call `invalid()` first
///    before relase a stream.
@available(macOS 10.15, tvOS 13.0, iOS 13.0, watchOS 6.0, *)
final public class AsyncThrowingSignalStream<T>: Sendable {

  public enum SignalError: Swift.Error {
    case closed
  }

  let multicaster: AsyncThrowingMulticast<T> = .init()

  public init() {}

  /// Try await a value signal.
  /// - Caution: This function will capture this stream, which will cause this stream can't be deallocated! If still
  ///   want to use this function, please call `invalid()` before release this stream.
  /// - Parameter signalCondition: A condition to determine whether the value is what caller waiting for.
  /// - Returns: The value.
  public func wait(for signalCondition: @escaping (T) -> Bool) async throws -> T {
    let observer = multicaster.subscribe(where: signalCondition)
    guard let value = try await observer.stream.first(where: signalCondition) else {
      throw SignalError.closed
    }
    return value
  }

  /// Try await a value signal, this functions won't let this stream be captured so this stream can be deallocated while
  /// waiting.
  /// - Parameter signalCondition: A condition to determine whether the value is what caller waiting for.
  /// - Returns: The value.
  public func weakWait(for signalCondition: @escaping (T) -> Bool) -> () async throws -> T {
    return { [weak self] in
      guard let observer = self?.multicaster.subscribe(where: signalCondition) else { throw SignalError.closed }
      guard let value = try await observer.stream.first(where: signalCondition) else { throw SignalError.closed }
      return value
    }
  }

  /// Send a value into this stream.
  /// - Parameter signal: A value.
  public func send(signal: T) {
    multicaster.cast(signal)
  }

  /// Send an error to all waiting caller.
  /// - Parameter error: An error.
  public func send(error: Error) {
    multicaster.cast(error: error)
  }

  /// Invalidate current stream and remove all waits.
  /// - Important: This stream won't ge deinit when there is any wait in the stream. So invalid when you
  ///              want to release a stream or add `invalid()` in the owner's `deinit`.
  public func invalid() {
    multicaster.cast(error: SignalError.closed)
  }

  deinit {
    invalid()
  }
}

// MARK: - Timeout

/// Inherit the current task priority in task hierarchy.
/// - Parameters:
///   - task: The operation.
///   - nanoseconds: Timeout limit in nanosecond.
///   - onTimeout: Timeout handler.
/// - Throws: The error thrown from `operation`
/// - Returns: The result from `operation`
@available(macOS 10.15, tvOS 13.0, iOS 13.0, watchOS 6.0, *)
public func timeoutTask<T: Sendable>(
  with nanoseconds: UInt64,
  task: @Sendable @escaping () async throws -> T,
  onTimeout: @escaping @Sendable () -> Void
) async throws -> T {
  let task = Task(operation: task)
  return try await task.value(timeout: nanoseconds, onTimeout: onTimeout)
}

/// The task generated errors while using `Task` functions in this library.
public struct TaskError: Swift.Error, RawRepresentable, Equatable {

  /// The TaskError's code.
  public struct Code: CustomStringConvertible, Equatable {
    public let code: Int
    public var description: String
  }

  public var rawValue: Code
  public init(rawValue: Code) {
    self.rawValue = rawValue
  }
}

extension TaskError.Code {

  public static let weakCapturingObjectReleasedCode = Self(
    code: 1,
    description: "The weak capturing object has been released.")

  public static let timeoutCode = Self(code: 2, description: "Task timeout.")
}

extension TaskError {

  /// The error thrown when the weak capturing object has been released.
  public static let weakCapturingObjectReleased = TaskError(rawValue: .weakCapturingObjectReleasedCode)

  /// The error thrown when the task timeout calling ``value(timeout:onTimeout:)``.
  public static let timeout = TaskError(rawValue: .timeoutCode)
}

@available(macOS 10.15, tvOS 13.0, iOS 13.0, watchOS 6.0, *)
extension Task where Failure == any Error {

  /// Get task's success value with a timeout limitation.
  /// - Important: If the task is a computationally-intensive process, guarantee to add `Task.checkCancellaction()`
  /// and `Task.yield()` to check the task whether has been cancelled already.
  /// - Important: When timeout there will be raised a "TaskError.timeout".
  /// - Parameters:
  ///   - nanoseconds: Timeout limitation
  ///   - onTimeout: Timeout handler.
  /// - Returns: Success value.
  public func value(timeout nanoseconds: UInt64, onTimeout: (@Sendable () -> Void)? = nil)
    async throws -> Success
  {
    return try await withCheckedThrowingContinuation { continuation in
      _timeout(
        continuation: continuation,
        onTimeout: onTimeout,
        waitBlock: {
          try await Task<Never, Never>.sleep(nanoseconds: nanoseconds)
        })
    }
  }

  /// Get task's success value with a timeout duration limitation.
  /// - Important: If the task is a computationally-intensive process, guarantee to add `Task.checkCancellaction()`
  /// and `Task.yield()` to check the task whether has been cancelled already, or the task may run infinitely.
  /// - Important: When timeout there will be raised a "TaskError.timeout".
  /// - Parameters:
  ///   - duration: Timeout limitation in Duration.
  ///   - onTimeout: Timeout handler
  /// - Returns: Success value.
  @available(macOS 13.0, iOS 16.0, watchOS 9.0, tvOS 16.0, *)
  public func value(timeout duration: Duration, onTimeout: (@Sendable () -> Void)? = nil)
    async throws -> Success
  {
    return try await withCheckedThrowingContinuation { continuation in
      _timeout(
        continuation: continuation,
        onTimeout: onTimeout,
        waitBlock: {
          try await Task<Never, Never>.sleep(for: duration)
        })
    }
  }

  private func _timeout(
    continuation: CheckedContinuation<Success, Error>,
    onTimeout: (@Sendable () -> Void)?,
    waitBlock: @escaping () async throws -> Void
  ) {
    let resumed: ActorAtomic<Bool> = .init(value: false)
    // Timeout task.
    Task<Void, Never> {
      do {
        try await waitBlock()
        await resumed.modify {
          guard $0.value == false else { return }
          onTimeout?()
          $0.value = true
          continuation.resume(throwing: TaskError.timeout)
        }
      } catch {
        await resumed.modify {
          guard $0.value == false else { return }
          $0.value = true
          continuation.resume(throwing: error)
        }
      }
    }
    // Original value task.
    Task<Void, Never> {
      do {
        let result = try await self.value
        await resumed.modify {
          guard $0.value == false else { return }
          $0.value = true
          continuation.resume(returning: result)
        }
      } catch {
        await resumed.modify {
          guard $0.value == false else { return }
          $0.value = true
          continuation.resume(throwing: error)
        }
      }

    }
  }

  /// Get task's success value with a timeout interval limitation, it will throw a `CustomError.timeout` if the task
  /// is not completed in the specified interval.
  /// - Parameters:
  ///   - interval: Timeout limitation in TimeInterval.
  ///   - onTimeout: Timeout handler
  /// - Returns:
  public func value(timeout interval: TimeInterval, onTimeout: (@Sendable () -> Void)? = nil) async throws -> Success {
    if #available(macOS 13.0, iOS 16.0, watchOS 9.0, tvOS 16.0, *) {
      return try await value(timeout: .seconds(interval), onTimeout: onTimeout)
    } else {
      return try await value(timeout: UInt64(interval * Double(NSEC_PER_SEC)), onTimeout: onTimeout)
    }
  }
}

// MARK: - Weak capture convinience methods.
@available(macOS 10.15, tvOS 13.0, iOS 13.0, watchOS 6.0, *)
extension Task where Failure == any Error {
  /// Create a detached task and weak capture an object for the task operation. (Mostly used in capture `self`)
  /// - Parameters:
  ///   - object: The object to be captured
  ///   - priority: Task priority.
  ///   - operation: Task operation.
  @discardableResult
  public static func detached<T>(
    weakCapturing object: T,
    priority: TaskPriority? = nil,
    operation: @escaping (T) async throws -> Success
  ) -> Self where T: AnyObject, Failure == any Error {
    self.detached(priority: priority) { [weak object] in
      guard let object else { throw TaskError.weakCapturingObjectReleased }
      return try await operation(object)
    }
  }
}

@available(macOS 10.15, tvOS 13.0, iOS 13.0, watchOS 6.0, *)
extension Task where Success == Void, Failure == Never {
  public static func detached<T: AnyObject>(
    weakCapturing object: T,
    priority: TaskPriority? = nil,
    operation: @escaping (T) async -> Void
  ) {
    self.detached(
      priority: priority,
      operation: { [weak object] in
        guard let object else { return }
        await operation(object)
      })
  }
}

// Copy from swift-concurrency-extra
@available(macOS 10.15, tvOS 13.0, iOS 13.0, watchOS 6.0, *)
extension Task where Success == Never, Failure == Never {
  /// Suspends the current task a number of times before resuming with the goal of allowing other
  /// tasks to start their work.
  ///
  /// This function can be used to make flakey async tests less flakey, as described in
  /// [this Swift Forums post](https://forums.swift.org/t/reliably-testing-code-that-adopts-swift-concurrency/57304).
  /// You may, however, prefer to use ``withMainSerialExecutor(operation:)-79jpc`` to improve the
  /// reliability of async tests, and to make their execution deterministic.
  ///
  /// > Note: When invoked from ``withMainSerialExecutor(operation:)-79jpc``, or when
  /// > ``uncheckedUseMainSerialExecutor`` is set to `true`, `Task.megaYield()` is equivalent to
  /// > a single `Task.yield()`.
  static func megaYield(count: Int = _defaultMegaYieldCount) async {
    // TODO: Investigate why mega yields are still necessary in TCA's test suite.
    // guard !uncheckedUseMainSerialExecutor else {
    //   await Task.yield()
    //   return
    // }
    for _ in 0..<count {
      await Task<Void, Never>.detached(priority: .background) { await Task.yield() }.value
    }
  }
}

/// The number of yields `Task.megaYield()` invokes by default.
///
/// Can be overridden by setting the `TASK_MEGA_YIELD_COUNT` environment variable.
let _defaultMegaYieldCount = max(
  0,
  min(
    ProcessInfo.processInfo.environment["TASK_MEGA_YIELD_COUNT"].flatMap(Int.init) ?? 20,
    10_000
  )
)