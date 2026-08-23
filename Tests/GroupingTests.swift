import XCTest
@testable import Clearer

final class GroupingTests: XCTestCase {
    func testEmptyInputProducesNoGroups() {
        let groups = Grouping.groups(ids: [], threshold: 0.35) { _, _ in 0 }
        XCTAssertTrue(groups.isEmpty)
    }

    func testCloseAssetsFormAGroup() {
        let close: Set<Set<String>> = [["a", "b"]]
        let groups = Grouping.groups(ids: ["a", "b"], threshold: 0.35) { lhs, rhs in
            close.contains([lhs, rhs]) ? 0.1 : 1.0
        }
        XCTAssertEqual(groups, [["a", "b"]])
    }

    func testFarAssetsStaySingletonsAndAreDropped() {
        let groups = Grouping.groups(ids: ["a", "b"], threshold: 0.35) { _, _ in 1 }
        XCTAssertTrue(groups.isEmpty, "singleton groups (no duplicate found) are filtered out")
    }

    func testChainOfDriftingNearDuplicatesStaysOneGroup() {
        // 1↔2 and 2↔3 are close; 1↔3 is not. Comparing each new id against
        // the group's LAST member (not its first) is what keeps this one
        // group instead of splitting after "3".
        let close: Set<Set<String>> = [["1", "2"], ["2", "3"]]
        let groups = Grouping.groups(ids: ["1", "2", "3"], threshold: 0.35) { lhs, rhs in
            close.contains([lhs, rhs]) ? 0.1 : 1.0
        }
        XCTAssertEqual(groups, [["1", "2", "3"]])
    }

    func testWindowSizeLimitsHowFarBackItLooks() {
        // "a" and "d" are close, but two unrelated groups sit between them.
        // With windowSize 2, "d" only gets to compare against the last two
        // groups (b's and c's) — "a" has scrolled out of the window.
        let close: Set<Set<String>> = [["a", "d"]]
        let groups = Grouping.groups(ids: ["a", "b", "c", "d"], windowSize: 2, threshold: 0.35) { lhs, rhs in
            close.contains([lhs, rhs]) ? 0.1 : 1.0
        }
        XCTAssertTrue(groups.isEmpty, "a should have fallen outside the window by the time d is processed")
    }

    func testLargerWindowSizeDoesFindTheSameMatch() {
        let close: Set<Set<String>> = [["a", "d"]]
        let groups = Grouping.groups(ids: ["a", "b", "c", "d"], windowSize: 10, threshold: 0.35) { lhs, rhs in
            close.contains([lhs, rhs]) ? 0.1 : 1.0
        }
        XCTAssertEqual(groups, [["a", "d"]])
    }

    func testThresholdBoundaryIsInclusive() {
        let groups = Grouping.groups(ids: ["a", "b"], threshold: 0.35) { _, _ in 0.35 }
        XCTAssertEqual(groups, [["a", "b"]], "distance == threshold should count as a match")
    }
}
