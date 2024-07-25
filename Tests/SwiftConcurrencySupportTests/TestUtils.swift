//
//  TestUtils.swift
//  SwiftConcurrencySupport-Unit-Tests
//
//  Created by KelanJiang on 2024/7/3.
//

import Foundation
import RxCocoa
import RxSwift

#if canImport(SwiftConcurrencySupport)
  @testable import SwiftConcurrencySupport
#endif

extension Observable {

  /// Create an Observable using a concurrency task.
  /// - Parameter op: The concurrency task closure.
  @available(iOS 13, *)
  public static func task(_ op: @Sendable @escaping () async throws -> Element) -> Observable<Element> {
    return Self.create { ob -> Disposable in
      let task = Task {
        do {
          ob.onNext(try await op())
          ob.onCompleted()
        } catch {
          ob.onError(error)
        }
      }
      return Disposables.create {
        task.cancel()
      }
    }
  }
}

@available(iOS 13, *)
extension UnsubscribeToken {

  /// Extern lifetime corresponding to an object.
  /// - Parameter object: An object.
  public func bindLifetime(to object: AnyObject) {
    let reactive = Reactive(object)
    reactive.deallocating
      .subscribe(onNext: { [weak self] _ in
        self?.unsubscribe()
      })
      .disposed(by: reactive.lifetime)
  }
}

extension Reactive where Base: AnyObject {

  var lifetime: DisposeBag {
    guard let disposeBag = objc_getAssociatedObject(self.base, #function) as? DisposeBag else {
      let disposeBag = DisposeBag.init()
      objc_setAssociatedObject(self.base, #function, disposeBag, .OBJC_ASSOCIATION_RETAIN_NONATOMIC)
      return disposeBag
    }
    return disposeBag
  }
}

extension Result {

  func error() -> Failure? {
    switch self {
    case .success(_):
      return nil
    case .failure(let failure):
      return failure
    }
  }
}

struct AsyncSkipRepeatsStream<T: Equatable>: AsyncSequence {
  let stream: AsyncStream<T>
  typealias Element = T

  struct Iterator: AsyncIteratorProtocol {
    var baseIterator: AsyncStream<T>.AsyncIterator
    var last: T?

    mutating func next() async throws -> T? {
      while let next = await baseIterator.next() {
        if next != last {
          last = next
          return next
        }
      }
      return nil
    }
  }

  func makeAsyncIterator() -> Iterator {
    Iterator(baseIterator: stream.makeAsyncIterator())
  }

  init<S: AsyncSequence>(_ sequence: S) where S.Element == T {
    stream = .init(sequence)
  }
}

extension AsyncSequence where Element: Equatable {
  func skipRepeats() -> AsyncSkipRepeatsStream<Element> {
    return AsyncSkipRepeatsStream(self)
  }
}

// extension AsyncStream {
//   func map<T>(_ conversion: @escaping (Element) -> T) -> AsyncStream<T> {
//     var iterator = self.makeAsyncIterator()
//     return .init {
//       if let value = await iterator.next() {
//         return conversion(value)
//       }
//       return nil
//     }
//   }
// }

private func foo<T>(stream: AsyncStream<T>) async {
  let result: AsyncFilterSequence<AsyncMapSequence<AsyncStream<T>, T>> = stream.map { return $0 }
    .filter { _ in true }

  var iterator = result.makeAsyncIterator()
  while let value = await iterator.next() {
    print(value)
  }
}
