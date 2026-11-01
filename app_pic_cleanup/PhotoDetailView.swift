import SwiftUI

/// Shows the real result of resizing one photo with the current settings. Nothing is saved.
struct PhotoDetailView: View {
    let model: CleanupModel
    let candidate: Candidate

    @State private var original: UIImage?
    @State private var resized: UIImage?
    @State private var output: ImageResizer.Output?
    @State private var showResized = true
    @State private var errorMessage: String?

    var body: some View {
        VStack(spacing: 12) {
            Picker("Version", selection: $showResized) {
                Text("Original").tag(false)
                Text("Resized").tag(true)
            }
            .pickerStyle(.segmented)
            .padding(.horizontal)

            ZStack {
                if let image = showResized ? resized : original {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFit()
                        .accessibilityLabel(showResized ? "Resized photo" : "Original photo")
                } else if let errorMessage {
                    ContentUnavailableView("Couldn't load photo", systemImage: "exclamationmark.triangle", description: Text(errorMessage))
                } else {
                    ProgressView("Resizing…")
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            Grid(alignment: .leading, horizontalSpacing: 16, verticalSpacing: 6) {
                GridRow {
                    Text("Original").foregroundStyle(.secondary)
                    Text(formatBytes(candidate.fileSize))
                    Text("\(candidate.pixelWidth)×\(candidate.pixelHeight)")
                }
                if let output {
                    GridRow {
                        Text("Resized").foregroundStyle(.secondary)
                        Text(formatBytes(Int64(output.data.count)))
                        Text("\(output.pixelWidth)×\(output.pixelHeight)")
                    }
                }
            }
            .font(.callout.monospacedDigit())

            if let output {
                let ratio = Double(output.data.count) / Double(max(candidate.fileSize, 1))
                if !CleanupSettings.isWorthReplacing(originalSize: candidate.fileSize, newSize: output.data.count) {
                    Text("This photo will be skipped: it would shrink by less than \(Int((1 - CleanupSettings.maxSizeRatio) * 100))%.")
                        .font(.footnote)
                        .foregroundStyle(.orange)
                } else {
                    Text("Saves \(formatBytes(candidate.fileSize - Int64(output.data.count))) (\(Int(((1 - ratio) * 100).rounded()))%)")
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(.green)
                }
            }
            if candidate.isLivePhoto {
                Text("Live Photo: the copy will be a still photo.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.bottom)
        .navigationTitle(candidate.creationDate?.formatted(date: .abbreviated, time: .omitted) ?? "Photo")
        .navigationBarTitleDisplayMode(.inline)
        .task { await load() }
    }

    private func load() async {
        do {
            let data = try await PhotoLibrary.loadImageData(id: candidate.id)
            let maxPixelSize = model.settings.maxPixelSize
            let quality = model.settings.quality
            let (originalImage, output) = try await Task.detached(priority: .userInitiated) {
                // Decode the original at a size that's sharp on screen without using huge amounts of memory.
                let originalImage = ImageResizer.downsample(data, maxPixelSize: 4096)
                let output = try ImageResizer.resize(data, maxPixelSize: maxPixelSize, quality: quality)
                return (originalImage, output)
            }.value
            original = originalImage.map { UIImage(cgImage: $0) }
            // Decode the encoded bytes so compression artifacts are visible.
            resized = UIImage(data: output.data)
            self.output = output
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
