//
//  TestUtils.swift
//  SwiftConcurrencySupport-Unit-Tests
//
//  Created by KelanJiang on 2024/7/3.
//

import Foundation
import RxCocoa
import RxSwift

#if canImport(swift_concurrency_support)
  @testable import swift_concurrency_support
#endif

#if canImport(swift_concurrency_support_test)
  import swift_concurrency_support_test
#endif

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
