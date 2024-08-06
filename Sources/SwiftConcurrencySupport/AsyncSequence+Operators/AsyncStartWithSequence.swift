//
//  AsyncStartWithSequence.swift
//
//  Created by Klein
//  Copyright © 2024 Klein. All rights reserved.
//

import Foundation

/// A sequence that emits the first `prefix` elements of the base sequence.
@frozen
public struct AsyncStartWithSequence<Base: AsyncSequence>: AsyncSequence {

  public typealias Element = Base.Element
  public typealias AsyncIterator = Iterator

  let base: Base
  let `prefix`: [Base.Element]

  public struct Iterator: AsyncIteratorProtocol {
    var iterator: Base.AsyncIterator
    var prefixValue: [Element]

    public mutating func next() async rethrows -> Element? {
      if !prefixValue.isEmpty {
        return prefixValue.removeFirst()
      } else {
        return try await iterator.next()
      }
    }
  }

  public func makeAsyncIterator() -> Iterator {
    Iterator(iterator: base.makeAsyncIterator(), prefixValue: prefix)
  }

}

extension AsyncSequence {
  /// Returns a sequence that emits the first `prefix` elements before the base sequence.
  /// - Parameter prefix: The first elements to emit.
  /// - Returns: The result sequence.
  public func start(with prefix: Element) -> AsyncStartWithSequence<Self> {
    AsyncStartWithSequence(base: self, prefix: [prefix])
  }

  /// Returns a sequence that emits the first `prefix` elements before the base sequence.
  /// - Parameter prefix: The first elements to emit.
  /// - Returns: The result sequence.
  public func start(with prefix: [Element]) -> AsyncStartWithSequence<Self> {
    AsyncStartWithSequence(base: self, prefix: prefix)
  }
}

extension AsyncStartWithSequence: Sendable where Base: Sendable, Base.Element: Sendable {}

@available(*, unavailable)
extension AsyncStartWithSequence.Iterator: Sendable {}
