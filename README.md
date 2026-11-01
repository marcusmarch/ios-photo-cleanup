# Photo Cleanup

An iPhone app that frees up storage by replacing large, older photos with smaller JPEG copies. It's meant for people who have already backed up their originals (to a computer, a NAS, Google Photos, and so on) and want their phone's library to take up less space.

You choose the rules: photos **taken before a date** and **larger than a file size**. Then you **preview** exactly what will happen before anything is changed.

> ⚠️ **This app deletes photos.** Originals go to *Recently Deleted* (recoverable for 30 days), but only use it on photos you have backed up somewhere else. If iCloud Photos is on, deleting also removes the original from iCloud and your other devices.

## Features

- **Filters:** "taken before" date, minimum file size, and Live Photos included or not.
- **Output:** longest side (1280–3024 px) and JPEG quality. Copies are always JPEG, including copies of HEIC originals, so they open anywhere.
- **Preview:**
  - Totals for current size and space freed. The estimate comes from really resizing a sample of photos, not a guess.
  - A per-photo list with thumbnails and estimated new sizes.
  - A before/after viewer that shows each photo's real resized result and exact sizes. Nothing is saved from the viewer.
- **Keeps what matters:** each copy keeps the date taken, location, camera EXIF, favorite status and album membership. Sideways-stored photos are saved upright.
- **Built for long runs:**
  - Works through hundreds or thousands of photos, one at a time.
  - Progress is saved after every photo, so it resumes safely if the app is closed. It never makes duplicate copies and never shrinks a copy again.
  - The screen stays awake while it runs.
- **Safe by default:**
  - Photos whose copy wouldn't be at least 20% smaller are left alone.
  - Originals are deleted in batches, and iOS asks you to approve each batch.

## How it works

iOS has no way to shrink a photo in place. An edit made through PhotoKit keeps the original alongside the edit, which uses *more* space. So for each matching photo the app:

1. Loads the full-quality image (downloading from iCloud if needed).
2. Resizes and re-encodes it as JPEG with ImageIO, keeping the metadata.
3. Skips the photo if the copy isn't at least 20% smaller.
4. Saves the copy as a new photo with the same date, location, favorite flag and albums.
5. Records the original → copy pair in a journal file.
6. Every *N* photos (your batch size), asks iOS to delete the replaced originals. iOS always shows a confirmation for deletions, and apps can't bypass it.

You get the storage back once *Recently Deleted* is emptied (manually, or automatically after 30 days).

### Known limitations

- **Live Photos become still photos.** That's why they're excluded unless you turn them on.
- **"Date added"** of the copy is the day it was created. The capture date (what Photos sorts by) is preserved.
- **iCloud Photos with "Optimize iPhone Storage":** the phone may only hold small previews of old photos, so this mostly frees *iCloud* space rather than phone space.
- **Edited photos:** the copy has the edits baked in, and the edit history is not kept.
- **Background:** iOS suspends apps in the background, so keep the app open, ideally plugged in. If iOS closes the app, scan again and it continues where it stopped.

## Requirements

- Xcode 27.2 or later. The project uses Xcode 27's JSON project format (`project.xcproj`).
- iOS 27.2 or later (the current deployment target). Most of the code only needs iOS 17. Lowering the target mainly means replacing `PHAssetResource.filename` with the older `originalFilename` in `PhotoLibrary.swift`.

## Getting started

1. Fork and clone the repo, then open `app_pic_cleanup.xcodeproj`.
2. **Signing:** select the project, then each target (`app_pic_cleanup` and `app_pic_cleanupTests`) → *Signing & Capabilities*:
   - set **Team** to your Apple ID (a free personal team works for running on your own phone)
   - change the **Bundle Identifier** to something unique, such as `com.yourname.photocleanup`
3. Choose a simulator or your iPhone as the run destination and press **⌘R**.
4. On a real iPhone, the first run also needs *Settings → Privacy & Security → Developer Mode* turned on.

### Trying it in the Simulator

A fresh simulator only has a few sample photos, and photos you drag in are dated today, so they don't match "taken before". A script generates realistic test photos with old dates, JPEG and HEIC, plus ones that *should* be filtered out:

```sh
swift scripts/make_test_photos.swift /tmp/test_photos
xcrun simctl addmedia booted /tmp/test_photos/*
```

| File | What it tests |
|---|---|
| `2014_beach.jpg` … `2022_park.jpg` | Old, large JPEG/HEIC: should be resized |
| `2017_portrait.jpg` | Stored sideways (EXIF orientation 6): copy must be upright |
| `2021_heic_48mp.heic` | 48 MP HEIC, about 18 MB |
| `2015_small.jpg` | Too small: excluded by the size filter |
| `2020_compact.heic` | Already compact: should be *skipped* (copy not 20% smaller) |
| `recent.jpg` | Taken last week: excluded by the date filter |

To start over, use *Device → Erase All Content and Settings* in the Simulator.

## Running the tests

In Xcode: **⌘U**, or the ◇ buttons in the Test navigator (⌘6) or next to each `@Test`.

From the terminal:

```sh
xcodebuild test -scheme app_pic_cleanup -destination 'platform=iOS Simulator,name=iPhone 18 Pro'
```

The tests use [Swift Testing](https://developer.apple.com/documentation/testing) and cover:

- **Rules:** scan filters, the "taken before" cutoff, the 20% replace rule, savings estimate and sampling, resize dimensions, and saving settings.
- **Image processing:** output is JPEG for both JPEG and HEIC input, the long edge is scaled without upscaling, rotation is baked in (checked pixel by pixel), date/GPS EXIF are kept, quality changes size, and invalid input is rejected.
- **Journal:** what scans exclude (including our own copies) and saving/loading, with corrupt or missing files handled.

Anything that talks to the real photo library (`PhotoLibrary.swift`, the run loop in `CleanupModel.swift`) is checked by hand in the Simulator with the test photos above.

## Project layout

```
app_pic_cleanup/              App sources (folder is auto-synced into the target)
  MyApp.swift                 App entry point, owns the CleanupModel
  ContentView.swift           Main screen: settings, preview totals, run controls, history
  PreviewListView.swift       List of matching photos + AssetThumbnail
  PhotoDetailView.swift       Before/after viewer for one photo (nothing is saved)
  CleanupModel.swift          @Observable state: scan, estimate, run loop, batched deletion
  CleanupSettings.swift       Settings, Candidate, and the pure decision rules
  ImageResizer.swift          ImageIO resize + JPEG encode, keeps metadata
  PhotoLibrary.swift          PhotoKit wrapper: scan, load, save copy, delete
  Journal.swift               Persistent progress (replaced / pending deletion / skipped)
app_pic_cleanupTests/         Swift Testing unit tests (also auto-synced)
scripts/make_test_photos.swift  Generates dated test photos for the Simulator
.kiro/steering/               Project context for Kiro (and other AI tools)
```

## Customizing

Common changes and where to make them:

| Change | Where |
|---|---|
| "At least 20% smaller" threshold | `CleanupSettings.maxSizeRatio` |
| Longest-side options | `CleanupSettings.pixelSizeOptions` |
| Default settings | `CleanupSettings.default` |
| Output format (e.g. back to HEIC) | `ImageResizer.resize`: the `CGImageDestinationCreateWithData` type and the `fileExtension` |
| Which photos are scanned (e.g. skip favorites, screenshots) | `PhotoLibrary.scan` (PhotoKit predicate) and `CleanupSettings.includes` |
| Number of samples for the estimate | `CleanupModel.estimateSavings` |

Keep decision logic in pure functions (like the ones in `CleanupSettings`) and add tests for them in `app_pic_cleanupTests/`.

## Using with Kiro and other AI tools

This repo is set up to be modified with AI coding assistants. `.kiro/steering/` holds context that [Kiro](https://kiro.dev) loads automatically:

- `product.md`: what the app does and the safety rules it must keep
- `tech.md`: stack, build/test commands, and coding conventions
- `structure.md`: where things live and how data flows

These are plain Markdown, so other tools can read them too. Point your assistant at them, or copy them into its rules file. The steering also tells the assistant to keep this README, the steering files and the tests up to date with every change.

## License

Not yet chosen. Add a `LICENSE` file before publishing. MIT is a common choice for projects meant to be forked.
