//
//  Atomic.swift
//  MIOSwiftyArchitecture
//
//  Created by Klein on 2022/6/9.
//

/*
  First-in first-out queue (FIFO)

  New elements are added to the end of the queue. Dequeuing pulls elements from
  the front of the queue.

  Enqueuing and dequeuing are O(1) operations.
*/
public struct Queue<T> {
  fileprivate var array = [T?]()
  fileprivate var head = 0

  public var isEmpty: Bool {
    return count == 0
  }

  public var count: Int {
    return array.count - head
  }

  public mutating func enqueue(_ element: T) {
    array.append(element)
  }

  public mutating func dequeue() -> T? {
    guard let element = array[guarded: head] else { return nil }

    array[head] = nil
    head += 1

    let percentage = Double(head) / Double(array.count)
    if array.count > 50 && percentage > 0.25 {
      array.removeFirst(head)
      head = 0
    }

    return element
  }

  public var front: T? {
    if isEmpty {
      return nil
    } else {
      return array[head]
    }
  }
}

extension Array {
  subscript(guarded idx: Int) -> Element? {
    guard (startIndex..<endIndex).contains(idx) else {
      return nil
    }
    return self[idx]
  }
}

public enum PriorityQueuePriority: Int, Comparable, CaseIterable {
  case low = 0
  case medium, high

  public static func < (lhs: Self, rhs: Self) -> Bool {
    return lhs.rawValue < rhs.rawValue
  }
}

public struct PriorityQueue<Element> {
  var queues: [PriorityQueuePriority: Queue<Element>] = [.low: .init(), .medium: .init(), .high: .init()]
  let priorityOrder = PriorityQueuePriority.allCases.sorted(by: >)

  public mutating func enqueue(_ element: Element, priority: PriorityQueuePriority) {
    queues[priority]?.enqueue(element)
  }

  public mutating func dequeue() -> Element? {
    guard let priority = priorityOrder.first(where: { queues[$0]?.isEmpty == false })
    else { return nil }
    return queues[priority]?.dequeue()
  }

  public var count: Int {
    return queues.reduce(0) { $0 + $1.value.count }
  }

  public var isEmpty: Bool {
    return queues.reduce(true) { $0 && $1.value.isEmpty }
  }

  public var front: Element? {
    guard let priority = priorityOrder.first(where: { queues[$0]?.isEmpty == false })
    else { return nil }
    return queues[priority]?.front
  }
}

extension Queue where T: Equatable {
  
  public func contains(_ element: T) -> Bool {
    return array.contains(element)
  }

  mutating public func remove(_ element: T) {
    if let index = array.firstIndex(of: element) {
      array.remove(at: index)
    }
  }
}

extension PriorityQueue where Element: Equatable {

  public func contains(_ element: Element) -> Bool {
    return queues.reduce(false) { $0 || $1.value.contains(element) }
  }

  mutating func remove(_ element: Element) {
    queues = queues.reduce(into: [:]) { (partialResult, content) in
      var queue = content.value
      queue.remove(element)
      partialResult[content.key] = queue
    }
  }
}
