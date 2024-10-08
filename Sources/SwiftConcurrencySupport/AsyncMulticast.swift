//
//  AsyncMulticast.swift
//  MIOSwiftyArchitecture
//
//  Created by Klein on 2024/7/2.
//

import Foundation

// MARK: - AsyncMulticast

@available(macOS 10.15, tvOS 13.0, iOS 13.0, watchOS 6.0, *)
protocol Unsubscribable: AnyObject {
  func unsubscribe(with token: UnsubscribeToken)
}

@available(macOS 10.15, tvOS 13.0, iOS 13.0, watchOS 6.0, *)
public class UnsubscribeToken {
  weak var multicaster: (any Unsubscribable)?

  init(multicaster: any Unsubscribable) {
    self.multicaster = multicaster
  }
  /// Unsubscribe from the multicaster.
  public func unsubscribe() {
    multicaster?.unsubscribe(with: self)
  }

  deinit {
    unsubscribe()
  }
}

/// Multicast values to many observers, observers can await values over time.
@available(macOS 10.15, tvOS 13.0, iOS 13.0, watchOS 6.0, *)
public class AsyncThrowingMulticast<T>: Unsubscribable, @unchecked Sendable {

  typealias Subscriber = (T) -> Void

  @ThreadSafe
  var subscribers: [ObjectIdentifier: (Subscriber, AsyncThrowingStream<T, Error>.Continuation)] =
    [:]

  public let bufferSize: Int

  @ThreadSafe
  internal private(set) var buffer: [T] = []

  /// Create a throwing multicaster.
  /// - Parameter bufferSize: The buffer size of the multicaster.
  public init(bufferSize: Int = 1) {
    assert(bufferSize >= 0, "bufferSize must be greater than or equal to 0")
    self.bufferSize = bufferSize
  }

  /// Get the last element of the multicaster's buffer
  /// - Returns: The last element of the multicaster's buffer if exists.
  public func lastElement() -> T? {
    return _buffer.read { $0.last }
  }

  /// Get the buffer of the multicaster with the given count.
  /// - Parameter count: The count of elents to get.
  /// - Returns: The buffer of the multicaster.
  public func buffer(count: Int? = nil) -> [T] {
    return _buffer.read {
      if let count {
        $0.suffix(count)
      } else {
        $0
      }
    }
  }

  /// Subscribe from this multicaster.
  /// - Parameters:
  ///   - condition: Optional, this condition can help to filter the cast values.
  ///   - bufferingPolicy: The buffering policy of returning stream.
  /// - Returns: An `AsyncThrowingStream` and an unsubscribe token.
  public func subscribe(
    where condition: ((T) -> Bool)? = nil,
    bufferingPolicy: AsyncThrowingStream<T, Error>.Continuation.BufferingPolicy = .unbounded
  )
    -> (stream: AsyncThrowingStream<T, Error>, token: UnsubscribeToken)
  {

    let cancelToken = UnsubscribeToken(multicaster: self)
    let id = ObjectIdentifier(cancelToken)
    let make = AsyncThrowingStream<T, Error>.makeStream(bufferingPolicy: bufferingPolicy)

    let subscriber: Subscriber = { value in
      if condition == nil || condition?(value) == true {
        make.continuation.yield(value)
      }
    }
    _subscribers.write { s in
      s[id] = (subscriber, make.continuation)
    }

    make.continuation.onTermination = { [weak self] termination in
      guard let self else { return }
      _subscribers.write { s -> Void in
        s[id] = nil
      }
    }
    return (stream: make.stream, token: cancelToken)
  }

  /// Unsubscribe from this multicaster.
  /// - Parameter subscriber: Who is unsubscribing.
  func unsubscribe(with token: UnsubscribeToken) {
    let id = ObjectIdentifier(token)
    if let subscriber = _subscribers.read({ $0[id] }) {
      subscriber.1.finish()
    }
  }

  /// Send a value and proadcast it.
  /// - Parameter value: The value.
  public func cast(_ value: T) {
    _buffer.write {
      $0.append(value)
      if $0.count > bufferSize { $0.removeFirst() }
    }
    let subs = subscribers
    subs.forEach { (_, sub: ((T) -> Void, AsyncThrowingStream<T, Error>.Continuation)) in
      sub.0(value)
    }
  }

  /// Send an error to all subscribers, and terminate the for-in loop.
  /// - Parameter error: An error.
  public func cast(error: any Error, keepBuffer: Bool = true) {
    if !keepBuffer { _buffer.write { $0.removeAll() } }
    let subs = subscribers
    subs.forEach { (_, sub: ((T) -> Void, AsyncThrowingStream<T, Error>.Continuation)) in
      sub.1.finish(throwing: error)
    }
  }

  /// Send finish to all subscribers.
  public func finish() {
    let subs = subscribers
    subs.forEach { (_, sub: ((T) -> Void, AsyncThrowingStream<T, Error>.Continuation)) in
      sub.1.finish()
    }
  }

  deinit {
    finish()
  }
}

/// Multicast values to many observers, observers can await values over time.
@available(macOS 10.15, tvOS 13.0, iOS 13.0, watchOS 6.0, *)
public class AsyncMulticast<T>: Unsubscribable, @unchecked Sendable {

  typealias Subscriber = (T) -> Void

  @ThreadSafe
  var subscribers: [ObjectIdentifier: (Subscriber, AsyncStream<T>.Continuation)] = [:]

  public let bufferSize: Int

  @ThreadSafe
  internal private(set) var buffer: [T] = []

  public init(bufferSize: Int = 1) {
    assert(bufferSize >= 0, "bufferSize must be greater than or equal to 0")
    self.bufferSize = bufferSize
  }

  public func lastElement() -> T? {
    return _buffer.read { $0.last }
  }

  /// Get the buffer of the multicaster with the given count.
  /// - Parameter count: The count of elents to get.
  /// - Returns: The buffer of the multicaster.
  public func buffer(count: Int? = nil) -> [T] {
    return _buffer.read {
      if let count {
        $0.suffix(count)
      } else {
        $0
      }
    }
  }

  /// Subscribe from this multicaster.
  /// - Parameters:
  ///   - condition: Optional, this condition can help to filter the cast values.
  ///   - bufferingPolicy: The buffering policy of returning stream.
  /// - Returns: An `AsyncStream` and its finish token.
  public func subscribe(
    where condition: ((T) -> Bool)? = nil,
    bufferingPolicy: AsyncStream<T>.Continuation.BufferingPolicy = .unbounded
  )
    -> (stream: AsyncStream<T>, token: UnsubscribeToken)
  {

    let cancelToken = UnsubscribeToken(multicaster: self)
    let id = ObjectIdentifier(cancelToken)
    let make = AsyncStream<T>.makeStream(bufferingPolicy: bufferingPolicy)

    let subscriber: Subscriber = { value in
      if condition == nil || condition?(value) == true {
        make.continuation.yield(value)
      }
    }
    _subscribers.write { s in
      s[id] = (subscriber, make.continuation)
    }

    make.continuation.onTermination = { [weak self] termination in
      guard let self else { return }
      _subscribers.write { s -> Void in
        s[id] = nil
      }
    }
    return (stream: make.stream, token: cancelToken)
  }

  /// Unsubscribe from this multicaster.
  /// - Parameter subscriber: Who is unsubscribing.
  func unsubscribe(with token: UnsubscribeToken) {
    let id = ObjectIdentifier(token)
    if let subscriber = _subscribers.read({ $0[id] }) {
      subscriber.1.finish()
    }
  }

  /// Send a value and proadcast it.
  /// - Parameter value: The value.
  public func cast(_ value: T) {
    _buffer.write {
      $0.append(value)
      if $0.count > bufferSize { $0.removeFirst() }
    }
    let subs = subscribers
    subs.forEach { (_, sub: ((T) -> Void, AsyncStream<T>.Continuation)) in
      sub.0(value)
    }
  }

  ///  Send finish to all subscribers.
  public func finish() {
    let subs = subscribers
    subs.forEach { (_, sub: ((T) -> Void, AsyncStream<T>.Continuation)) in
      sub.1.finish()
    }
  }

  deinit {
    finish()
  }
}

@available(macOS 10.15, tvOS 13.0, iOS 13.0, watchOS 6.0, *)
extension AsyncStream {

  /// Make a multicaster for this stream. If the task is suspended or released, the multicatser can't receive any
  /// new elements.
  /// - Returns: An observing task and it's multicatster.
  public func makeMulticaster() -> (task: Task<(), Never>, multicaster: AsyncMulticast<Element>) {
    let multicaster = AsyncMulticast<Element>()
    let observingTask = Task { [weak multicaster] in
      var iterator = self.makeAsyncIterator()
      do {
        while let element = await iterator.next() {
          guard let multicaster else { return }
          try Task.checkCancellation()
          multicaster.cast(element)
        }
        multicaster?.finish()
      } catch {
        if error is CancellationError {
          multicaster?.finish()
        }
      }
    }
    return (task: observingTask, multicaster: multicaster)
  }
}

@available(macOS 10.15, tvOS 13.0, iOS 13.0, watchOS 6.0, *)
extension AsyncThrowingStream {

  /// Make a throwing multicaster for this stream. If the task is suspended or released, the multicatser can't
  /// receive any new elements.
  /// - Returns: An observing task and it's multicatster.
  public func makeMulticaster() -> (
    task: Task<Void, Never>, multicaster: AsyncThrowingMulticast<Element>
  ) {
    let multicaster = AsyncThrowingMulticast<Element>()
    let observingTask = Task { [weak multicaster] in
      let copied = self
      var iterator = copied.makeAsyncIterator()
      do {
        while let element = try await iterator.next() {
          guard let multicaster else { return }
          do {
            try Task.checkCancellation()
          } catch {
            multicaster.finish()
            return
          }
          multicaster.cast(element)
        }
        multicaster?.finish()
      } catch {
        multicaster?.cast(error: error)
      }
    }
    return (task: observingTask, multicaster: multicaster)
  }
}

// MARK: - AsyncProperty

/// For the feature like `Property<T>` in `ReactiveSwift`
@available(macOS 10.15, tvOS 13.0, iOS 13.0, watchOS 6.0, *)
final public class AsyncProperty<T>: AsyncSequence {
  public typealias AsyncIterator = Iterator
  public typealias Element = T

  public struct Iterator: AsyncIteratorProtocol {
    var iterator: AsyncStream<T>.AsyncIterator
    let token: UnsubscribeToken

    public mutating func next() async -> T? {
      return await iterator.next()
    }
  }

  let multicaster: AsyncMulticast<T> = .init(bufferSize: 1)
  let initialValue: T

  public func makeAsyncIterator() -> Iterator {
    let subscriber = subscribe()
    return .init(iterator: subscriber.stream.makeAsyncIterator(), token: subscriber.token)
  }

  /// Initialization
  /// - Parameter wrappedValue: initial value.
  public init(initialValue: T) {
    self.initialValue = initialValue
  }

  /// The current value of this property.
  public var value: T {
    return multicaster.lastElement() ?? initialValue
  }

  /// Update the value of this property.
  /// - Parameter newValue: The new value.
  public func update(_ newValue: T) {
    multicaster.cast(newValue)
  }

  /// Drive the changes of this property by a AsyncSequence.
  /// - Parameter sequence: The sequence to drive this property.
  public func driven<S: AsyncSequence>(by sequence: S) where S.Element == T {
    Task {
      for try await element in sequence {
        update(element)
      }
    }
  }

  /// Subscribing the changes of this property.
  /// - Important: the token should be stored some where, otherwise the subscibed stream will be invalid immediately.
  /// - Returns: An async stream and it's invalidation token.
  public func subscribe() -> (stream: AsyncStream<T>, token: UnsubscribeToken) {
    return multicaster.subscribe()
  }
}

extension AsyncProperty: Sendable where T: Sendable {}
