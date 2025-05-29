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

        // Check all elements were added in order
        for (index, element) in array.enumerated() {
            #expect(linkedList[index] == element)
        }
    }

    @Test func testArrayLiteralInit() async throws {
        let linkedList: LinkedList<Int> = [1, 2, 3, 4, 5]

        #expect(linkedList.size == 5)
        #expect(linkedList.first == 1)
        #expect(linkedList.last == 5)
    }

    // MARK: - Append and Prepend Tests

    @Test func testAppend() async throws {
        var linkedList = LinkedList<Int>()

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

    @Test func testPrepend() async throws {
        var linkedList = LinkedList<Int>()

        // Prepend to empty LinkedList
        linkedList.prepend(1)
        #expect(linkedList.size == 1)
        #expect(linkedList.first == 1)
        #expect(linkedList.last == 1)

        // Prepend to non-empty LinkedList
        linkedList.prepend(2)
        #expect(linkedList.size == 2)
        #expect(linkedList.first == 2)
        #expect(linkedList.last == 1)

        // Prepend multiple elements
        linkedList.prepend(3)
        linkedList.prepend(4)
        #expect(linkedList.size == 4)
        #expect(linkedList.first == 4)
        #expect(linkedList.last == 1)
    }

    @Test func testMixedAppendPrepend() async throws {
        var linkedList = LinkedList<Int>()

        linkedList.append(10)
        linkedList.prepend(5)
        linkedList.append(15)
        linkedList.prepend(0)

        #expect(linkedList.size == 4)
        #expect(linkedList[0] == 0)
        #expect(linkedList[1] == 5)
        #expect(linkedList[2] == 10)
        #expect(linkedList[3] == 15)
    }

    // MARK: - Removal Tests

    @Test func testPopFirst() async throws {
        var linkedList: LinkedList<Int> = [1, 2, 3, 4, 5]

        // Pop first element
        let first = linkedList.popFirst()
        #expect(first == 1)
        #expect(linkedList.size == 4)
        #expect(linkedList.first == 2)

        // Pop until one element remains
        _ = linkedList.popFirst()
        _ = linkedList.popFirst()
        _ = linkedList.popFirst()
        #expect(linkedList.size == 1)
        #expect(linkedList.first == 5)
        #expect(linkedList.last == 5)

        // Pop last element
        _ = linkedList.popFirst()
        #expect(linkedList.size == 0)
        #expect(linkedList.first == nil)
        #expect(linkedList.last == nil)

        // Pop from empty LinkedList
        let emptyResult = linkedList.popFirst()
        #expect(emptyResult == nil)
        #expect(linkedList.size == 0)
    }

    @Test func testpopFirst() async throws {
        var linkedList: LinkedList<Int> = [1, 2, 3, 4, 5]

        // Remove first element
        let first = linkedList.popFirst()
        #expect(first == 1)
        #expect(linkedList.size == 4)
        #expect(linkedList.first == 2)

        // Remove until one element remains
        _ = linkedList.popFirst()
        _ = linkedList.popFirst()
        _ = linkedList.popFirst()
        #expect(linkedList.size == 1)
        #expect(linkedList.first == 5)
        #expect(linkedList.last == 5)

        // Remove last element
        _ = linkedList.popFirst()
        #expect(linkedList.size == 0)
        #expect(linkedList.first == nil)
        #expect(linkedList.last == nil)
    }

    @Test func testRemoveAll() async throws {
        var linkedList: LinkedList<Int> = [1, 2, 3, 4, 5]

        linkedList.removeAll()
        #expect(linkedList.size == 0)
        #expect(linkedList.first == nil)
        #expect(linkedList.last == nil)
    }

    // MARK: - Access Tests

    @Test func testSubscript() async throws {
        let linkedList: LinkedList<Int> = [10, 20, 30, 40, 50]

        #expect(linkedList[0] == 10)
        #expect(linkedList[2] == 30)
        #expect(linkedList[4] == 50)
    }

    // MARK: - Collection Conformance Tests

    @Test func testForInLoop() async throws {
        let linkedList: LinkedList<Int> = [1, 2, 3, 4, 5]
        var sum = 0

        for element in linkedList {
            sum += element
        }

        #expect(sum == 15)
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
        var linkedList = LinkedList<Int>()
        linkedList.append(42)

        #expect(linkedList.size == 1)
        #expect(linkedList.first == 42)
        #expect(linkedList.last == 42)
        #expect(linkedList[0] == 42)

        let removed = linkedList.popFirst()
        #expect(removed == 42)
        #expect(linkedList.size == 0)
    }

    @Test func testResizeGrowth() async throws {
        var linkedList = LinkedList<Int>()

        // Add more elements than the initial capacity
        for i in 1...100 {
            linkedList.append(i)
        }

        #expect(linkedList.size == 100)

        // Check that all elements are correct after multiple resizes
        for i in 0..<100 {
            #expect(linkedList[i] == i + 1)
        }
    }

    @Test func testResizeWithMixedOperations() async throws {
        var linkedList = LinkedList<Int>()

        // Mix prepend and append to force multiple resize operations
        for i in 1...50 {
            linkedList.append(i)
            linkedList.prepend(-i)
        }

        #expect(linkedList.size == 100)

        // Check correct order after resizes
        for i in 0..<50 {
            #expect(linkedList[i] == -50 + i)
        }
        for i in 50..<100 {
            #expect(linkedList[i] == i - 49)
        }
    }

    @Test func testCycleOperations() async throws {
        var linkedList = LinkedList<Int>()

        // Add elements
        for i in 1...20 {
            linkedList.append(i)
        }

        // Remove from front, forcing the head to wrap around
        for _ in 1...15 {
            _ = linkedList.popFirst()
        }

        // Add more elements, testing if append works correctly with wrapped buffer
        for i in 21...30 {
            linkedList.append(i)
        }

        #expect(linkedList.size == 15)

        // Check elements are in correct order
        for i in 0..<5 {
            #expect(linkedList[i] == i + 16)
        }
        for i in 5..<15 {
            #expect(linkedList[i] == i + 16)
        }
    }
}
