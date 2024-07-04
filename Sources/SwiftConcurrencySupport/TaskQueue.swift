//
//  TaskQueue.swift
//  MIOSwiftyArchitecture
//
//  Created by Klein on 2024/7/2.
//

import Foundation

/// Run tasks one by one, FIFO.
@available(macOS 10.15, tvOS 13.0, iOS 13.0, watchOS 6.0, *)
final public class TaskQueue<Element> {

  @ThreadSafe
  private var array: [TaskItem] = []

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
        checkNext()
      })
    _array.write { array in
      array.append(item)
    }
    return item
  }

  /// The `await` for the block returned here will immediately pass when `self` is deallocated.
  private func waitUntilAvailable(item: TaskItem) -> () async -> Void {
    // weak capture `self`, otherwise if any signal is waiting, the `TaskQueue` can't be deallocated.
    return { [weak self] in
      guard let (signal, token) = self?.stream.subscribe(where: { $0.id == item.id }) else {
        return
      }
      self?.checkNext()
      // Must await here first, then the `stream` can cast the item later.
      for await _ in signal { break }
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

@available(macOS 10.15, tvOS 13.0, iOS 13.0, watchOS 6.0, *)
public typealias ThrowingTaskQueue<Value, E: Swift.Error> = TaskQueue<Swift.Result<Value, E>>
