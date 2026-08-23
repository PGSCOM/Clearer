/// Clusters near-duplicate assets by feature-print distance. Pure logic —
/// takes a distance function instead of real Vision types, so it's testable
/// with fake distances and no live photo library.
enum Grouping {
    /// Greedy, single-pass clustering: for each id (in input order), join
    /// the nearest-preceding group if it's within `threshold`, otherwise
    /// start a new one. Only compares against the last `windowSize` groups.
    ///
    /// That window is a deliberate assumption, not just a perf shortcut:
    /// near-duplicates (bursts, "just one more shot") are essentially
    /// always adjacent in a library sorted by creation date, which is the
    /// only order this is ever called with (`PhotoLibrary.fetchAllAssets`
    /// sorts newest-first). Comparing every asset against every prior
    /// group would be correct too, just needlessly O(n²) for a case that
    /// doesn't happen in practice — a 2019 photo and a 2024 photo are never
    /// going to be near-duplicates of each other.
    ///
    /// ponytail: greedy + windowed, not full hierarchical clustering. Good
    /// enough for "a few near-identical shots taken seconds apart"; revisit
    /// only if real usage shows it missing duplicates that matter.
    static func groups(
        ids: [String],
        windowSize: Int = 20,
        threshold: Float,
        distance: (String, String) -> Float
    ) -> [[String]] {
        var groups: [[String]] = []

        for id in ids {
            let searchStart = max(0, groups.count - windowSize)
            // Compare against each candidate group's most recently added
            // member, not its first — that's what lets a *chain* of
            // gradually-drifting near-duplicates (5 burst shots where 1↔2,
            // 2↔3, 3↔4... are each close but 1↔5 might not be) stay in one
            // group instead of splintering.
            if let offset = groups[searchStart...].firstIndex(where: { distance($0.last!, id) <= threshold }) {
                groups[offset].append(id)
            } else {
                groups.append([id])
            }
        }

        return groups.filter { $0.count > 1 }
    }
}
