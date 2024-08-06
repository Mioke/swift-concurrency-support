//
//  AsyncSequence+Support.swift
//  SwiftConcurrencySupport
//
//  Created by Klein
//  Copyright © 2024 Klein. All rights reserved.
//

extension AsyncSequence {

  /// Returns the next element in the sequence, or `nil` if the sequence closes.
  /// - Returns: The next possible element.
  public func next() async rethrows -> Element? {
    var iterator = makeAsyncIterator()
    return try await iterator.next()
  }

  /// Collect all elements in the sequence until the sequence closes.
  /// - Returns: An array of elements.
  public func collect() async rethrows -> [Element] {
    try await reduce(into: [Element]()) {
      $0.append($1)
    }
  }

}
