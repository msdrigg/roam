import Testing
import Roam

import Foundation

struct DequeTests {
    // MARK: - Initialization Tests

    @Test func testEmptyInit() async throws {
        let deque = Deque<Int>()
        #expect(deque.size == 0)
        #expect(deque.first == nil)
        #expect(deque.last == nil)
    }

    @Test func testSequenceInit() async throws {
        let array = [1, 2, 3, 4, 5]
        let deque = Deque(array)

        #expect(deque.size == array.count)
        #expect(deque.first == array.first)
        #expect(deque.last == array.last)

        // Check all elements were added in order
        for (index, element) in array.enumerated() {
            #expect(deque[index] == element)
        }
    }

    @Test func testArrayLiteralInit() async throws {
        let deque: Deque<Int> = [1, 2, 3, 4, 5]

        #expect(deque.size == 5)
        #expect(deque.first == 1)
        #expect(deque.last == 5)
    }

    // MARK: - Append and Prepend Tests

    @Test func testAppend() async throws {
        var deque = Deque<Int>()

        // Append to empty deque
        deque.append(1)
        #expect(deque.size == 1)
        #expect(deque.first == 1)
        #expect(deque.last == 1)

        // Append to non-empty deque
        deque.append(2)
        #expect(deque.size == 2)
        #expect(deque.first == 1)
        #expect(deque.last == 2)

        // Append multiple elements
        deque.append(3)
        deque.append(4)
        #expect(deque.size == 4)
        #expect(deque.first == 1)
        #expect(deque.last == 4)
    }

    @Test func testPrepend() async throws {
        var deque = Deque<Int>()

        // Prepend to empty deque
        deque.prepend(1)
        #expect(deque.size == 1)
        #expect(deque.first == 1)
        #expect(deque.last == 1)

        // Prepend to non-empty deque
        deque.prepend(2)
        #expect(deque.size == 2)
        #expect(deque.first == 2)
        #expect(deque.last == 1)

        // Prepend multiple elements
        deque.prepend(3)
        deque.prepend(4)
        #expect(deque.size == 4)
        #expect(deque.first == 4)
        #expect(deque.last == 1)
    }

    @Test func testMixedAppendPrepend() async throws {
        var deque = Deque<Int>()

        deque.append(10)
        deque.prepend(5)
        deque.append(15)
        deque.prepend(0)

        #expect(deque.size == 4)
        #expect(deque[0] == 0)
        #expect(deque[1] == 5)
        #expect(deque[2] == 10)
        #expect(deque[3] == 15)
    }

    // MARK: - Removal Tests

    @Test func testPopFirst() async throws {
        var deque: Deque<Int> = [1, 2, 3, 4, 5]

        // Pop first element
        let first = deque.popFirst()
        #expect(first == 1)
        #expect(deque.size == 4)
        #expect(deque.first == 2)

        // Pop until one element remains
        _ = deque.popFirst()
        _ = deque.popFirst()
        _ = deque.popFirst()
        #expect(deque.size == 1)
        #expect(deque.first == 5)
        #expect(deque.last == 5)

        // Pop last element
        _ = deque.popFirst()
        #expect(deque.size == 0)
        #expect(deque.first == nil)
        #expect(deque.last == nil)

        // Pop from empty deque
        let emptyResult = deque.popFirst()
        #expect(emptyResult == nil)
        #expect(deque.size == 0)
    }

    @Test func testpopFirst() async throws {
        var deque: Deque<Int> = [1, 2, 3, 4, 5]

        // Remove first element
        let first = deque.popFirst()
        #expect(first == 1)
        #expect(deque.size == 4)
        #expect(deque.first == 2)

        // Remove until one element remains
        _ = deque.popFirst()
        _ = deque.popFirst()
        _ = deque.popFirst()
        #expect(deque.size == 1)
        #expect(deque.first == 5)
        #expect(deque.last == 5)

        // Remove last element
        _ = deque.popFirst()
        #expect(deque.size == 0)
        #expect(deque.first == nil)
        #expect(deque.last == nil)
    }

    @Test func testRemoveAll() async throws {
        var deque: Deque<Int> = [1, 2, 3, 4, 5]

        deque.removeAll()
        #expect(deque.size == 0)
        #expect(deque.first == nil)
        #expect(deque.last == nil)
    }

    // MARK: - Access Tests

    @Test func testSubscript() async throws {
        let deque: Deque<Int> = [10, 20, 30, 40, 50]

        #expect(deque[0] == 10)
        #expect(deque[2] == 30)
        #expect(deque[4] == 50)
    }

    // MARK: - Collection Conformance Tests

    @Test func testForInLoop() async throws {
        let deque: Deque<Int> = [1, 2, 3, 4, 5]
        var sum = 0

        for element in deque {
            sum += element
        }

        #expect(sum == 15)
    }

    @Test func testMap() async throws {
        let deque: Deque<Int> = [1, 2, 3, 4, 5]
        let doubled = deque.map { $0 * 2 }

        #expect(doubled == [2, 4, 6, 8, 10])
    }

    @Test func testFilter() async throws {
        let deque: Deque<Int> = [1, 2, 3, 4, 5, 6, 7, 8]
        let evenNumbers = deque.filter { $0 % 2 == 0 }

        #expect(evenNumbers == [2, 4, 6, 8])
    }

    // MARK: - Edge Cases and Stress Tests

    @Test func testEmptyDequeOperations() async throws {
        let deque = Deque<Int>()

        // These should not cause crashes or issues
        #expect(deque.first == nil)
        #expect(deque.last == nil)
        #expect(deque.size == 0)
    }

    @Test func testSingleElementDeque() async throws {
        var deque = Deque<Int>()
        deque.append(42)

        #expect(deque.size == 1)
        #expect(deque.first == 42)
        #expect(deque.last == 42)
        #expect(deque[0] == 42)

        let removed = deque.popFirst()
        #expect(removed == 42)
        #expect(deque.size == 0)
    }

    @Test func testResizeGrowth() async throws {
        var deque = Deque<Int>()

        // Add more elements than the initial capacity
        for i in 1...100 {
            deque.append(i)
        }

        #expect(deque.size == 100)

        // Check that all elements are correct after multiple resizes
        for i in 0..<100 {
            #expect(deque[i] == i + 1)
        }
    }

    @Test func testResizeWithMixedOperations() async throws {
        var deque = Deque<Int>()

        // Mix prepend and append to force multiple resize operations
        for i in 1...50 {
            deque.append(i)
            deque.prepend(-i)
        }

        #expect(deque.size == 100)

        // Check correct order after resizes
        for i in 0..<50 {
            #expect(deque[i] == -50 + i)
        }
        for i in 50..<100 {
            #expect(deque[i] == i - 49)
        }
    }

    @Test func testCycleOperations() async throws {
        var deque = Deque<Int>()

        // Add elements
        for i in 1...20 {
            deque.append(i)
        }

        // Remove from front, forcing the head to wrap around
        for _ in 1...15 {
            _ = deque.popFirst()
        }

        // Add more elements, testing if append works correctly with wrapped buffer
        for i in 21...30 {
            deque.append(i)
        }

        #expect(deque.size == 15)

        // Check elements are in correct order
        for i in 0..<5 {
            #expect(deque[i] == i + 16)
        }
        for i in 5..<15 {
            #expect(deque[i] == i + 16)
        }
    }
}
