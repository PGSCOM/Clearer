import Photos
import SwiftData
import SwiftUI
import UIKit

struct PhotoGridView: View {
    let model: PhotoGridModel

    @Environment(\.modelContext) private var modelContext
    @State private var coordinator: AnalysisCoordinator?

    private let columns = [GridItem(.adaptive(minimum: 110), spacing: 2)]

    var body: some View {
        ScrollView {
            counterHeader
            LazyVGrid(columns: columns, spacing: 2) {
                if let fetchResult = model.fetchResult {
                    ForEach(0..<fetchResult.count, id: \.self) { index in
                        PhotoGridCell(asset: fetchResult.object(at: index), model: model)
                    }
                }
            }
        }
        .navigationTitle("Fotos")
        .toolbar {
            if let fetchResult = model.fetchResult, let coordinator {
                ToolbarItem(placement: .topBarTrailing) {
                    NavigationLink {
                        AnalysisResultsView(fetchResult: fetchResult, coordinator: coordinator)
                    } label: {
                        Image(systemName: "sparkles")
                    }
                }
            }
        }
        .task {
            if coordinator == nil {
                coordinator = AnalysisCoordinator(modelContext: modelContext)
            }
        }
    }

    private var counterHeader: some View {
        HStack {
            Text("\(model.fetchResult?.count ?? 0) fotos")
            if model.iCloudOnlyCount > 0 {
                Text("· \(model.iCloudOnlyCount) sin descargar de iCloud")
            }
            Spacer()
        }
        .font(.footnote)
        .foregroundStyle(.secondary)
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }
}

private struct PhotoGridCell: View {
    let asset: PHAsset
    let model: PhotoGridModel

    @State private var image: UIImage?
    @State private var isICloudOnly = false

    var body: some View {
        Rectangle()
            .fill(.quaternary)
            .aspectRatio(1, contentMode: .fit)
            .overlay {
                if let image {
                    Image(uiImage: image)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                }
            }
            .overlay(alignment: .bottomTrailing) {
                if isICloudOnly {
                    Image(systemName: "icloud")
                        .font(.caption2)
                        .foregroundStyle(.white)
                        .padding(5)
                        .background(.black.opacity(0.35), in: Circle())
                        .padding(4)
                }
            }
            .clipped()
            .task {
                let side = 110 * UIScreen.main.scale
                let result = await PhotoLibrary.shared.thumbnail(
                    for: asset,
                    targetSize: CGSize(width: side, height: side)
                )
                switch result {
                case .available(let fetchedImage):
                    image = fetchedImage
                case .iCloudOnly:
                    isICloudOnly = true
                case .unavailable:
                    break
                }
                model.noteThumbnailResult(result, assetID: asset.localIdentifier)
            }
    }
}
