//
//  TaskQueue.swift
//  MIOSwiftyArchitecture
//
//  Created by Klein on 2024/7/2.
//

import Foundation

@available(macOS 10.15, tvOS 13.0, iOS 13.0, watchOS 6.0, *)
final public class TaskQueue: @unchecked Sendable {

  typealias ConcurrencyWorkTask = () async -> Void
  private let workersContinuatoin: AsyncStream<(UUID, ConcurrencyWorkTask)>.Continuation

  @ThreadSafe
  private var finished: Bool = false

  /// The initializer of `TaskPriorityQueue`.
  /// - Parameter priority: The task priority of the task that observing enqueued signals, default is `.medium`.
  public init(priority: TaskPriority = .medium) {
    let (worker, workersContinuatoin) = AsyncStream<(UUID, ConcurrencyWorkTask)>.makeStream()
    self.workersContinuatoin = workersContinuatoin

    Task.detached(priority: priority) { [weak self] in
      for await (uuid, task) in worker {
        guard let self else { break }
        print(Date(), "observed uuid: \(uuid)")
        markMetricsAsStart(id: uuid)
        await task()
        print(Date(), "after task uuid: \(uuid)")
        markMetricsAsEnd(id: uuid)
      }
    }
  }

  @discardableResult
  /// Enqueue a task and run it immediately, the finish callback will be called as non-concurrency type.
  /// - Parameters:
  ///   - task: The task to be executed.
  ///   - completion: The completion callback.
  /// - Returns: The UUID of the task metrics, you can use it to retrieve the metrics from cache.
  public func enqueue<T>(
    task: @escaping @Sendable () async throws -> T,
    completion: ((Result<T, Swift.Error>) -> Void)? = nil
  ) -> UUID {
    let uuid = UUID()
    let task: ConcurrencyWorkTask = {
      let result = await Result { try await task() }
      completion?(result)
    }
    createMetricsAsEnqueued(id: uuid)
    workersContinuatoin.yield((uuid, task))
    return uuid
  }

  @discardableResult
  /// Enqueue a task and run it immediately, the finish callback will be called as non-concurrency type.
  /// - Parameters:
  ///   - isolatedActor: The actor which the task isolated in.
  ///   - task: The task to be executed.
  ///   - completion: The completion callback.
  /// - Returns: The UUID of the task metrics, you can use it to retrieve the metrics from cache.
  public func enqueue<T, ActorType: Actor>(
    on isolatedActor: ActorType,
    task: @escaping @Sendable (isolated ActorType) async throws -> T,
    completion: ((Result<T, Swift.Error>) -> Void)? = nil
  ) -> UUID {
    let uuid = UUID()
    let task: ConcurrencyWorkTask = { 
      let result = await Result { try await task(isolatedActor) }
      completion?(result)
    }
    createMetricsAsEnqueued(id: uuid)
    workersContinuatoin.yield((uuid, task))
    return uuid
  }

  /// Enqueue a task and wait for it's result.
  /// - Parameters:
  ///   - task: The task to be executed.
  /// - Throws: The error thrown by the task.
  /// - Returns: The result of the task.
  public func enqueueAndWait<T>(
    _ task: @escaping () async throws -> T
  ) async throws -> T {
    try await withUnsafeThrowingContinuation { continuation in
      let work: ConcurrencyWorkTask = { [weak self] in
        guard let self, !finished else {
          continuation.resume(throwing: CancellationError())
          return
        }
        do {
          continuation.resume(returning: try await task())
        } catch {
          continuation.resume(throwing: error)
        }
      }
      workersContinuatoin.yield((UUID(), work))
    }
  }

  /// Enqueue a task and wait for it's result.
  /// - Parameters:
  ///   - isolatedActor: The actor which the task isolated in.
  ///   - task: The task to be executed.
  /// - Throws: The error thrown by the task.
  /// - Returns: The result of the task.
  public func enqueueAndWait<T, ActorType: Actor>(
    on isolatedActor: ActorType,
    _ task: @escaping (isolated ActorType) async throws -> T
  ) async throws -> T {
    try await withUnsafeThrowingContinuation { continuation in
      let work: ConcurrencyWorkTask = { [weak self] in
        guard let self, !finished else {
          continuation.resume(throwing: CancellationError())
          return
        }
        do {
          continuation.resume(returning: try await task(isolatedActor))
        } catch {
          continuation.resume(throwing: error)
        }
      }
      workersContinuatoin.yield((UUID(), work))
    }
  }

  /// Invalidate this queue and stop running next task if you are using `enqueueAndWait` function. As known that async 
  /// function will implict capture itself and keep it until outside the function. Please call this function before 
  /// deallocating this queue, or the queue will continue running left tasks and won't be deallocated until all tasks 
  /// are finished.
  public func invalidate() {
    workersContinuatoin.finish()
    finished = true
    print(Date(), "invalidate")
  }

  deinit {
    workersContinuatoin.finish()
    print(Date(), "deinit")
  }

  // MARK: - Metrics Properties

  /// The metrics configuration, default is `.enabled(cacheSize: 10)`, set `.disabled` to disable metrics.
  public var metricsConfiguration: TaskQueue.MetricsConfiguration = .disabled

  let metricsLock = UnfairLock()
  private var metrics: [UUID: TaskQueue.Metrics] = [:]
  private var metricsCacheIndex: [UUID] = []
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
    metricsLock.around {
      let m = metrics[id]
      _remove(metricsID: id)
      return m
    }
  }

  /// Update the metrics configuration.
  /// - Parameter configuration: The configuration to be updated.
  public func updateMetricsConfiguration(_ configuration: MetricsConfiguration) {
    metricsLock.around {
      metrics.removeAll()
      metricsCacheIndex.removeAll()
      metricsConfiguration = configuration
    }
  }

  func add(metrics: Metrics) {
    guard case .enabled(let metricsCacheSize) = metricsConfiguration else { return }
    metricsLock.around {
      self.metrics[metrics.id] = metrics
      metricsCacheIndex.append(metrics.id)

      if metricsCacheIndex.count > metricsCacheSize {
        let oldest = metricsCacheIndex.removeFirst()
        self.metrics.removeValue(forKey: oldest)
      }
    }
  }

  // No protect
  func _remove(metricsID: UUID) {
    self.metrics.removeValue(forKey: metricsID)
    metricsCacheIndex.removeAll { $0 == metricsID }
  }

  func createMetricsAsEnqueued(id: UUID) {
    guard metricsConfiguration != .disabled else { return }
    let metr: Metrics = .init(id: id, enqueueTime: CFAbsoluteTimeGetCurrent())
    add(metrics: metr)
  }

  func markMetricsAsStart(id: UUID) {
    modifyMetrics(id: id) { $0.startExecutionTime = CFAbsoluteTimeGetCurrent() }
  }

  func markMetricsAsEnd(id: UUID) {
    modifyMetrics(id: id) { $0.endExecutionTime = CFAbsoluteTimeGetCurrent() }
  }

  func modifyMetrics(id: UUID, modification: (inout Metrics) -> Void) {
    guard metricsConfiguration != .disabled else { return }
    metricsLock.around {
      guard var metr = metrics[id] else { return }
      modification(&metr)
      metrics[id] = metr
    }
  }

  func resetMetrics() {
    metricsLock.around {
      metrics.removeAll()
      metricsCacheIndex.removeAll()
    }
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
