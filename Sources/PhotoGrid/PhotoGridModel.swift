import Observation
import Photos

@Observable
@MainActor
final class PhotoGridModel {
    private(set) var authorizationStatus: PHAuthorizationStatus
    private(set) var fetchResult: PHFetchResult<PHAsset>?
    private(set) var iCloudOnlyCount = 0
    private var seenICloudOnlyIDs = Set<String>()

    init() {
        authorizationStatus = PhotoLibrary.shared.authorizationStatus()
    }

    func requestAccess() async {
        authorizationStatus = await PhotoLibrary.shared.requestAuthorization()
        loadLibraryIfAuthorized()
    }

    /// Called when the app becomes active, in case the user granted access
    /// from Settings while we were backgrounded.
    func refreshAuthorizationStatus() {
        authorizationStatus = PhotoLibrary.shared.authorizationStatus()
        loadLibraryIfAuthorized()
    }

    private func loadLibraryIfAuthorized() {
        guard fetchResult == nil else { return }
        guard authorizationStatus == .authorized || authorizationStatus == .limited else { return }
        Task {
            fetchResult = await PhotoLibrary.shared.fetchAllPhotos()
        }
    }

    /// Tallies distinct iCloud-only assets as the grid discovers them while
    /// scrolling — not a full-library upfront scan, which would mean
    /// touching every asset just to count. A real full-library tally
    /// happens naturally in Fase 2's analysis pass instead.
    func noteThumbnailResult(_ result: ThumbnailResult, assetID: String) {
        guard case .iCloudOnly = result else { return }
        guard seenICloudOnlyIDs.insert(assetID).inserted else { return }
        iCloudOnlyCount += 1
    }
}
