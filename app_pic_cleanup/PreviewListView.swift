import SwiftUI

struct PreviewListView: View {
    let model: CleanupModel

    var body: some View {
        let candidates = model.candidates ?? []
        List(candidates) { candidate in
            NavigationLink {
                PhotoDetailView(model: model, candidate: candidate)
            } label: {
                CandidateRow(model: model, candidate: candidate)
            }
        }
        .navigationTitle("\(candidates.count) photos")
        .navigationBarTitleDisplayMode(.inline)
    }
}

private struct CandidateRow: View {
    let model: CleanupModel
    let candidate: Candidate

    var body: some View {
        let resized = candidate.resizedDimensions(maxPixelSize: model.settings.maxPixelSize)
        HStack(spacing: 12) {
            AssetThumbnail(id: candidate.id, side: 56)
            VStack(alignment: .leading, spacing: 2) {
                Text(candidate.creationDate?.formatted(date: .abbreviated, time: .shortened) ?? "Unknown date")
                    .font(.subheadline)
                Text("\(formatBytes(candidate.fileSize)) · \(candidate.pixelWidth)×\(candidate.pixelHeight)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text("→ \(model.estimatedSize(of: candidate).map { "≈ " + formatBytes($0) } ?? "…") · \(resized.width)×\(resized.height)")
                    .font(.caption)
                    .foregroundStyle(.green)
            }
            Spacer()
            if candidate.isLivePhoto {
                Image(systemName: "livephoto")
                    .foregroundStyle(.secondary)
                    .accessibilityLabel("Live Photo")
            }
        }
    }
}

struct AssetThumbnail: View {
    let id: String
    let side: CGFloat
    @State private var image: UIImage?

    var body: some View {
        ZStack {
            Rectangle().fill(.quaternary)
            if let image {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
            }
        }
        .frame(width: side, height: side)
        .clipShape(RoundedRectangle(cornerRadius: 6))
        .accessibilityHidden(true)
        .task(id: id) {
            image = await PhotoLibrary.thumbnail(id: id, side: side * 3)
        }
    }
}
