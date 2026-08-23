import XCTest
@testable import Clearer

final class ReviewQueueBuilderTests: XCTestCase {
    func testEmptyInputProducesEmptyQueue() {
        let items = ReviewQueueBuilder.build(singleReasons: [], burstGroups: [], duplicateGroups: [])
        XCTAssertTrue(items.isEmpty)
    }

    func testFlaggedSingleAppearsInQueue() {
        let items = ReviewQueueBuilder.build(
            singleReasons: [(id: "a", reasons: [.screenshot])],
            burstGroups: [],
            duplicateGroups: []
        )
        XCTAssertEqual(items, [ReviewItem(id: "a", reasons: [.screenshot])])
    }

    func testEmptyReasonSetIsExcluded() {
        let items = ReviewQueueBuilder.build(
            singleReasons: [(id: "a", reasons: [])],
            burstGroups: [],
            duplicateGroups: []
        )
        XCTAssertTrue(items.isEmpty)
    }

    func testBurstGroupFlagsOnlyTheExcessMembers() {
        let items = ReviewQueueBuilder.build(
            singleReasons: [],
            burstGroups: [[(id: "a", overallScore: 0.9), (id: "b", overallScore: 0.1)]],
            duplicateGroups: []
        )
        XCTAssertEqual(items, [ReviewItem(id: "b", reasons: [.burstDuplicate])], "a is the kept shot, it shouldn't appear")
    }

    func testDuplicateGroupFlagsOnlyTheExcessMembers() {
        let items = ReviewQueueBuilder.build(
            singleReasons: [],
            burstGroups: [],
            duplicateGroups: [[(id: "x", overallScore: 0.2), (id: "y", overallScore: 0.8), (id: "z", overallScore: 0.1)]]
        )
        XCTAssertEqual(
            Set(items.map(\.id)), ["x", "z"],
            "y is the kept shot, it shouldn't appear"
        )
        XCTAssertTrue(items.allSatisfy { $0.reasons == [.duplicate] })
    }

    func testGroupOfOneIsIgnored() {
        let items = ReviewQueueBuilder.build(
            singleReasons: [],
            burstGroups: [[(id: "a", overallScore: 0.5)]],
            duplicateGroups: []
        )
        XCTAssertTrue(items.isEmpty)
    }

    func testSameAssetFlaggedTwiceGetsOneCardWithBothReasons() {
        // "a" is both a low-quality single AND the excess half of a burst.
        let items = ReviewQueueBuilder.build(
            singleReasons: [(id: "a", reasons: [.lowQuality])],
            burstGroups: [[(id: "a", overallScore: 0.1), (id: "b", overallScore: 0.9)]],
            duplicateGroups: []
        )
        XCTAssertEqual(items.count, 1)
        XCTAssertEqual(items.first?.reasons, [.lowQuality, .burstDuplicate])
    }

    func testResultIsSortedByIDForStableOrdering() {
        let items = ReviewQueueBuilder.build(
            singleReasons: [
                (id: "c", reasons: [.screenshot]),
                (id: "a", reasons: [.screenshot]),
                (id: "b", reasons: [.screenshot]),
            ],
            burstGroups: [],
            duplicateGroups: []
        )
        XCTAssertEqual(items.map(\.id), ["a", "b", "c"])
    }
}
