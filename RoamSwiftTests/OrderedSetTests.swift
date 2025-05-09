import Testing
import Roam
import Foundation

struct OrderedSetTests {
    // MARK: - Initialization Tests

    @Test func testEmptyInit() async throws {
        let set = OrderedSet<String>()
        #expect(set.count == 0)
        #expect(set.isEmpty == true)
        #expect(set.first == nil)
        #expect(set.last == nil)
    }

    @Test func testSequenceInit() async throws {
        let array = ["a", "b", "c", "d", "b"] // Note the duplicate "b"
        let set = OrderedSet(array)

        #expect(set.count == 4, "Duplicates should be removed")
        #expect(set.first == "a")
        #expect(set.last == "d")

        // Check all elements were added in order (minus duplicates)
        #expect(set[0] == "a")
        #expect(set[1] == "b")
        #expect(set[2] == "c")
        #expect(set[3] == "d")
    }

    @Test func testArrayLiteralInit() async throws {
        let set: OrderedSet<String> = ["a", "b", "c", "d", "b"] // Note the duplicate "b"

        #expect(set.count == 4, "Duplicates should be removed")
        #expect(set[0] == "a")
        #expect(set[1] == "b")
        #expect(set[2] == "c")
        #expect(set[3] == "d")
    }

    // MARK: - Append and Insert Tests

    @Test func testAppend() async throws {
        var set = OrderedSet<Int>()

        // Append to empty set
        #expect(set.append(1) == true)
        #expect(set.count == 1)
        #expect(set.first == 1)
        #expect(set.last == 1)

        // Append unique values
        #expect(set.append(2) == true)
        #expect(set.append(3) == true)
        #expect(set.count == 3)
        #expect(set.first == 1)
        #expect(set.last == 3)

        // Append duplicate value
        #expect(set.append(2) == false, "Should return false for duplicates")
        #expect(set.count == 3, "Count shouldn't change")

        // Original order should be preserved
        #expect(set[0] == 1)
        #expect(set[1] == 2)
        #expect(set[2] == 3)
    }

    // MARK: - UpdateOrAppend Tests

    @Test func testUpdateOrAppend() async throws {
        // Create a test model that's Hashable based on ID but has other properties
        struct TestItem: Hashable {
            let id: Int      // Identity
            var value: String // Mutable property

            static func == (lhs: TestItem, rhs: TestItem) -> Bool {
                return lhs.id == rhs.id
            }

            func hash(into hasher: inout Hasher) {
                hasher.combine(id)
            }
        }

        var set = OrderedSet<TestItem>()

        // Test appending new items
        set.updateOrAppend(TestItem(id: 1, value: "Item 1"))
        set.updateOrAppend(TestItem(id: 2, value: "Item 2"))
        set.updateOrAppend(TestItem(id: 3, value: "Item 3"))

        #expect(set.count == 3)
        #expect(set[0].value == "Item 1")
        #expect(set[1].value == "Item 2")
        #expect(set[2].value == "Item 3")

        // Test updating existing item - should maintain position
        set.updateOrAppend(TestItem(id: 2, value: "Updated Item 2"))

        // Count should stay the same as we updated, not appended
        #expect(set.count == 3)

        // Position should be maintained for the updated item
        #expect(set[0].id == 1)
        #expect(set[1].id == 2)
        #expect(set[2].id == 3)

        // Value should be updated
        #expect(set[1].value == "Updated Item 2")

        // Add another item then update the first
        set.updateOrAppend(TestItem(id: 4, value: "Item 4"))
        set.updateOrAppend(TestItem(id: 1, value: "Updated Item 1"))

        // Count increases only for the new item
        #expect(set.count == 4)

        // Check all items have correct positions and values
        #expect(set[0].id == 1)
        #expect(set[0].value == "Updated Item 1")
        #expect(set[1].id == 2)
        #expect(set[1].value == "Updated Item 2")
        #expect(set[3].id == 4)
        #expect(set[3].value == "Item 4")

        // Test updating the last item
        set.updateOrAppend(TestItem(id: 4, value: "Updated Item 4"))

        // Count remains the same
        #expect(set.count == 4)

        // Last item has updated value
        #expect(set[3].value == "Updated Item 4")
    }

    // MARK: - Removal Tests

    @Test func testPopFirst() async throws {
        var set: OrderedSet<String> = ["a", "b", "c", "d", "e"]

        // Pop first element
        let first = set.popFirst()
        #expect(first == "a")
        #expect(set.count == 4)
        #expect(set.first == "b")
        #expect(set.contains("a") == false)

        // Pop until one element remains
        _ = set.popFirst()
        _ = set.popFirst()
        _ = set.popFirst()
        #expect(set.count == 1)
        #expect(set.first == "e")
        #expect(set.last == "e")

        // Pop last element
        _ = set.popFirst()
        #expect(set.count == 0)
        #expect(set.first == nil)
        #expect(set.last == nil)

        // Pop from empty set
        let emptyResult = set.popFirst()
        #expect(emptyResult == nil)
        #expect(set.count == 0)
    }

    @Test func testRemoveElement() async throws {
        var set: OrderedSet<String> = ["a", "b", "c", "d", "e"]

        // Remove middle element
        let removed = set.remove("c")
        #expect(removed == "c")
        #expect(set.count == 4)
        #expect(set[0] == "a")
        #expect(set[1] == "b")
        #expect(set[2] == "d")
        #expect(set[3] == "e")

        // Remove first element
        _ = set.remove("a")
        #expect(set.count == 3)
        #expect(set[0] == "b")

        // Remove last element
        _ = set.remove("e")
        #expect(set.count == 2)
        #expect(set[1] == "d")

        // Remove non-existent element
        let nonExistent = set.remove("z")
        #expect(nonExistent == nil)
        #expect(set.count == 2)
    }

    @Test func testRemoveAll() async throws {
        var set: OrderedSet<String> = ["a", "b", "c", "d", "e"]

        set.removeAll()
        #expect(set.count == 0)
        #expect(set.isEmpty == true)
        #expect(set.first == nil)
        #expect(set.last == nil)
    }

    // MARK: - Access and Contains Tests

    @Test func testSubscript() async throws {
        let set: OrderedSet<String> = ["a", "b", "c", "d", "e"]

        #expect(set[0] == "a")
        #expect(set[2] == "c")
        #expect(set[4] == "e")
    }

    @Test func testContains() async throws {
        let set: OrderedSet<String> = ["a", "b", "c"]

        #expect(set.contains("a") == true)
        #expect(set.contains("b") == true)
        #expect(set.contains("c") == true)
        #expect(set.contains("d") == false)
        #expect(set.contains("") == false)
    }

    @Test func testFirstIndex() async throws {
        let set: OrderedSet<String> = ["a", "b", "c", "d", "e"]

        #expect(set.firstIndex(of: "a") == 0)
        #expect(set.firstIndex(of: "c") == 2)
        #expect(set.firstIndex(of: "e") == 4)
        #expect(set.firstIndex(of: "z") == nil)
    }

    // MARK: - Set Operation Tests

    @Test func testUnion() async throws {
        let set1: OrderedSet<Int> = [1, 2, 3, 4]
        let set2: OrderedSet<Int> = [3, 4, 5, 6]

        let union = set1.union(set2)

        #expect(union.count == 6)

        // Elements from set1 should appear first, in original order
        #expect(union[0] == 1)
        #expect(union[1] == 2)
        #expect(union[2] == 3)
        #expect(union[3] == 4)

        // Followed by unique elements from set2, in original order
        #expect(union[4] == 5)
        #expect(union[5] == 6)
    }

    @Test func testIntersection() async throws {
        let set1: OrderedSet<Int> = [1, 2, 3, 4, 5]
        let set2: OrderedSet<Int> = [3, 4, 5, 6, 7]

        let intersection = set1.intersection(set2)

        #expect(intersection.count == 3)

        // Elements should be in the order they appear in set1
        #expect(intersection[0] == 3)
        #expect(intersection[1] == 4)
        #expect(intersection[2] == 5)
    }

    @Test func testSubtracting() async throws {
        let set1: OrderedSet<Int> = [1, 2, 3, 4, 5]
        let set2: OrderedSet<Int> = [3, 4, 5, 6, 7]

        let difference = set1.subtracting(set2)

        #expect(difference.count == 2)

        // Elements should be in the order they appear in set1
        #expect(difference[0] == 1)
        #expect(difference[1] == 2)
    }

    @Test func testSymmetricDifference() async throws {
        let set1: OrderedSet<Int> = [1, 2, 3, 4, 5]
        let set2: OrderedSet<Int> = [3, 4, 5, 6, 7]

        let symDifference = set1.symmetricDifference(set2)

        #expect(symDifference.count == 4)

        // Elements unique to set1 come first in their original order
        #expect(symDifference[0] == 1)
        #expect(symDifference[1] == 2)

        // Then elements unique to set2 in their original order
        #expect(symDifference[2] == 6)
        #expect(symDifference[3] == 7)
    }

    // MARK: - Collection Conformance Tests

    @Test func testForInLoop() async throws {
        let set: OrderedSet<Int> = [1, 2, 3, 4, 5]
        var sum = 0

        for element in set {
            sum += element
        }

        #expect(sum == 15)
    }

    @Test func testMap() async throws {
        let set: OrderedSet<Int> = [1, 2, 3, 4, 5]
        let doubled = set.map { $0 * 2 }

        #expect(doubled == [2, 4, 6, 8, 10])
    }

    @Test func testFilter() async throws {
        let set: OrderedSet<Int> = [1, 2, 3, 4, 5, 6, 7, 8]
        let evenNumbers = set.filter { $0 % 2 == 0 }

        #expect(evenNumbers == [2, 4, 6, 8])
    }

    // MARK: - Edge Cases and Stress Tests

    @Test func testEmptySetOperations() async throws {
        var set = OrderedSet<Int>()

        // These should not cause crashes or issues
        #expect(set.first == nil)
        #expect(set.last == nil)
        #expect(set.count == 0)
        #expect(set.contains(42) == false)
        #expect(set.firstIndex(of: 42) == nil)
        #expect(set.remove(42) == nil)
        #expect(set.popFirst() == nil)

        // Edge case: empty set operations
        let emptySet = OrderedSet<Int>()
        let unionResult = set.union(emptySet)
        #expect(unionResult.count == 0)

        let intersectionResult = set.intersection(emptySet)
        #expect(intersectionResult.count == 0)

        let differenceResult = set.subtracting(emptySet)
        #expect(differenceResult.count == 0)

        let symDifferenceResult = set.symmetricDifference(emptySet)
        #expect(symDifferenceResult.count == 0)
    }

    @Test func testSingleElementSet() async throws {
        var set = OrderedSet<Int>()
        set.append(42)

        #expect(set.count == 1)
        #expect(set.first == 42)
        #expect(set.last == 42)
        #expect(set[0] == 42)
        #expect(set.contains(42) == true)
        #expect(set.firstIndex(of: 42) == 0)

        let removed = set.remove(42)
        #expect(removed == 42)
        #expect(set.count == 0)
    }
}
