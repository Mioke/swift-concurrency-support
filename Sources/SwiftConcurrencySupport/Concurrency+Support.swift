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
public actor AsyncThrowingSignalStream<T> {

  public enum SignalError: Swift.Error {
    case closed
  }

  private var continuations: [(condition: (T) -> Bool, continuation: CheckedContinuation<T, any Error>)] = []

  public init() {}

  /// Try await a value signal
  /// - Parameter signalCondition: A condition to determine whether the value is what caller waiting for.
  /// - Returns: The value.
  public func wait(for signalCondition: @escaping (T) -> Bool) async throws -> T {
    return try await withCheckedThrowingContinuation { continuation in
      continuations.append((condition: signalCondition, continuation: continuation))
    }
  }

  /// Send a value into this stream.
  /// - Parameter signal: A value.
  public func send(signal: T) {
    continuations.removeAll {
      if $0.condition(signal) {
        $0.continuation.resume(returning: signal)
        return true
      }
      return false
    }
  }

  /// Send an error to all waiting caller.
  /// - Parameter error: An error.
  public func send(error: Error) {
    continuations.removeAll {
      $0.continuation.resume(throwing: error)
      return true
    }
  }

  /// Invalidate current stream and remove all waits.
  /// - Important: This stream won't ge deinit when there is any wait in the stream. So invalid when you
  ///              want to release a stream or add `invalid()` in the owner's `deinit`.
  public func invalid() {
    continuations.removeAll {
      $0.continuation.resume(throwing: SignalError.closed)
      return true
    }
  }

  deinit {
    continuations.forEach { $0.continuation.resume(throwing: SignalError.closed) }
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

@available(macOS 10.15, tvOS 13.0, iOS 13.0, watchOS 6.0, *)
extension Task where Failure == any Error {

  /// The task generated errors using in custom `Task` extension.
  public enum CustomError: Error {
    case capturingObjectReleased
    case timeout
  }

  /// Get task's success value with a timeout limitation.
  /// - Important: If the task is a computationally-intensive process, guarantee to add `Task.checkCancellaction()`
  /// and `Task.yield()` to check the task whether has been cancelled already.
  /// - Important: When timeout there will be raised a "CustomError.timeout".
  /// - Parameters:
  ///   - nanoseconds: Timeout limitation
  ///   - onTimeout: Timeout handler.
  /// - Returns: Success value.
  public func value(timeout nanoseconds: UInt64, onTimeout: (@Sendable () -> Void)? = nil)
    async throws -> Success
  {
    return try await withCheckedThrowingContinuation { continuation in
      let cooperateTask = Task<Void, Never> {
        do {
          try await Task<Never, Never>.sleep(nanoseconds: nanoseconds)
          // Task.isCancelled - get the value or an error before timed-out.
          // self.isCancelled - may get cancelled by other process.
          if !Task<Never, Never>.isCancelled {
            onTimeout?()
            continuation.resume(throwing: CustomError.timeout)
            self.cancel()
          }
        } catch {
          continuation.resume(throwing: error)
        }
      }
      Task<Void, Never> {
        do {
          continuation.resume(returning: try await self.value)
        } catch {
          if !self.isCancelled { continuation.resume(throwing: error) }
        }
        cooperateTask.cancel()
      }
    }
  }

  /// Get task's success value with a timeout duration limitation.
  /// - Important: If the task is a computationally-intensive process, guarantee to add `Task.checkCancellaction()`
  /// and `Task.yield()` to check the task whether has been cancelled already, or the task may run infinitely.
  /// - Important: When timeout there will be raised a "CustomError.timeout".
  /// - Parameters:
  ///   - duration: Timeout limitation in Duration.
  ///   - onTimeout: Timeout handler
  /// - Returns: Success value.
  @available(macOS 13.0, iOS 16.0, watchOS 9.0, tvOS 16.0, *)
  public func value(timeout duration: Duration, onTimeout: (@Sendable () -> Void)? = nil)
    async throws -> Success
  {
    return try await withCheckedThrowingContinuation { continuation in
      let cooperateTask = Task<Void, Never> {
        do {
          try await Task<Never, Never>.sleep(for: duration)
          // Task.isCancelled - get the value or an error before timed-out.
          // self.isCancelled - may get cancelled by other process.
          if !Task<Never, Never>.isCancelled {
            onTimeout?()
            continuation.resume(throwing: CustomError.timeout)
            self.cancel()
          }
        } catch {
          continuation.resume(throwing: error)
        }
      }
      Task<Void, Never> {
        do {
          continuation.resume(returning: try await self.value)
        } catch {
          if !self.isCancelled { continuation.resume(throwing: error) }
        }
        cooperateTask.cancel()
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
      guard let object else { throw CustomError.capturingObjectReleased }
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
