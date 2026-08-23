/// One asset the review screen shows a card for, and every reason it was
/// flagged. An asset that matched more than one criterion — a screenshot
/// that's also part of a burst, say — gets exactly one card with both
/// reasons on it, not two separate cards.
struct ReviewItem: Identifiable, Equatable {
    let id: String
    let reasons: Set<CleanupReason>
}

enum ReviewQueueBuilder {
    /// Builds the review queue from three separately-computed inputs:
    ///
    /// - `singleReasons`: per-asset reasons from `Detectors.reasons`.
    /// - `burstGroups` / `duplicateGroups`: groups of "the same shot" —
    ///   camera bursts and near-duplicate clusters respectively. Only the
    ///   EXCESS members of each group (via `Detectors.excessIDs`) get a
    ///   card; the one being kept isn't suggested for deletion, so there's
    ///   nothing to review about it. This is deliberately simpler than a
    ///   side-by-side group picker: every excess duplicate still gets
    ///   reviewed individually, tagged with why, just without a
    ///   comparison view. Good enough for v1; a real group-picker UI can
    ///   follow later if this turns out to feel wrong in practice.
    ///
    /// Groups take the SAME `(id, overallScore)` shape so both call the
    /// one `excessIDs` algorithm — a burst and a near-duplicate cluster are
    /// the same kind of decision ("keep the best, flag the rest"), just
    /// found two different ways upstream.
    static func build(
        singleReasons: [(id: String, reasons: Set<CleanupReason>)],
        burstGroups: [[(id: String, overallScore: Float?)]],
        duplicateGroups: [[(id: String, overallScore: Float?)]]
    ) -> [ReviewItem] {
        var reasonsByID: [String: Set<CleanupReason>] = [:]

        for (id, reasons) in singleReasons where !reasons.isEmpty {
            reasonsByID[id, default: []].formUnion(reasons)
        }
        for burst in burstGroups where burst.count > 1 {
            for id in Detectors.excessIDs(in: burst) {
                reasonsByID[id, default: []].insert(.burstDuplicate)
            }
        }
        for group in duplicateGroups where group.count > 1 {
            for id in Detectors.excessIDs(in: group) {
                reasonsByID[id, default: []].insert(.duplicate)
            }
        }

        // Sorted for a stable order across rebuilds (e.g. dragging the
        // duplicate-threshold slider) — a `Dictionary`'s iteration order
        // isn't guaranteed, and a review queue that reshuffles itself
        // mid-review would be a bad surprise.
        return reasonsByID
            .map { ReviewItem(id: $0.key, reasons: $0.value) }
            .sorted { $0.id < $1.id }
    }
}
