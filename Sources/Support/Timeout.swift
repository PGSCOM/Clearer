enum TimeoutError: Error {
    case timedOut
}

/// Races `operation` against a deadline. Exists specifically because
/// `PHPhotoLibrary.performChanges` has a confirmed (if rare) failure mode
/// on some iOS 26 builds where its completion never fires at all — see
/// `PhotoLibrary.deleteAssets`. Without this, that would hang the delete
/// UI forever instead of surfacing an honest "this is taking too long".
func withTimeout<T: Sendable>(
    seconds: Int,
    operation: @escaping @Sendable () async throws -> T
) async throws -> T {
    try await withThrowingTaskGroup(of: T.self) { group in
        group.addTask { try await operation() }
        group.addTask {
            try await Task.sleep(for: .seconds(seconds))
            throw TimeoutError.timedOut
        }
        guard let result = try await group.next() else {
            throw TimeoutError.timedOut
        }
        group.cancelAll()
        return result
    }
}
