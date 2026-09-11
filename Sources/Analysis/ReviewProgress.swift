import Foundation
import SwiftData

/// A single row (fixed `id`) persisting which review-card decisions have
/// already been made, so leaving the review screen — normal with ~10,000
/// photos to get through, nobody does that in one sitting — doesn't mean
/// starting over from the first card.
///
/// Stores the reviewed ID SET, not a position: the queue itself is rebuilt
/// from live criteria/threshold state on every load (see
/// `ReviewQueueBuilder`), so a saved index would point at the wrong photo
/// the instant a toggle or the duplicate-threshold slider changes what's in
/// the queue. `ReviewQueueBuilder.pending(items:reviewed:)` is what turns
/// this set back into "what's left to show".
@Model
final class ReviewProgressRecord {
    @Attribute(.unique) var id: String
    var reviewedIDs: [String]

    init(reviewedIDs: [String] = []) {
        self.id = "singleton"
        self.reviewedIDs = reviewedIDs
    }
}

enum ReviewProgressStore {
    static func load(from context: ModelContext) -> Set<String> {
        let record = (try? context.fetch(FetchDescriptor<ReviewProgressRecord>()))?.first
        return Set(record?.reviewedIDs ?? [])
    }

    static func save(_ reviewedIDs: Set<String>, to context: ModelContext) {
        if let record = (try? context.fetch(FetchDescriptor<ReviewProgressRecord>()))?.first {
            record.reviewedIDs = Array(reviewedIDs)
        } else {
            context.insert(ReviewProgressRecord(reviewedIDs: Array(reviewedIDs)))
        }
        try? context.save()
    }
}
