import SwiftUI
import Photos

struct ContentView: View {
    @Bindable var model: CleanupModel
    @State private var confirmStart = false
    @Environment(\.openURL) private var openURL

    var body: some View {
        NavigationStack {
            Form {
                switch model.authorization {
                case .authorized, .limited:
                    if model.authorization == .limited {
                        Section {
                            Label("You've given access to only some photos. Allow full access in Settings to clean up your whole library.", systemImage: "exclamationmark.triangle")
                                .font(.callout)
                        }
                    }
                    settingsSections
                    previewSection
                    runSection
                    historySection
                case .notDetermined:
                    Section {
                        Text("This app needs access to your photo library to find and resize large photos.")
                        Button("Allow Photo Access") {
                            Task { await model.requestAccess() }
                        }
                    }
                default:
                    Section {
                        Text("Photo access is turned off. Turn on full access in Settings to use this app.")
                        Button("Open Settings") {
                            if let url = URL(string: UIApplication.openSettingsURLString) { openURL(url) }
                        }
                    }
                }
            }
            .navigationTitle("Photo Cleanup")
            .confirmationDialog(
                "Replace \(model.candidates?.count ?? 0) photos with smaller copies?",
                isPresented: $confirmStart,
                titleVisibility: .visible
            ) {
                Button("Start", role: .destructive) { model.startRun() }
            } message: {
                Text("Each photo is saved again at the smaller size, keeping its date, location, favorite status and albums. Then the original is moved to Recently Deleted. Only continue if your originals are backed up.")
            }
        }
    }

    // MARK: - Sections

    @ViewBuilder
    private var settingsSections: some View {
        Group {
            Section {
                DatePicker("Taken before", selection: $model.settings.cutoffDate, displayedComponents: .date)
                Stepper(value: $model.settings.minFileSizeMB, in: 0.5...50, step: 0.5) {
                    Text("Larger than \(model.settings.minFileSizeMB, format: .number) MB")
                }
                Toggle("Include Live Photos", isOn: $model.settings.includeLivePhotos)
            } header: {
                Text("Which photos")
            } footer: {
                Text("Choose the date your backup covers. Live Photos lose their motion and become still photos.")
            }

            Section {
                Picker("Longest side", selection: $model.settings.maxPixelSize) {
                    ForEach(CleanupSettings.pixelSizeOptions, id: \.self) { Text("\($0) px").tag($0) }
                }
                VStack(alignment: .leading) {
                    Text("Quality: \(Int((model.settings.quality * 100).rounded()))%")
                    Slider(value: $model.settings.quality, in: 0.4...0.95, step: 0.05) {
                        Text("Quality")
                    }
                }
            } header: {
                Text("Resize to")
            } footer: {
                Text("Saved as JPEG so copies open anywhere, including HEIC originals. iPhone photos are usually 4032 px on the long side. 2048 px still looks sharp on a phone or TV.")
            }

            Section {
                Stepper(value: $model.settings.batchSize, in: 10...200, step: 10) {
                    Text("Delete originals every \(model.settings.batchSize) photos")
                }
            } footer: {
                Text("iOS asks you to approve every deletion, so the app stops and waits for you after each batch. Bigger batches mean fewer taps, but the copies use extra space until you approve.")
            }
        }
        .disabled(model.runState != .idle)
    }

    private var previewSection: some View {
        Section("Preview") {
            if model.isScanning {
                ProgressView(value: model.scanProgress) { Text("Scanning library…") }
            } else if let candidates = model.candidates {
                if candidates.isEmpty {
                    Text("No photos match these settings.")
                        .foregroundStyle(.secondary)
                } else {
                    LabeledContent("Photos", value: "\(candidates.count)")
                    LabeledContent("Current size", value: formatBytes(model.totalOriginalBytes))
                    if model.isEstimating {
                        LabeledContent("After resizing") { ProgressView() }
                    } else if let newBytes = model.estimatedNewBytes {
                        LabeledContent("After resizing", value: "≈ \(formatBytes(newBytes))")
                        LabeledContent("Space freed", value: "≈ \(formatBytes(model.totalOriginalBytes - newBytes))")
                            .fontWeight(.semibold)
                    }
                    NavigationLink("Review photos") {
                        PreviewListView(model: model)
                    }
                }
            }

            Button(model.candidates == nil ? "Scan library" : "Scan again") {
                Task { await model.scan() }
            }
            .disabled(model.isScanning || model.runState != .idle)
        }
    }

    @ViewBuilder
    private var runSection: some View {
        if model.runState != .idle {
            Section {
                ProgressView(value: Double(model.runDone), total: Double(max(model.runTotal, 1))) {
                    Text("\(model.runDone) of \(model.runTotal)")
                }
                LabeledContent("Replaced", value: "\(model.runReplaced)")
                LabeledContent("Skipped", value: "\(model.runSkipped)")
                if model.runFailed > 0 {
                    LabeledContent("Failed (will retry next scan)", value: "\(model.runFailed)")
                }
                LabeledContent("Space saved", value: formatBytes(model.runBytesSaved))
                Button(model.runState == .stopping ? "Stopping…" : "Stop after this photo", role: .cancel) {
                    model.stopRun()
                }
                .disabled(model.runState == .stopping)
            } header: {
                Text("Running")
            } footer: {
                Text("Keep the app open, ideally with the phone plugged in. The screen stays on while this runs. If iOS closes the app, scan again and it picks up where it stopped.")
            }
        } else if let candidates = model.candidates, !candidates.isEmpty, !model.isScanning {
            Section {
                Button("Resize \(candidates.count) photos", role: .destructive) {
                    confirmStart = true
                }
                .disabled(model.isEstimating)
            }
        }

        if let message = model.statusMessage {
            Section {
                Text(message)
            }
        }
    }

    private var historySection: some View {
        Section {
            LabeledContent("Photos replaced", value: "\(model.journal.replacements.count)")
            LabeledContent("Skipped (wouldn't shrink)", value: "\(model.journal.skipped.count)")
            if !model.journal.pendingDeletion.isEmpty && model.runState == .idle {
                Button("Delete \(model.journal.pendingDeletion.count) replaced originals") {
                    Task { await model.deletePendingOriginals() }
                }
            }
            if !model.journal.skipped.isEmpty && model.runState == .idle {
                Button("Retry skipped photos") { model.forgetSkipped() }
            }
        } header: {
            Text("History")
        } footer: {
            Text("Deleted originals go to Albums → Recently Deleted. You get the space back when you empty that album, or after 30 days.")
        }
    }
}

#Preview {
    ContentView(model: CleanupModel())
}
