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
    let semaphore = SemaphoreActor(value: 0)
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
    let semaphore = SemaphoreActor(value: 10)
    @Sendable
    func run() async throws {
      await semaphore.wait()
      try await Task.sleep(for: .seconds(0.01))
      await semaphore.signal()
    }

    let expect1 = XCTestExpectation()

    for num in 0...20 {
      Task {
        try await run()
        if num == 20 {
          expect1.fulfill()
        }
      }
    }

    await fulfillment(of: [expect1], timeout: 0.2)
  }

}
