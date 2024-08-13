//
//  Atomic.swift
//  MIOSwiftyArchitecture
//
//  Created by Klein on 2022/6/9.
//

import Darwin
import Foundation
import os

protocol Protectable {
  func around<T>(_ closure: () -> T) -> T
}

final class UnfairLock {
  private let _lock: os_unfair_lock_t

  init() {
    _lock = .allocate(capacity: 1)
    _lock.initialize(to: os_unfair_lock())
  }

  func lock() {
    os_unfair_lock_lock(_lock)
  }

  func unlock() {
    os_unfair_lock_unlock(_lock)
  }

  func `try`() -> Bool {
    return os_unfair_lock_trylock(_lock)
  }

  func around<T>(_ closure: () -> T) -> T {
    lock()
    defer { unlock() }
    return closure()
  }

  deinit {
    _lock.deinitialize(count: 1)
    _lock.deallocate()
  }
}

final class RwLock {

  enum Exception: Swift.Error {
    case lockFailed(internalStatus: Int32)
  }

  private var _lock: pthread_rwlock_t = .init()

  init() {
    pthread_rwlock_init(&_lock, nil)
  }

  @discardableResult
  func readLock() -> Bool {
    pthread_rwlock_rdlock(&_lock) == 0
  }

  @discardableResult
  func writeLock() -> Bool {
    pthread_rwlock_wrlock(&_lock) == 0
  }

  func tryReadLock() throws {
    let status = pthread_rwlock_tryrdlock(&_lock)
    if status == EBUSY || status == EINVAL || status == EDEADLK {
      throw RwLock.Exception.lockFailed(internalStatus: status)
    }
  }

  func tryWriteLock() throws {
    let status = pthread_rwlock_trywrlock(&_lock)
    if status == EBUSY || status == EINVAL || status == EDEADLK {
      throw RwLock.Exception.lockFailed(internalStatus: status)
    }
  }

  @discardableResult
  func unlock() -> Bool {
    let status = pthread_rwlock_unlock(&_lock)
    // Error: EINVAL (not initialized), EPERM (doesn't own the lock)
    return status == 0
  }

  func write<T>(_ closure: () throws -> T) rethrows -> T {
    let rst = writeLock()
    defer { if rst { unlock() } }
    return try closure()
  }

  func read<T>(_ closure: () throws -> T) rethrows -> T {
    let rst = readLock()
    defer { if rst { unlock() } }
    return try closure()
  }

  deinit {
    pthread_rwlock_destroy(&_lock)
  }
}

/// Wrapper of a value to protect it from data race.
/// @Discussion:
/// But this can't ensure the result is correct and atomic, for example:
///  ```swift
///  @ThreadSafe
///  var array: [Int] = []
///
///  queue1.async {
///      self.array += [1]
///  }
///  queue2.async {
///      self.array += [1]
///  }
/// ```
/// The result could be randomly different. So use `read(_:)` or `write(_:)` functions to ensure all the logic is protected.
@propertyWrapper
@dynamicMemberLookup
final class ThreadSafe<T> {
  private var value: T
  private let _lock: RwLock = .init()

  var wrappedValue: T {
    get {
      return _lock.read { return value }
    }
    set {
      _lock.write { value = newValue }
    }
  }

  init(wrappedValue: T) {
    self.value = wrappedValue
  }

  subscript<Property>(dynamicMember keyPath: WritableKeyPath<T, Property>) -> Property {
    get { _lock.read { value[keyPath: keyPath] } }
    set { _lock.write { value[keyPath: keyPath] = newValue } }
  }

  subscript<Property>(dynamicMember keyPath: KeyPath<T, Property>) -> Property {
    _lock.read { value[keyPath: keyPath] }
  }

  /// Synchronously read or transform the contained value.
  func read<U>(_ closure: (T) throws -> U) rethrows -> U {
    try _lock.read { try closure(self.value) }
  }

  /// Synchronously modify the protected value.
  @discardableResult
  func write<U>(_ closure: (inout T) throws -> U) rethrows -> U {
    try _lock.write { try closure(&self.value) }
  }
}

final class Atomic<T> {
  private var _value: T
  private let _lock: RwLock = .init()

  init(value: T) {
    self._value = value
  }

  @discardableResult
  func modify<Result>(_ action: (inout T) -> Result) -> Result {
    _lock.write {
      action(&_value)
    }
  }

  @discardableResult
  func swap(_ newValue: T) -> T {
    modify { value in
      let oldValue = value
      value = newValue
      return oldValue
    }
  }

  var value: T {
    _lock.read {
      let copy = _value
      return copy
    }
  }

  var unsafeValue: T {
    let copy = _value
    return copy
  }
}

extension RwLock: Protectable {
  /// Default is using the write lock.
  /// - Parameter closure: Protected operation.
  /// - Returns: The result of the operation.
  func around<T>(_ closure: () -> T) -> T {
    writeLock()
    defer { unlock() }
    return closure()
  }
}

extension UnfairLock: Protectable {}

/// An Actor wrapper which protects the value from data race.
public actor ActorAtomic<T> {
  /// The value to protect.
  public var value: T

  /// Initialize the value.
  /// - Parameter value: The initial value.
  public init(value: T) {
    self.value = value
  }

  /// Modify the value.
  /// - Parameter action: The action to modify the value.
  public func modify(action: (inout T) async throws -> Void) async rethrows {
    var current = value
    try await action(&current)
    value = current
  }

  /// Do actions with the value.
  /// - Parameter action: The action to do.
  /// - Returns: The result of the action.
  public func with<U>(action: (T) async throws -> U) async rethrows -> U {
    try await action(value)
  }
}
