import Testing
import Roam

import Foundation

struct LinkedListTests {
    // MARK: - Initialization Tests

    @Test func testEmptyInit() async throws {
        let linkedList = LinkedList<Int>()
        #expect(linkedList.size == 0)
        #expect(linkedList.first == nil)
        #expect(linkedList.last == nil)
    }

    @Test func testSequenceInit() async throws {
        let array = [1, 2, 3, 4, 5]
        let linkedList = LinkedList(array)

        #expect(linkedList.size == array.count)
        #expect(linkedList.first == array.first)
        #expect(linkedList.last == array.last)

        var element = linkedList.removeFirst()
        var i = 1
        while element != nil {
            #expect(element == i)
            element = linkedList.removeFirst()
            i += 1
        }
    }

    @Test func testArrayLiteralInit() async throws {
        let linkedList: LinkedList<Int> = LinkedList([1, 2, 3, 4, 5])

        #expect(linkedList.size == 5)
        #expect(linkedList.first == 1)
        #expect(linkedList.last == 5)
    }

    // MARK: - Append and Prepend Tests

    @Test func testAppend() async throws {
        let linkedList = LinkedList<Int>()

        // Append to empty LinkedList
        linkedList.append(1)
        #expect(linkedList.size == 1)
        #expect(linkedList.first == 1)
        #expect(linkedList.last == 1)

        // Append to non-empty LinkedList
        linkedList.append(2)
        #expect(linkedList.size == 2)
        #expect(linkedList.first == 1)
        #expect(linkedList.last == 2)

        // Append multiple elements
        linkedList.append(3)
        linkedList.append(4)
        #expect(linkedList.size == 4)
        #expect(linkedList.first == 1)
        #expect(linkedList.last == 4)
    }

    // MARK: - Removal Tests

    @Test func testRemoveFirst() async throws {
        let linkedList: LinkedList<Int> = LinkedList([1, 2, 3, 4, 5])

        // Pop first element
        let first = linkedList.removeFirst()
        #expect(first == 1)
        #expect(linkedList.size == 4)
        #expect(linkedList.first == 2)

        // Pop until one element remains
        _ = linkedList.removeFirst()
        _ = linkedList.removeFirst()
        _ = linkedList.removeFirst()
        #expect(linkedList.size == 1)
        #expect(linkedList.first == 5)
        #expect(linkedList.last == 5)

        // Pop last element
        _ = linkedList.removeFirst()
        #expect(linkedList.size == 0)
        #expect(linkedList.first == nil)
        #expect(linkedList.last == nil)

        // Pop from empty LinkedList
        let emptyResult = linkedList.removeFirst()
        #expect(emptyResult == nil)
        #expect(linkedList.size == 0)
    }

    // MARK: - Edge Cases and Stress Tests

    @Test func testEmptyLinkedListOperations() async throws {
        let linkedList = LinkedList<Int>()

        // These should not cause crashes or issues
        #expect(linkedList.first == nil)
        #expect(linkedList.last == nil)
        #expect(linkedList.size == 0)
    }

    @Test func testSingleElementLinkedList() async throws {
        let linkedList = LinkedList<Int>()
        linkedList.append(42)

        #expect(linkedList.size == 1)
        #expect(linkedList.first == 42)
        #expect(linkedList.last == 42)
        #expect(linkedList.first == 42)

        let removed = linkedList.removeFirst()
        #expect(removed == 42)
        #expect(linkedList.size == 0)
    }

    @Test func testResizeGrowth() async throws {
        let linkedList = LinkedList<Int>()

        // Add more elements than the initial capacity
        for i in 1...100 {
            linkedList.append(i)
        }

        #expect(linkedList.size == 100)

        var element = linkedList.removeFirst()
        var i = 0
        while element != nil {
            #expect(element == i + 1)
            element = linkedList.removeFirst()
            i += 1
        }
        #expect(i == 100)
    }

    @Test func testCycleOperations() async throws {
        let linkedList = LinkedList<Int>()

        // Add elements
        for i in 1...20 {
            linkedList.append(i)
        }

        // Remove from front, forcing the head to wrap around
        for _ in 1...15 {
            _ = linkedList.removeFirst()
        }

        // Add more elements, testing if append works correctly with wrapped buffer
        for i in 21...30 {
            linkedList.append(i)
        }

        #expect(linkedList.size == 15)

        var element = linkedList.removeFirst()
        var i = 0
        while element != nil {
            #expect(element == i + 16)
            element = linkedList.removeFirst()
            i += 1
        }
        #expect(i == 15)
    }
}
