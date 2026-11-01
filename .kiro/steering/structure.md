# Project structure

```
app_pic_cleanup/                 App target sources (synchronized folder)
  MyApp.swift                    @main; owns a single CleanupModel via @State
  ContentView.swift              Main Form: auth states, settings, preview totals, run progress, history
  PreviewListView.swift          List of Candidates (+ AssetThumbnail view)
  PhotoDetailView.swift          Before/after of one photo with real resize output; read-only
  CleanupModel.swift             @Observable app state and orchestration (scan, estimate, run, delete)
  CleanupSettings.swift          CleanupSettings (persisted in UserDefaults), Candidate, pure rules, formatBytes
  ImageResizer.swift             ImageIO: resize + JPEG encode with metadata; downsample for display
  PhotoLibrary.swift             All PhotoKit access: auth, scan, file sizes, load data, thumbnails, save copy, delete
  Journal.swift                  Codable progress record in Application Support/journal.json
app_pic_cleanupTests/            Swift Testing unit tests (synchronized folder)
  CleanupRulesTests.swift        Filters, cutoff date, replace rule, estimate, sampling, dimensions, settings
  ImageResizerTests.swift        Real encode/decode tests with an in-memory TestImage builder
  JournalTests.swift             Exclusions and persistence (uses temp files, never the real journal)
scripts/make_test_photos.swift   Generates dated JPEG/HEIC test photos for the simulator
```

## Data flow

1. `ContentView` binds directly to `model.settings`. Any change saves the settings and clears the preview (`candidates = nil`).
2. `CleanupModel.scan()` → `PhotoLibrary.scan()` (detached), with a PhotoKit date predicate plus `CleanupSettings.includes`, excluding `journal.excludedIDs` → `[Candidate]`.
3. `estimateSavings()` resizes `sampleIndices(...)` candidates → `CleanupSettings.estimatedRatio`.
4. `startRun()` → `run()` loops over candidates → `process()`:
   - `PhotoLibrary.loadImageData` → `ImageResizer.resize` (detached)
   - `CleanupSettings.isWorthReplacing`? If not → `journal.skipped`
   - `PhotoLibrary.saveReplacement` → `journal.replacements` + `journal.pendingDeletion` → `journal.save()`
   - When `pendingDeletion.count >= batchSize` → `deletePendingOriginals()` (iOS confirmation). If declined → stop the run.
5. At the end, any remaining pending originals are deleted (with confirmation), and finished items are removed from `candidates`.

## Where to put new code

- New user setting → add a property to `CleanupSettings` (and to `.default`), a control in `ContentView.settingsSections`, a test, and a README row.
- New filter → pure check in `CleanupSettings`, called from `PhotoLibrary.scan`, plus tests.
- New PhotoKit operation → a static function in `PhotoLibrary`. Pass IDs in and out, not `PHAsset`s.
- New screen → its own `*View.swift` file, taking `CleanupModel` as a parameter.
