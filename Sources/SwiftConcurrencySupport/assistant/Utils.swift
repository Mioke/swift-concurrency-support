//
//  Atomic.swift
//  MIOSwiftyArchitecture
//
//  Created by Klein on 2022/6/9.
//

@Sendable
public func checkAround<T>(
  _ checks: () throws -> Void,
  around operation: () async throws -> T
) async throws -> T {
  try checks()
  let result = try await operation()
  try checks()
  return result
}

public func checkNil<T: AnyObject>(_ object: T, throwing: Swift.Error) -> () throws -> Void {
  let weakObject = WeakObject(referencing: object)
  return { if weakObject.isDeallocated { throw throwing } }
}

/**
 Creates a generic class `WeakObject` that holds a weak reference to an object of type `T: AnyObject`.
 
 ## Example usage:
 ```swift
 let object = SomeClass()
 let weakObject = WeakObject(referencing: object)
 ```
 
 - Note: The `WeakObject` class is designed to hold a weak reference to an object, allowing the object to be 
 deallocated if there are no strong references to it.
 
 - Parameters:
    - referencing: The object to be weakly referenced.
 
 - SeeAlso: `weak var reference: T?`
 - SeeAlso: `var isDeallocated: Bool`
 */
public final class WeakObject<T: AnyObject> {
  public weak var reference: T?

  public init(referencing: T) {
    self.reference = referencing
  }

  public var isDeallocated: Bool { reference == nil }
}
