//
//  ConcurrencySupportTests.swift
//  MIOSwiftyArchitecture
//
//  Created by Klein on 2024/1/16.
//

import Darwin
import Dispatch
import Foundation
import XCTest
import os

#if canImport(SwiftConcurrencySupport)
  import SwiftConcurrencySupport
#endif

enum InternalError: Error, Equatable {
  case test
  case one
}

class ConcurrencySupportTestCases: XCTestCase {

  var property: AsyncProperty<Int> = .init(initialValue: -1)

  override func setUp() async throws {

  }

  @available(iOS 16.0, *)
  func testAsyncProperty() async throws {

    let expect = XCTestExpectation()

    print("Start!")

    Task.detached {
      print("detached task 1, prepare to update")
      var times = 0
      while times < 10 {
        print("task 1 updated \(times), before: \(self.property.value)")
        self.property.update(times)
        times += 1
        try await Task.sleep(for: .seconds(0.1))
      }
      expect.fulfill()
    }

    Task.detached(weakCapturing: self) { me in
      print("detached task 2, prepare to visit")
      print("task 2 visited current value: \(me.property.value)")
      let (stream, token) = me.property.subscribe()
      for await value in stream {
        print("task 2 notified with:", value)
      }
      token.unsubscribe()
    }

    await fulfillment(of: [expect], timeout: 2)
  }

  @available(iOS 16.0, *)
  func testAsyncPropertyAsAsyncSequence() async throws {
    let property: AsyncProperty<Int> = .init(initialValue: 1)
    let expect = XCTestExpectation()

    Task {
      // visit
      var results = [Int]()
      for await value in property {
        results.append(value)
        if results.count == 5 {
          break
        }
      }
      print(results)
      XCTAssert(results == [0, 1, 2, 3, 4])
      expect.fulfill()
    }

    await Task.yield()

    Task {
      for value in 0..<5 {
        property.update(value)
        try await Task.sleep(for: .seconds(0.01))
      }
    }
    await fulfillment(of: [expect], timeout: 1)
  }

  @available(iOS 16.0, *)
  func testAsyncPropertyAsAsyncSequenceUsingInMultipleTask() async throws {
    let property: AsyncProperty<Int> = .init(initialValue: 1)
    let expect = XCTestExpectation()

    Task {
      // visit
      var results = [Int]()
      for await value in property {
        results.append(value)
        if results.count == 5 {
          break
        }
      }
      print(results)
      XCTAssert(results == [0, 1, 2, 3, 4])
    }

    await Task.yield()

    Task {
      // visit
      var results = [Int]()
      for await value in property {
        results.append(value)
        if results.count == 3 {
          break
        }
      }
      print(results)
      XCTAssert(results == [0, 1, 2])
    }

    await Task.yield()

    Task {
      for value in 0..<6 {
        property.update(value)
        try await Task.sleep(for: .seconds(0.01))
      }
      expect.fulfill()
    }
    await fulfillment(of: [expect], timeout: 1)
  }

  @available(iOS 16.0, *)
  func testAsyncPropertyDriven() async throws {
    let property: AsyncProperty<Int> = .init(initialValue: 1)
    let expect = XCTestExpectation()
    let driveStream = AsyncStream<Int>.makeStream()
    property.drive(by: driveStream.stream)
    let (stream, token) = property.subscribe()

    Task {
      // observe
      var results = [Int]()
      for await value in stream {
        results.append(value)
      }
      XCTAssert(results == [0, 1, 2, 3, 4])
      expect.fulfill()
    }
    await Task.yield()
    Task {
      try await Task.sleep(for: .seconds(0.1))

      for value in 0..<5 {
        driveStream.continuation.yield(value)
      }
      driveStream.continuation.finish()
      token.unsubscribe()
    }
    await fulfillment(of: [expect], timeout: 1)
  }

  @available(iOS 16.0, *)
  func testAsyncThrowingSignalStream1() async throws {
    let stream: AsyncThrowingSignalStream<Int> = .init()

    let expect = XCTestExpectation()

    Task.detached {
      try await Task.sleep(for: Duration.seconds(0.1))
      stream.send(signal: 1)

      try await Task.sleep(for: Duration.seconds(0.1))
      stream.send(signal: 2)
    }

    Task {
      let one = try await stream.wait { $0 == 1 }
      print("get one")
      XCTAssert(one == 1)
      let two = try await stream.wait { $0 == 2 }
      print("get two")
      XCTAssert(two == 2)

      expect.fulfill()
    }

    await fulfillment(of: [expect], timeout: 1)
  }

  enum InternalError: Error {
    case testError
  }

  // test send error
  @available(iOS 16.0, *)
  func testAsyncThrowingSignalStream2() async throws {
    let stream: AsyncThrowingSignalStream<Int> = .init()

    Task.detached {
      try await Task.sleep(for: Duration.seconds(0.2))
      stream.send(signal: 1)

      try await Task.sleep(for: Duration.seconds(0.2))
      stream.send(error: InternalError.testError)
    }

    let task = Task {
      let one = try await stream.wait { $0 == 1 }
      print("get one")
      XCTAssert(one == 1)

      _ = try await stream.wait { $0 == 2 }
      print("won't run the following code")
      XCTAssert(false)
    }

    switch await task.result {
    case .failure(let error):
      guard let error = error as? InternalError else {
        XCTAssert(false)
        return
      }
      XCTAssert(error == InternalError.testError)
    default:
      break
    }
  }

  var stream: AsyncThrowingSignalStream<Int> = .init()

  // Test deinit.
  @available(iOS 16.0, *)
  func testAsyncThrowingSignalStreamDealloc() async throws {
    let expect = XCTestExpectation()
    let task = Task {
      _ = try await stream.weakWait { $0 == 1 }()
      XCTAssert(false)
    }

    Task {
      try await Task.sleep(for: Duration.seconds(0.2))
      // stream.invalid()
      stream = .init()

      switch await task.result {
      case .failure(let error):
        guard let error = error as? AsyncThrowingSignalStream<Int>.SignalError else {
          XCTAssert(false)
          return
        }
        XCTAssert(error == .closed)
      default:
        break
      }
      expect.fulfill()
    }
    await fulfillment(of: [expect], timeout: 1)
  }

  var multicaster: AsyncThrowingMulticast<Int> = .init()

  @available(iOS 16.0, *)
  func testAsyncThrowingMulticast1() async throws {

    let expect = XCTestExpectation()
    let (stream, token) = multicaster.subscribe()

    Task {
      var results = [Int]()
      for try await item in stream {
        results.append(item)
      }
      XCTAssert(results.count == 3)
      expect.fulfill()
    }

    await Task.yield()

    Task {
      multicaster.cast(1)
      try await Task.sleep(for: Duration.seconds(0.1))
      multicaster.cast(2)
      try await Task.sleep(for: Duration.seconds(0.1))
      multicaster.cast(3)
      token.unsubscribe()
    }

    await fulfillment(of: [expect], timeout: 1)
  }

  // Test deinit
  @available(iOS 16.0, *)
  func testAsyncThrowingMulticast2() async throws {

    let expect = XCTestExpectation()
    let (stream, token) = multicaster.subscribe()
    token.bindLifetime(to: self)

    Task {
      var results = [Int]()
      for try await item in stream {
        results.append(item)
      }
      XCTAssert(results.count == 1)
      expect.fulfill()
    }

    Task {
      multicaster.cast(1)
      try await Task.sleep(for: Duration.seconds(0.1))
      multicaster = .init()
    }

    await fulfillment(of: [expect], timeout: 1)
  }

  @available(iOS 16.0, *)
  func testAsyncThrowingMulticast3() async throws {
    let expect = XCTestExpectation()
    let (stream1, token1) = multicaster.subscribe()
    let (stream2, _) = multicaster.subscribe()
    token1.bindLifetime(to: self)
    // token2 is not used, so the observer will not run.

    let task = Task {
      var results = [Int]()
      for try await item in stream1 {
        results.append(item)
      }
      XCTAssert(false)
    }

    Task {
      for try await _ in stream2 {
        XCTAssert(false)
      }
    }

    Task {
      multicaster.cast(1)
      try await Task.sleep(for: .seconds(0.1))
      multicaster.cast(error: InternalError.testError)
      multicaster.cast(2)
      try await Task.sleep(for: .seconds(0.1))
      expect.fulfill()
    }

    switch await task.result {
    case .failure(let error):
      guard let error = error as? InternalError else {
        XCTAssert(false)
        return
      }
      XCTAssert(error == InternalError.testError)
    case .success():
      XCTAssert(false)
    }

    await fulfillment(of: [expect])
  }

  var multicaster2: AsyncMulticast<Int> = .init()

  @available(iOS 16.0, *)
  func testAsyncMulticast1() async throws {

    let expect = XCTestExpectation()
    let (stream, token) = multicaster2.subscribe()

    Task {
      var results = [Int]()
      for try await item in stream {
        results.append(item)
      }
      XCTAssert(results.count == 3)
      expect.fulfill()
    }

    Task {
      multicaster2.cast(1)
      try await Task.sleep(for: Duration.seconds(0.1))
      multicaster2.cast(2)
      try await Task.sleep(for: Duration.seconds(0.1))
      multicaster2.cast(3)
      token.unsubscribe()
    }

    await fulfillment(of: [expect], timeout: 1)
  }

  // Test deinit
  @available(iOS 16.0, *)
  func testAsyncMulticast2() async throws {

    let expect = XCTestExpectation()
    let (stream, token) = multicaster2.subscribe()
    token.bindLifetime(to: self)

    Task {
      var results = [Int]()
      for try await item in stream {
        results.append(item)
      }
      XCTAssert(results.count == 1)
      expect.fulfill()
    }

    Task {
      multicaster2.cast(1)
      try await Task.sleep(for: Duration.seconds(0.1))
      multicaster2 = .init()
    }

    await fulfillment(of: [expect], timeout: 1)
  }

  // Test buffer
  @available(iOS 16.0, *)
  func testAsyncMulticast3() async throws {

    let expect = XCTestExpectation()
    let multicaster = AsyncMulticast<Int>(bufferSize: 2)
    let (stream, token) = multicaster.subscribe()
    token.bindLifetime(to: self)

    Task {
      var results = [Int]()
      for try await item in stream {
        results.append(item)
      }
      XCTAssert(results == multicaster.buffer)
      print(multicaster.lastElement() as Any)
      expect.fulfill()
    }

    Task {
      multicaster.cast(1)
      multicaster.cast(2)
      try await Task.sleep(for: Duration.seconds(0.1))
      token.unsubscribe()
    }

    await fulfillment(of: [expect], timeout: 1)
  }

}

@available(iOS 16, *)
class TimeoutTestCases: XCTestCase {
  func testTimeout1() async throws {
    let result = try? await timeoutTask(with: 1 * NSEC_PER_SEC) {
      var count = 0
      while true {
        count += 1
        if count == 100 {
          count = 0
          /// - Important: In this computationally-intensive process, because this process already take
          /// place in this thread and there is no other place for concurrency system to check this task
          /// is cancelled or not, so we must explicitly call `checkCancellaction()`, and better to
          /// `yield()` once for asynchronisely call.
          try Task.checkCancellation()
          await Task.yield()
        }
      }
      XCTAssert(false)
      return "some"
    } onTimeout: {
      print("ext: on timeout")
      XCTAssert(true)
    }

    XCTAssert(result == nil)
  }

  @available(iOS 16.0, *)
  func testTimeout2() async throws {

    let task = Task<String, any Error> {
      var count = 0
      while true {
        count += 1
        if count == 100 {
          count = 0
          /// - Important: In this computationally-intensive process, because this process already take
          /// place in this thread and there is no other place for concurrency system to check this task
          /// is cancelled or not, so we must explicitly call `checkCancellaction()`, and better to
          /// `yield()` once for asynchronisely call.
          try Task.checkCancellation()
          await Task.yield()
        }
      }
      XCTAssert(false)
      return "some"
    }

    do {
      _ = try await task.value(timeout: .seconds(0.2)) {
        print("on timeout")
      }
    } catch {
      print("###", error)
      if let error = error as? TaskError {
        XCTAssert(TaskError.timeout == error)
      } else {
        XCTAssert(false)
      }
    }
  }

  @available(iOS 16.0, *)
  func testTimeout3() async throws {

    let task = Task<String, any Error> {
      try await Task.sleep(for: .seconds(10))
      print("# done")
      return "some"
    }

    Task {
      try await Task.sleep(for: .seconds(0.1))
      print("# cancelling")
      task.cancel()
    }

    do {
      _ = try await task.value(timeout: .seconds(0.2)) {
        print("on timeout")
      }
      print("# value")
      XCTFail()
    } catch {
      print("###", error, await task.result)

      if error is CancellationError {
        XCTAssert(true)
      } else {
        XCTAssert(false)
      }
    }
  }

  @available(iOS 16.0, *)
  func testTimeout4() async throws {

    let task = Task<String, any Error> {
      while true {}
    }

    Task {
      try await Task.sleep(for: .seconds(2))
      print("# cancelling")
      task.cancel()
    }

    do {
      _ = try await task.value(timeout: .seconds(0.1)) {
        print("on timeout")
      }
      print("# value")
      XCTAssert(false)
    } catch {
      print("###", error)
      if let error = error as? TaskError {
        XCTAssert(TaskError.timeout == error)
      } else {
        XCTAssert(false)
      }
    }
  }

  func testNoTimeout() async throws {
    let task = Task {
      try await Task.sleep(for: .seconds(0.1))
      return 1
    }
    let result = try await task.value(timeout: .seconds(2))
    XCTAssert(result == 1)
  }
}

@available(iOS 16, *)
class TaskQueueTestCases: XCTestCase {

  func testNormal() async throws {
    let queue = TaskQueue<Int>()
    var tasks: [Task<Int, Error>] = []
    let assuming = (0..<10).reduce(into: Array<Int>.init()) { $0.append($1) }

    for index in assuming {
      let task = queue.enqueueTask {
        try! await Task.sleep(for: .seconds(0.2))
        print("running", index)
        return index
      }
      tasks.append(task)
    }

    try await Task.sleep(for: .seconds(0.5))
    print("Start to observe.")

    var results: [Int] = []
    for task in tasks {
      results.append(try await task.value)
    }

    XCTAssert(results == assuming)
  }

  func testThrowingQueue() async throws {
    let queue = ThrowingTaskQueue<Int, Swift.Error>()
    let task = queue.enqueueTask {
      return .failure(NSError(domain: "1", code: 1))
    }
    if case .failure = try await task.value {
      XCTAssertTrue(true)
    } else {
      XCTAssertTrue(false)
    }
  }

  func testOrder() async {
    let queue = TaskQueue<Int>()

    var counts = 0
    let getCounts: () -> Int = {
      counts += 1
      return counts
    }

    async let result1 = queue.task {
      print("run 1")
      return getCounts()  // 2
    }
    async let result2 = queue.task {
      print("run 2")
      return getCounts()  // 3
    }

    //        print(await result1, await result2)

    let result3 = await queue.task {
      print("run 3")
      return getCounts()  // 1
    }
    let result4 = await queue.task {
      print("run 4")
      return getCounts()  // 4
    }

    print(result3, result4)
    print(await result2, await result1)

    // !! REDICULOUS !!
    // run 1 and run 2 are randomly inserted between `run 3` and `run 4`
  }

  func testOrder2() async {
    let queue = TaskQueue<Int>()

    var counts = 0
    let getCounts: () -> Int = {
      counts += 1
      return counts
    }

    var order: [Int] = []

    let result1 = await queue.task {
      print("run 1")
      let value = getCounts()
      order.append(value)
      return value
    }
    let result2 = await queue.task {
      print("run 2")
      let value = getCounts()
      order.append(value)
      return value
    }

    let result3 = await queue.task {
      print("run 3")
      let value = getCounts()
      order.append(value)
      return value
    }
    let result4 = await queue.task {
      print("run 4")
      let value = getCounts()
      order.append(value)
      return value
    }

    print(result1, result2, result3, result4)

    XCTAssert(order == [1, 2, 3, 4])
  }

  var queue: TaskQueue<Int>? = .init()

  func testDeallocation1() async {
    self.queue = TaskQueue<Int>()

    let expect = XCTestExpectation()
    Task {
      let result = await self.queue?.task {
        do {
          try await Task.sleep(for: .seconds(0.2))
        } catch {
          print("error", error)
        }
        XCTAssert(self.queue == nil)
        return 1
      }
      XCTAssert(result == 1)
      expect.fulfill()
    }

    Task {
      try await Task.sleep(for: .seconds(0.1))
      self.queue = nil
      print("set to nil")
    }
    await fulfillment(of: [expect], timeout: 1)
  }

  func testDeallocation3() async throws {
    let expect = XCTestExpectation()
    self.queue = TaskQueue<Int>()

    let op1: () async -> Int = {
      do { try await Task.sleep(for: .seconds(99)) } catch { print("#1 error", error) }
      print(self.queue == nil)
      return 1
    }
    let op2: () async -> Int = {
      do { try await Task.sleep(for: .seconds(3)) } catch { print("#2 error", error) }
      print(self.queue == nil)
      return 2
    }

    if let _ = self.queue?.enqueueTask(task: op1),
      let task2 = self.queue?.enqueueTask(task: op2)
    {

      Task {
        try await Task.sleep(for: .seconds(0.2))
        weak var tempQueue = self.queue
        self.queue = nil
        print("set to nil", tempQueue as Any)
      }
      Task {
        do {
          print(try await task2.value)
          XCTAssert(false)
        } catch {
          print("waited an error: \(error)")
          expect.fulfill()
        }
      }
    }

    await fulfillment(of: [expect], timeout: 10)
  }

  func testDeallocation4() async throws {
    let expect = XCTestExpectation()
    self.queue = TaskQueue<Int>()

    if let queue = self.queue {
      queue.addTask {
        try! await Task.sleep(for: .seconds(0.2))
        return 1
      } onFinished: { result in
        do {
          let result = try result.get()
          XCTAssert(result == 1)
        } catch {
          XCTAssert(false)
        }
        expect.fulfill()
      }

      queue.addTask {
        try! await Task.sleep(for: .seconds(3))
        return 2
      } onFinished: { result in
        do {
          _ = try result.get()
          XCTAssert(false)
        } catch {
          XCTAssert(error is CancellationError)
        }
      }

      Task {
        try await Task.sleep(for: .seconds(0.1))
        print("set to nil")
        self.queue = nil
      }
    }

    await fulfillment(of: [expect], timeout: 1)
  }

  func testMetricsData() async throws {
    let queue = TaskQueue<Int>()

    let id1 = UUID()
    let task1 = queue.enqueueTask(id: id1) {
      try await Task.sleep(for: .seconds(0.1))
      print("\(id1) done")
      return 1
    }

    let id2 = UUID()
    let task2 = queue.enqueueTask(id: id2) {
      try await Task.sleep(for: .seconds(0.2))
      print("\(id2) done")
      return 2
    }

    print(try await task1.value, try await task2.value)

    let met1 = queue.retreiveTaskMetrics(id: id1)
    let met2 = queue.retreiveTaskMetrics(id: id2)

    print(met1!.description)
    print(met2!.description)
  }
}

@available(iOS 16, *)
class TaskPriorityQueueTestCases: XCTestCase {

  func testPriorityQueue() async throws {
    let expect = XCTestExpectation()
    let queue = TaskPriorityQueue<Void>()
    var results: [Int] = []

    queue.enqueueTask(priority: .medium) {
      print("enter task 1")
      try await Task.sleep(for: .seconds(0.1))
      results.append(1)
    }

    await Task.yield()

    queue.enqueueTask(priority: .low) {
      print("enter task 3")
      try await Task.sleep(for: .seconds(0.1))
      results.append(3)
    }
    await Task.yield()
    queue.enqueueTask(priority: .low) {
      print("enter task 4")
      try await Task.sleep(for: .seconds(0.1))
      results.append(4)
      expect.fulfill()
    }
    await Task.yield()
    queue.enqueueTask(priority: .high) {
      print("enter task 2")
      try await Task.sleep(for: .seconds(0.1))
      results.append(2)
    }

    await fulfillment(of: [expect], timeout: 2)
    print("results: \(results)")
    XCTAssert(results.count == 4 && results == [1, 2, 3, 4])
  }

  func testSamePriority() async throws {
    let expect = XCTestExpectation()
    let queue = TaskPriorityQueue<Void>()
    var results: [Int] = []

    queue.enqueueTask {
      print("enter task 1")
      try await Task.sleep(for: .seconds(0.1))
      results.append(1)
    }

    queue.enqueueTask {
      print("enter task 2")
      try await Task.sleep(for: .seconds(0.1))
      results.append(2)
      expect.fulfill()
    }
    await fulfillment(of: [expect], timeout: 1)
    print("results: \(results)")
    XCTAssert(results.count == 2 && results == [1, 2])
  }

  var queue: TaskPriorityQueue<Void>? = nil
  func testDeallocate() async throws {
    let expect = XCTestExpectation()
    self.queue = TaskPriorityQueue<Void>()
    Task {
      let task1 = queue?.enqueueTask {
        print("enter task 1")
        try await Task.sleep(for: .seconds(0.3))
        XCTAssert(self.queue == nil)
      }

      let task2 = queue?.enqueueTask {
        print("enter task 2")
        XCTFail()
      }

      let error = await task2?.result.error()
      XCTAssert(error is CancellationError)

      let error1 = await task1?.result.error()
      // The task is running won't get cancelled, so there's no error.
      XCTAssert(error1 == nil)

      expect.fulfill()
    }

    Task {
      try await Task.sleep(for: .seconds(0.1))
      self.queue = nil
    }

    await fulfillment(of: [expect], timeout: 1)
    XCTAssert(self.queue == nil)
  }
}

@available(iOS 16, *)
class AsyncOperationTestCases: XCTestCase {

  func testOperation() async throws {
    let operation: AsyncOperation<Int> = .init {
      try await Task.sleep(for: .seconds(0.1))
      return 1
    }

    let result = try await operation.start()
    XCTAssert(result == 1)
  }

  func testOperationMultipleEntry() async throws {
    let operation: AsyncOperation<Int> = .init {
      try await Task.sleep(for: .seconds(0.1))
      return 1
    }

    Task {
      let result = try await operation.start()
      XCTAssert(result == 1)
    }

    await Task.yield()

    let multientryTask = Task {
      return try await operation.start()
    }

    if case .success(let value) = await multientryTask.result {
      print(value)
      XCTAssert(value == 1)
    }
  }

  func testFlatMap() async throws {
    let operation1: AsyncOperation<Int> = .init {
      print("Enter 1")
      try await Task.sleep(for: .seconds(0.1))
      print("Ending 1")
      return 1
    }

    let operation2 = operation1.flatMap { result in
      return .init {
        print("Enter 2")
        try await Task.sleep(for: .seconds(0.1))
        print("Ending 2")
        return result + 1
      }
    }

    let result = try await operation2.start()

    XCTAssert(result == 2)
  }

  func testMap() async throws {
    let operation1: AsyncOperation<Int> = .init {
      print("Enter 1")
      try await Task.sleep(for: .seconds(0.1))
      print("Ending 1")
      return 1
    }

    let operation2 =
      operation1
      .flatMap { result in
        return .init {
          print("Enter 2")
          try await Task.sleep(for: .seconds(0.1))
          print("Ending 2")
          return result + 1
        }
      }
      .map { value in
        value + 1
      }

    let result = try await operation2.start()

    XCTAssert(result == 3)
  }

  func testCombine() async throws {
    let operation1: AsyncOperation<Int> = .init {
      print("Enter 1")
      try await Task.sleep(for: .seconds(0.1))
      print("Ending 1")
      return 1
    }

    let operation2: AsyncOperation<Int> = .init {
      print("Enter 2")
      try await Task.sleep(for: .seconds(0.1))
      print("Ending 2")
      return 2
    }
    let combined = operation1.combine(operation2)
    let result = try await combined.start()

    XCTAssert(result == (1, 2))
  }

  func testCombines() async throws {
    let operation1: AsyncOperation<Int> = .init {
      print("Enter 1")
      try await Task.sleep(for: .seconds(0.2))
      print("Ending 1")
      return 1
    }

    let operation2: AsyncOperation<Int> = .init {
      print("Enter 2")
      try await Task.sleep(for: .seconds(0.1))
      print("Ending 2")
      return 2
    }

    let combined = AsyncOperation.combine([operation1, operation2])
    let result = try await combined.start()

    XCTAssert(result == [1, 2])
  }

  func testMapError() async throws {
    let operation1: AsyncOperation<Int> = .error(InternalError.test)
    let operation2 = operation1.mapError { error in
      XCTAssert((error as! InternalError) == .test)
      return .value(1)
    }

    let result = try await operation2.start()
    XCTAssert(result == 1)
  }

  func testRetry() async throws {
    var counter = 0
    let operation1: AsyncOperation<Int> = .error(InternalError.test)
      .map { $0 + 1 }
      .on(error: { error in
        print("Get error \(error) in operation 1, date \(Date())")
        XCTAssert(error is InternalError)
        counter += 1
      })
      .retry(times: 3, interval: 0.1)
    let result = await operation1.startWithResult()
    XCTAssert(result.error() != nil)
    XCTAssert(counter == 4)
  }

  func testMultipleTransformation() async throws {
    let operation1: AsyncOperation<Int> = .init {
      print("Enter 1")
      try await Task.sleep(for: .seconds(0.1))
      print("Ending 1")
      return 1
    }
    .on(
      value: { value in
        print("Get value \(value) in operation 1")
      },
      error: { error in
        print("Get error \(error) in operation 1")
      })

    let operation2 =
      operation1
      .flatMap { _ in
        return .init {
          print("Enter 2")
          try await Task.sleep(for: .seconds(0.1))
          print("Ending 2")
          return 2
        }
      }
      .combine(operation1)
      .map(+)
      .mapError { error in
        print("Get error \(error) in operation 2")
        return .value(0)
      }
      .metrics { metrics in
        print("Metrics \(metrics)")
      }
      .retry(times: 1, interval: 5)
      .timeout(after: 10)

    let result = try await operation2.start()
    XCTAssert(result == 3)

    let result1 = await operation1.startWithResult()
    XCTAssert(result1.error() == nil)
  }

  func testMetrics() async throws {
    let operation1: AsyncOperation<Int> = .init {
      print("Enter 1")
      try await Task.sleep(for: .seconds(0.1))
      print("Ending 1")
      return 1
    }
    .metrics { metrics in
      print("Metrics \(metrics)")
      XCTAssert(metrics.duration! > 0.09)
    }

    let result = try await operation1.start()
    XCTAssert(result == 1)
  }

  func testTimeout() async throws {
    let operation: AsyncOperation<Int> = .init {
      print("Enter 1")
      try await Task.sleep(for: .seconds(2))
      print("Ending 1")
      return 1
    }
    .timeout(after: 0.1)

    let result = await operation.startWithResult()
    if let error = result.error() as? TaskError {
      print("Got timeout error \(error)")
      XCTAssert(error == .timeout)
    } else {
      XCTAssert(false)
    }
  }

  func testCheckAfter() async throws {
    var checked = false
    let operation: AsyncOperation<Int> = .init {
      var counter = 0
      print("start")
      while counter < 100_000_000 { counter += 1 }
      print("end")
      return counter
    }
    .check(
      after: 0.1,
      handler: {
        print("checked")
        checked = true
      })

    let result = await operation.startWithResult()
    print(try result.get())

    XCTAssert(checked == true)
  }

  func testCheckAfterNotReached() async throws {
    let operation: AsyncOperation<Int> = .init {
      return 1
    }
    .check(after: 1) {
      XCTAssert(false)
    }

    let result = await operation.startWithResult()
    print(try result.get())
  }

  func testMergeOperator() async throws {
    let operation1: AsyncOperation<Int> = .init {
      print("Enter 1")
      try await Task.sleep(for: .seconds(0.1))
      print("Ending 1")
      return 1
    }

    let operation2: AsyncOperation<Int> = .init {
      print("Enter 2")
      try await Task.sleep(for: .seconds(0.1))
      print("Ending 2")
      return 2
    }

    let mergedStream = AsyncOperation.merge([operation1, operation2])
    var iterator = mergedStream.makeAsyncIterator()
    var results: [Int] = []
    while let value = try await iterator.next() {
      print("Got value \(value)")
      results.append(value)
    }

    XCTAssert(results == [1, 2])
  }

  func testMergeDeallocation() async throws {
    let expectation = expectation(description: "Merge dealloc")

    Task {
      let operation1: AsyncOperation<Int> = .init { fatalError() }
      let operation2: AsyncOperation<Int> = .init { fatalError() }
      let mergedStream = AsyncOperation.merge([operation1, operation2])
      _ = mergedStream.makeAsyncIterator()
    }

    await Task.yield()

    Task {
      try await Task.sleep(for: .seconds(0.1))
      expectation.fulfill()
    }

    await fulfillment(of: [expectation], timeout: 1)
  }
}

@available(iOS 16, *)
class AsyncOperationQueueTestCases: XCTestCase {

  func testOrder() async throws {
    let queue = AsyncOperationQueue()
    let order: ActorAtomic<[Int]> = .init(value: [])
    Task {
      print("Running task 1")
      let result = try await queue.operation {
        print("enter operation 1")
        await order.modify { $0.append(1) }
        try await Task.sleep(for: .seconds(0.2))
        print("after sleep operation 1")
        await order.modify { $0.append(2) }
        return 1
      }
      print("Get result \(result)")
    }

    await Task.yield()

    let task2 = Task {
      print("Running task 2")
      let result = try await queue.operation {
        print("enter operation 2")
        await order.modify { $0.append(3) }
        try await Task.sleep(for: .seconds(0.1))
        print("after sleep operation 2")
        await order.modify { $0.append(4) }
        return 2
      }
      print("Get result \(result)")
    }

    _ = await task2.result
    await order.with {
      XCTAssert($0 == [1, 2, 3, 4])
    }
  }

  func testConcurrentQueue() async throws {
    let queue = AsyncOperationQueue(mode: .concurrent(limit: 2))
    let expect = XCTestExpectation()

    for i in 0...10 {
      Task {
        print("Running task \(i)")
        let result = try await queue.operation {
          print("enter operation \(i)")
          try await Task.sleep(for: .seconds(0.1))
          print("after sleep operation \(i)")
          return i
        }
        print("Get result \(result)")
        if result == 10 {
          expect.fulfill()
        }
      }
      try await Task.sleep(for: .seconds(0.01))
    }
    // 11 tasks, 2 concurrent at a time, total cost must be less than 1.1s
    await fulfillment(of: [expect], timeout: 0.8)
  }
}
