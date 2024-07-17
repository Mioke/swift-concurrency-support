//
//  Array+Concurrency.swift
//  MIOSwiftyArchitecture
//
//  Created by Klein on 2024/7/2.
//

import Foundation

@available(macOS 10.15, tvOS 13.0, iOS 13.0, watchOS 6.0, *)
extension Array {

  ///  Returns an array containing the results of mapping the given closure over the sequence's elements. The mapping
  ///  closure is asynchrounous function and the trasnform process will await the results one by one.
  /// - Parameter conversion: The transform conversion closure.
  /// - Returns: An array containing the transformed elements of this sequence.
  public func asyncMap<T>(_ conversion: (Element) async throws -> T) async rethrows -> [T] {
    var results: [T] = []
    let copied = self
    for item in copied {
      results.append(try await conversion(item))
    }
    return results
  }

  ///  Returns an array containing the results of mapping the given closure over the sequence's elements. The mapping
  ///  closure is asynchrounous function, and different from ``asyncMap(_:)`` this function will run all the
  ///  conversions asynchronously.
  /// - Parameter conversion: The transform conversion closure.
  /// - Returns: An array containing the transformed elements of this sequence.
  public func concurrentMap<T>(_ conversion: @escaping (Element) async throws -> T) async throws -> [T] {
    var results: [T] = []
    let tasks = map { item in
      Task {
        let result = try await conversion(item)
        try Task.checkCancellation()
        return result
      }
    }
    do {
      for task in tasks {
        results.append(try await task.value)
      }
      return results
    } catch {
      tasks.forEach { $0.cancel() }
      throw error
    }
  }

  ///  Performs the given action on each element of the sequence in a concurrency context.
  /// - Parameter action: The closure to invoke on each element.
  public func asyncForEach(_ action: (Element) async throws -> Void) async rethrows {
    let copied = self
    for item in copied {
      try await action(item)
    }
  }

  /// Returns an array containing the non-nil results of calling the given transformation with each element
  /// of this sequence.
  /// - Parameter conversion: The transform conversion closure.
  /// - Returns: An array containing the transformed non-nil elements of this sequence.
  public func asyncCompactMap<T>(_ conversion: (Element) async throws -> T?) async rethrows -> [T] {
    var results: [T] = []
    let copied = self
    for item in copied {
      if let result = try await conversion(item) {
        results.append(result)
      }
    }
    return results
  }

}
