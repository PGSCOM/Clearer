import SwiftData
import XCTest
@testable import Clearer

final class ReviewProgressStoreTests: XCTestCase {
    private func makeContext() throws -> ModelContext {
        let schema = Schema([ReviewProgressRecord.self])
        let config = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: schema, configurations: [config])
        return ModelContext(container)
    }

    func testLoadWithNoRecordReturnsEmptySet() throws {
        let context = try makeContext()
        XCTAssertTrue(ReviewProgressStore.load(from: context).isEmpty)
    }

    func testSaveThenLoadRoundTrips() throws {
        let context = try makeContext()
        ReviewProgressStore.save(["a", "b"], to: context)
        XCTAssertEqual(ReviewProgressStore.load(from: context), ["a", "b"])
    }

    func testSaveOverwritesPreviousRecordRatherThanDuplicating() throws {
        let context = try makeContext()
        ReviewProgressStore.save(["a"], to: context)
        ReviewProgressStore.save(["a", "b"], to: context)
        XCTAssertEqual(ReviewProgressStore.load(from: context), ["a", "b"])
        XCTAssertEqual(try context.fetch(FetchDescriptor<ReviewProgressRecord>()).count, 1)
    }
}
