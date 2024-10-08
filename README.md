
# swift-concurrency-support

[![SwiftConcurrencySupport](https://github.com/Mioke/swift-concurrency-support/actions/workflows/swift.yml/badge.svg?branch=master)](https://github.com/Mioke/swift-concurrency-support/actions/workflows/swift.yml)
![Swift Package Manager](https://img.shields.io/badge/Swift%20Package%20Manager-compatible-brightgreen.svg)
![Supported Platforms: iOS, macOS, tvOS, watchOS & Linux](https://img.shields.io/badge/platforms-iOS%20%7C%20macOS%20%7C%20tvOS%20%7C%20watchOS%20%7C%20Linux-333333.svg)

Currently pre-release version, continuously optimizing and adding new features.

## Install

### Using CocoaPods

```ruby
pod 'SwiftConcurrencySupport', :git => 'https://github.com/mioke/swift-concurrency-support.git', :branch => 'master'
```

### Using SPM

```swift
// add package to your dependencies:
.package(url: "https://github.com/Mioke/swift-concurrency-support.git", branch: "master")

// add target dependency:
.product(name: "SwiftConcurrencySupport", package: "swift-concurrency-support")
```

## Index

- [swift-concurrency-support](#swift-concurrency-support)
  - [Install](#install)
    - [Using CocoaPods](#using-cocoapods)
    - [Using SPM](#using-spm)
  - [Index](#index)
  - [Functions](#functions)
    - [Timeout functions for `Task`](#timeout-functions-for-task)
    - [`SemaphoreActor`](#semaphoreactor)
    - [`AsyncMuticast` : Multicaster for a concurrency context](#asyncmuticast--multicaster-for-a-concurrency-context)
    - [`AsyncProperty`: Similar to `Property<T>` in ReactiveSwift](#asyncproperty-similar-to-propertyt-in-reactiveswift)
    - [`AsyncThrowingSignalStream`](#asyncthrowingsignalstream)
    - [`TaskQueue`: Run `Task` one by one, have task metrics when task is finished](#taskqueue-run-task-one-by-one-have-task-metrics-when-task-is-finished)
  - [Functional Programming](#functional-programming)
    - [`AsyncOperation` : Wrapped async operation](#asyncoperation--wrapped-async-operation)
    - [`AsyncOperation.combine` : Combine multiple `AsyncOperation` into one](#asyncoperationcombine--combine-multiple-asyncoperation-into-one)
    - [`AsyncOperation.merge` : Merge multiple `AsyncOperation` into one `AsyncStream`](#asyncoperationmerge--merge-multiple-asyncoperation-into-one-asyncstream)
    - [`AsyncOperationQueue` : Run `AsyncOperation` in serial or concurrent ways, Please see the code detail](#asyncoperationqueue--run-asyncoperation-in-serial-or-concurrent-ways-please-see-the-code-detail)
  - [Other supporting features](#other-supporting-features)
    - [`ActorAtomic<T>`: Locking wrapper implemented by actor](#actoratomict-locking-wrapper-implemented-by-actor)
    - [`AsyncStartWithSequence`: AsyncSequence that starts with values](#asyncstartwithsequence-asyncsequence-that-starts-with-values)
    - [AsyncSequence `eraseToStream()` and `eraseToThrowingStream()`](#asyncsequence-erasetostream-and-erasetothrowingstream)

## Functions

### Timeout functions for `Task`

```swift
let task = Task<String, any Error> {
  var count = 0
  while true { }
  XCTAssert(false)
  return "some"
}

do {
  _ = try await task.value(timeout: .seconds(2)) {
    print("on timeout")
  }
} catch {
  print("###", error)

  if case Task<String, any Error>.CustomError.timeout = error {
    XCTAssert(true)
  } else {
    XCTAssert(false)
  }
}
```

### `SemaphoreActor`

A semaphore implemented by `actor`, can be used to limit the number of concurrent operations or protect data.

```swift
let semaphore = SemaphoreActor(value: 0)

Task {
  await semaphore.wait()
}

Task {
  try await Task.sleep(for: .seconds(0.05))
  await semaphore.signal()
}
```

### `AsyncMuticast` : Multicaster for a concurrency context

Multicaster for a concurrency context, create an `AsyncStream` and a cancel token for the observer when subscribing from this multicaster.

```swift
let (stream, token) = multicaster.subscribe()

Task {
  var results = [Int]()
  for try await item in stream {
    results.append(item)
  }
  XCTAssert(results.count == 3)
  expect.fulfill()
}

Task {
  multicaster.cast(1)
  try await Task.sleep(for: Duration.seconds(2))
  multicaster.cast(2)
  try await Task.sleep(for: Duration.seconds(2))
  multicaster.cast(3)
  token.unsubscribe()
}
```

### `AsyncProperty`: Similar to `Property<T>` in ReactiveSwift

It can subscribe its changes overtime. It also is an `AsyncSequence` so you can transform it with `AsyncSequence`'s operators. It can be driven by other `AsyncSequence` too.

```swift
let property: AsyncProperty<Int> = .init(initialValue: 1)
property.update(2)

let driver = AsyncStream<Int>.makeStream()
property.driven(by: driver.stream)
let (stream, token) = property.subscribe()

Task {
  for i in 0...10 {
    driver.continuation.yeild(value)
  }
}

Task {
  for await changes in stream {
    print("Got \(changes)")
    break
  }
  let transformed = property.map { $0 * 2 }
  let next = await transfromed.first { $0 > 2 }
  XCTAssert(next == 4)

  token.unsubscribe()
}
```

### `AsyncThrowingSignalStream`

(Please see the code detail.)

```swift
let stream: AsyncThrowingSignalStream<Int> = .init()

Task.detached {
  try await Task.sleep(for: Duration.seconds(2))
  stream.send(signal: 1)

  try await Task.sleep(for: Duration.seconds(2))
  stream.send(signal: 2)
}

Task {
  let one = try await stream.wait { $0 == 1 }
  XCTAssert(one == 1)
  let two = try await stream.wait { $0 == 2 }
  XCTAssert(two == 2)
}
```

### `TaskQueue`: Run `Task` one by one, have task metrics when task is finished

```swift
for index in assuming {
  let task = queue.enqueueTask {
    try! await Task.sleep(for: .seconds(1))
    print("running", index)
    return index
  }
  tasks.append(task)
}

let results = try await tasks.asyncMap { try await $0.value }
XCTAssert(results == assuming)

/*
Metrics's log:
id: 6B1802A9-B417-46D7-8AFD-1DDA8EFF3570
  waitingDuration: 1.00012505054473876953
  executionDuration: 1.042160987854004
*/
```

## Functional Programming

### `AsyncOperation` : Wrapped async operation

Provides basic functional programming unit and `flatMap`, `map`, `combine` and lots of operators to manipulate the operation.

```swift
let operation1: AsyncOperation<Int> = .init {
  try await Task.sleep(for: .seconds(2))
  return 1
}
.on(
  value: { value in
    print("Get value \(value) in operation 1")
  },
  error: { error in
    print("Get error \(error) in operation 1")
  })

let operation2 =
  operation1
  .flatMap { _ in
    return .init {
      try await Task.sleep(for: .seconds(1))
      return 2
    }
  }
  .combine(operation1)
  .map(+)
  .mapError { error in
    print("Get error \(error) in operation 2")
    return .value(0)
  }
  .metrics { metrics in
    print("Metrics \(metrics)")
  }
  .retry(times: 1, interval: 5)
  .timeout(after: 10)
  

let result = try await operation2.start()
XCTAssert(result == 3)

let result1 = await operation1.startWithResult()
XCTAssert(result1.error() == nil)
```

### `AsyncOperation.combine` : Combine multiple `AsyncOperation` into one

```swift
let combined = AsyncOperation.combine([operation1, operation2])
let result = try await combined.start()

XCTAssert(result == [1, 3])
```

### `AsyncOperation.merge` : Merge multiple `AsyncOperation` into one `AsyncStream`

```swift
let mergedStream = AsyncOperation.merge([operation1, operation2])
var iterator = mergedStream.makeAsyncIterator()
var results: [Int] = []
while let value = try await iterator.next() {
  print("Got value \(value)")
  results.append(value)
}

XCTAssert(results == [1, 2])
```

### `AsyncOperationQueue` : Run `AsyncOperation` in serial or concurrent ways, Please see the code detail

```swift
let queue = AsyncOperationQueue()

Task {
  let result = try await queue.operation {
    try await Task.sleep(for: .seconds(2))
    return 1
  }
}

Task {
  let result = try await queue.operation {
    try await Task.sleep(for: .seconds(2))
    return 2
  }
}
```

## Other supporting features

### `ActorAtomic<T>`: Locking wrapper implemented by actor

```swift
let protected = ActorAtomic<Bool>.init(value: true)
await protected.with { print($0) }
await protected.modify { $0 = false }
```

### `AsyncStartWithSequence`: AsyncSequence that starts with values

```swift
stream.prefix(with: [1, 2, 3])
```

### AsyncSequence `eraseToStream()` and `eraseToThrowingStream()`

Convert any `AsyncSequence` to `AsyncStream`, preventing the long generics type.

```swift
let earased = stream
  .map { ... }
  .filter { ... }
  .eraseToStream()
```
