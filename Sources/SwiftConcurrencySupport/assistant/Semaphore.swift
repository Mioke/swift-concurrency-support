//
//  Semaphore.swift
//  SwiftConcurrencySupport
//
//  Created by Klein on 2024-08-15.
//  Copyright © 2024 Klein. All rights reserved.
//

/// A SemaphoreActor is a synchronization primitive that can be used to control access to a shared resource. 
public actor SemaphoreActor {
  let value: Int
  var current: Int
  var continuations: [UnsafeContinuation<Void, Never>] = []

  /// Creates a new `SemaphoreActor` with the given value.
  /// - Parameter value: The initial value of the semaphore.
  public init(value: Int = 1) {
    self.value = value
    self.current = value
  }

  /// Waits until the semaphore's value is greater than zero.
  public func wait() async {
    current -= 1
    if current < 0 {
      await withUnsafeContinuation { self.continuations.append($0) }
    }
  }

  /// Increments the semaphore's value.
  public func signal() {
    guard current < value else {
      assertionFailure("There is no one waiting on this semaphore.")
      return
    }
    current += 1

    if !continuations.isEmpty {
      let first = continuations.removeFirst()
      first.resume()
    }
  }

  deinit {
    let isSignaled = current == value
    precondition(isSignaled, "Semaphore is not signaled when deinitialized.")
  }
}
