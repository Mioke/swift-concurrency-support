//
//  TaskQueue.swift
//  MIOSwiftyArchitecture
//
//  Created by Klein on 2024/7/2.
//

import Foundation

@available(macOS 10.15, tvOS 13.0, iOS 13.0, watchOS 6.0, *)
public typealias ThrowingTaskQueue<Value, E: Swift.Error> = TaskQueue<Swift.Result<Value, E>>

/// Run tasks one by one, FIFO.
@available(macOS 10.15, tvOS 13.0, iOS 13.0, watchOS 6.0, *)
final public class TaskQueue<Element> {

  /// The metrics configuration, default is `.enabled(cacheSize: 10)`, set `.disabled` to disable metrics.
  public var metricsConfiguration: TaskQueue.MetricsConfiguration = .enabled(cacheSize: 10) {
    didSet {
      resetMetrics()
    }
  }

  @ThreadSafe
  private var array: [TaskItem] = []

  private var metrics: [UUID: TaskQueue.Metrics] = [:]
  private var metricsCacheIndex: [UUID] = []

  private var stream: AsyncMulticast<TaskItem> = .init()

  /// The running state, protected by the `array`'s lock, not thread-safe.
  private var isRunning: Bool = false

  struct TaskItem {
    let id: UUID
    let originalTask: () async throws -> Element
    let postCheck: () -> Void

    func task() async throws -> Element {
      let result = try await originalTask()
      postCheck()
      return result
    }
  }

  /// Enqueue a task and run it immediately, the finish callback will be called as non-concurrency type.
  /// - Parameters:
  ///   - id: Task id, for tracking purpose.
  ///   - task: The task you want to enqueue.
  ///   - onFinished: Finish callback closure. If the result is nil, that means the `TaskQueue` has already been
  ///   deallocated before this task is finished.
  public func addTask(
    id: UUID = .init(),
    _ task: @escaping () async throws -> Element,
    onFinished: @escaping (Result<Element, Swift.Error>) -> Void
  ) {
    let item = enqueueTask(with: id, task: task)
    Task { [weak self] in
      await self?.waitUntilAvailable(item: item)()
      do {
        if self == nil { throw _Concurrency.CancellationError() }
        onFinished(.success(try await item.task()))
      } catch {
        onFinished(.failure(error))
      }
    }
  }

  /// Enqueue a task and wait for it's result. If the task has already began, this function will return the result even
  /// the queue is deallocated.
  /// - Parameters:
  ///   - id: Task id, for tracking purpose.
  ///   - task: The task you want to enqueue.
  /// - Returns: The task's result.
  public func task(id: UUID = .init(), _ task: @escaping () async throws -> Element) async rethrows -> Element {
    let item = enqueueTask(with: id, task: task)
    // The `await`s here will capture `self` and delay the deallocation if the queue has no other owners.
    await waitUntilAvailable(item: item)()
    // for the `rethrows` feature, can only call the parameter task here.
    let result = try await task()
    item.postCheck()
    return result
  }

  /// Enqueue a task and try to run it immediately.
  /// - Parameters:
  ///   - id: Task's id, for tracking purpose.
  ///   - task: The task.
  /// - Returns: The wrapped Task.
  public func enqueueTask(id: UUID = .init(), task: @escaping () async throws -> Element) -> Task<Element, Error> {
    let item = enqueueTask(with: id, task: task)
    return .init { [weak self] in
      await self?.waitUntilAvailable(item: item)()
      if self == nil { throw _Concurrency.CancellationError() }
      return try await item.task()
    }
  }

  private func enqueueTask(with id: UUID, task: @escaping () async throws -> Element) -> TaskItem {
    let item = TaskItem(
      id: id,
      originalTask: task,
      postCheck: { [weak self] in
        guard let self else { return }
        isRunning = false
        markMetricsAsEnd(id: id)
        checkNext()
      })
    _array.write { array in
      array.append(item)
      metrics(id: id)
    }
    return item
  }

  /// The `await` for the block returned here will immediately pass when `self` is deallocated.
  private func waitUntilAvailable(item: TaskItem) -> () async -> Void {
    let id = item.id
    // weak capture `self`, otherwise if any signal is waiting, the `TaskQueue` can't be deallocated.
    return { [weak self] in
      guard let (signal, token) = self?.stream.subscribe(where: { $0.id == item.id }) else {
        return
      }
      self?.checkNext()
      // Must await here first, then the `stream` can cast the item later.
      for await _ in signal { break }
      self?.markMetricsAsStart(id: id)
      token.unsubscribe()
    }
  }

  private func checkNext() {
    let next: TaskItem? = _array.write { array in
      // `isRunning` must be protected by the `write`, because this whole logic determine the `isRunning` state.
      guard isRunning == false, let next = array.first else { return nil }
      array.removeFirst()
      isRunning = true
      return next
    }
    guard let next else { return }

    // cast asynchrounously, make sure the `cast` is run after `await`.
    Task {
      stream.cast(next)
    }
  }

  deinit {
  }
}

// MARK: - Metrics

@available(macOS 10.15, tvOS 13.0, iOS 13.0, watchOS 6.0, *)
extension TaskQueue {

  /// The task's metrics of whole enqueueing and execution.
  public struct Metrics {
    /// The task's id when passed as the parameter into the enqueueing function.
    public let id: UUID
    /// The enqueue time of the task.
    public let enqueueTime: CFAbsoluteTime
    /// The start execution time of the task.
    public var startExecutionTime: CFAbsoluteTime?
    /// The end execution time of the task.
    public var endExecutionTime: CFAbsoluteTime?

    /// The waiting time of the task in the queue.
    public var waitingDuration: TimeInterval? {
      guard let startExecutionTime else { return nil }
      return startExecutionTime - enqueueTime
    }
    /// The execution time of the task.
    public var executionDuration: TimeInterval? {
      guard let startExecutionTime, let endExecutionTime else { return nil }
      return endExecutionTime - startExecutionTime
    }
  }

  /// The metrics configuration
  public enum MetricsConfiguration: Equatable {
    case disabled
    case enabled(cacheSize: Int)
  }

  /// Retreive the task's metrics using task id, will delete the metrics from the queue cache after retreived.
  /// - Parameter id: The task's id.
  /// - Returns: The metrics of the task if there is any in the cache, otherwise `nil`.
  public func retreiveTaskMetrics(id: UUID) -> Metrics? {
    defer {
      _array.write { _ in
        remove(metricsID: id)
      }
    }
    return metrics[id]
  }

  func add(metrics: Metrics) {
    guard case .enabled(let metricsCacheSize) = metricsConfiguration else { return }
    self.metrics[metrics.id] = metrics
    metricsCacheIndex.append(metrics.id)

    if metricsCacheIndex.count > metricsCacheSize {
      let oldest = metricsCacheIndex.removeFirst()
      self.metrics.removeValue(forKey: oldest)
    }
  }

  func remove(metricsID: UUID) {
    self.metrics.removeValue(forKey: metricsID)
    metricsCacheIndex.removeAll { $0 == metricsID }
  }

  func metrics(id: UUID) {
    guard metricsConfiguration != .disabled else { return }
    let metr: Metrics = .init(id: id, enqueueTime: CFAbsoluteTimeGetCurrent())
    add(metrics: metr)
  }

  func markMetricsAsStart(id: UUID) {
    guard metricsConfiguration != .disabled else { return }
    guard var metr = metrics[id] else { return }
    metr.startExecutionTime = CFAbsoluteTimeGetCurrent()
    metrics[id] = metr
  }

  func markMetricsAsEnd(id: UUID) {
    guard metricsConfiguration != .disabled else { return }
    guard var metr = metrics[id] else { return }
    metr.endExecutionTime = CFAbsoluteTimeGetCurrent()
    metrics[id] = metr
  }

  func resetMetrics() {
    metrics.removeAll()
    metricsCacheIndex.removeAll()
  }
}

@available(macOS 10.15, tvOS 13.0, iOS 13.0, watchOS 6.0, *)
extension TaskQueue.Metrics: CustomStringConvertible {
  public var description: String {
    var desc = "id: \(id)"
    desc += "\n - waitingDuration: \(waitingDuration ?? -1)"
    desc += "\n - executionDuration: \(executionDuration ?? -1)"
    return desc
  }
}
