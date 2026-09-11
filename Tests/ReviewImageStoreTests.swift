import XCTest
@testable import Clearer

/// `keepWarmIDs` is the pure piece of `ReviewImageStore`'s prefetch window
/// — no PhotoKit involved, so the boundary cases (empty queue, empty
/// history, a queue shorter than the window) are covered without a live
/// photo library.
final class ReviewImageStoreTests: XCTestCase {
    func testKeepsAheadItemsAndOneBehindItem() {
        let keep = ReviewImageStore.keepWarmIDs(
            pending: ["a", "b", "c", "d", "e", "f"],
            recentlyReviewed: ["y", "z"]
        )
        XCTAssertEqual(keep, ["a", "b", "c", "d", "z"])
    }

    func testEmptyPendingKeepsOnlyRecentHistory() {
        let keep = ReviewImageStore.keepWarmIDs(pending: [], recentlyReviewed: ["z"])
        XCTAssertEqual(keep, ["z"])
    }

    func testEmptyHistoryKeepsOnlyPending() {
        let keep = ReviewImageStore.keepWarmIDs(pending: ["a", "b"], recentlyReviewed: [])
        XCTAssertEqual(keep, ["a", "b"])
    }

    func testShorterQueueThanWindowKeepsWhatExists() {
        let keep = ReviewImageStore.keepWarmIDs(pending: ["a"], recentlyReviewed: ["z"])
        XCTAssertEqual(keep, ["a", "z"])
    }

    func testEverythingEmptyIsEmpty() {
        XCTAssertTrue(ReviewImageStore.keepWarmIDs(pending: [], recentlyReviewed: []).isEmpty)
    }

    func testCustomAheadAndBehindWindow() {
        let keep = ReviewImageStore.keepWarmIDs(
            pending: ["a", "b", "c"],
            recentlyReviewed: ["x", "y", "z"],
            ahead: 1,
            behind: 2
        )
        XCTAssertEqual(keep, ["a", "y", "z"])
    }
}
