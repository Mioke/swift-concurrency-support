import Darwin
import Dispatch
import Foundation
import XCTest
import os

#if canImport(SwiftConcurrencySupport)
  @testable import SwiftConcurrencySupport
#endif

class AsyncMulticastPerformanceTests: XCTestCase {

  func testDeallocationPerformance() async throws {
    var multicaster: AsyncMulticast<Int>? = AsyncMulticast<Int>()
    var streams: [(AsyncStream<Int>, UnsubscribeToken)] = []
    for _ in 0...10000 {
      if let subscriber = multicaster?.subscribe() {
        streams.append(subscriber)
      }
    }
    let start = CFAbsoluteTimeGetCurrent()
    print("before dealloc")
    multicaster = nil
    let cost = CFAbsoluteTimeGetCurrent() - start
    print("after set to nil \(cost)")
    XCTAssert(cost < 0.1)
  }

}
