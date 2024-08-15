import Darwin
import Dispatch
import Foundation
import XCTest
import os

#if canImport(SwiftConcurrencySupport)
  @testable import SwiftConcurrencySupport
#endif

class SemaphoreTestCases: XCTestCase {

  func testLogic() async throws {
    let semaphore = SwiftConcurrencySupport.Semaphore(value: 0)
    let expect = XCTestExpectation()

    Task {
      print("enter task 1")
      await semaphore.wait()
      print("ending task 1")

      expect.fulfill()
    }

    Task {
      try await Task.sleep(for: .seconds(0.05))
      print("enter task 2")
      await semaphore.signal()
      print("ending task 2")
    }

    await fulfillment(of: [expect], timeout: 1)
  }

  func testHeavyLoad() async throws {
    let semaphore = SwiftConcurrencySupport.Semaphore(value: 10)
    
    @Sendable
    func run() async throws {
      await semaphore.wait()
      try await Task.sleep(for: .seconds(0.01))
      await semaphore.signal()
    }

    let expect1 = XCTestExpectation()
    let expect2 = XCTestExpectation()

    Task {
      for _ in 0...10 {
        try await run()
      }
      expect1.fulfill()
    }

    Task {
      for _ in 0...10 {
        try await run()
      }
      expect2.fulfill()
    }

    await fulfillment(of: [expect1, expect2], timeout: 15)
  }

}
