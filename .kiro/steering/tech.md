# Tech stack and conventions

- **Language/UI:** Swift, SwiftUI, Observation (`@Observable`). No third-party dependencies; keep it that way unless there's a strong reason.
- **Frameworks:** PhotoKit (`Photos`), ImageIO, UniformTypeIdentifiers, UIKit (idle timer, background task, `UIImage`).
- **Platforms:** iPhone and iPad only (`SUPPORTED_PLATFORMS = iphoneos iphonesimulator`). Deployment target iOS 27.2.
- **Xcode:** 27.2+. The project file is Xcode 27's **JSON format** at `app_pic_cleanup.xcodeproj/project.xcproj` (not `project.pbxproj`).
- **Tests:** Swift Testing (`import Testing`, `@Test`, `#expect`) in the `app_pic_cleanupTests` target, hosted by the app, using `@testable import app_pic_cleanup`.

## Build and test commands

```sh
# Build (use any available simulator; list them with `xcrun simctl list devices available`)
xcodebuild -scheme app_pic_cleanup -destination 'platform=iOS Simulator,name=iPhone 18 Pro' build

# Run all unit tests
xcodebuild test -scheme app_pic_cleanup -destination 'platform=iOS Simulator,name=iPhone 18 Pro'

# Generate dated test photos and add them to the booted simulator
swift scripts/make_test_photos.swift /tmp/test_photos && xcrun simctl addmedia booted /tmp/test_photos/*
```

After every code change: build, run the tests, and fix all errors **and warnings** before you finish.

## Project file notes

- `app_pic_cleanup/` and `app_pic_cleanupTests/` are **synchronized folders**: any `.swift` file placed in them is automatically part of that target. You don't need to edit the project file to add source files.
- Info.plist is generated. Add keys as `INFOPLIST_KEY_*` build settings in `project.xcproj` (e.g. `INFOPLIST_KEY_NSPhotoLibraryUsageDescription`).
- Prefer adding new targets through Xcode's UI (File → New → Target) rather than hand-editing the JSON.

## Concurrency conventions

- The app target sets `SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor` with approachable concurrency (Swift 5 language mode).
- Pure value types and helpers used off the main actor are marked **`nonisolated`** (`CleanupSettings`, `Candidate`, `Journal`, `ImageResizer`, `PhotoLibrary`, `formatBytes`).
- Heavy work (scanning, decoding, encoding) runs in `Task.detached` and passes only `Sendable` values (IDs, `Data`, settings structs), never `PHAsset` objects.
- `CleanupModel` and the views stay on the main actor.

## Coding conventions

- Put decision logic in **small pure functions** (see the `Rules` section of `CleanupSettings.swift`) and test them. Keep PhotoKit calls thin and inside `PhotoLibrary`.
- Any new rule that decides what gets resized, skipped or deleted **must have unit tests**. For image-processing changes, add a test in `ImageResizerTests.swift` using its in-memory `TestImage` helper.
- Before finishing, check that a new test can fail: break the code briefly and confirm the test catches it.
- User-facing text is plain and short. Explain consequences (space, deletion, iCloud) wherever a setting has them.
- Accessibility: label images and icons (`accessibilityLabel`, or `accessibilityHidden` for decorative ones).

## Keep documentation current

With every change that affects behavior, setup, settings or file layout, update in the same change:

- `README.md`: features, limitations, the customizing table, the test coverage list, the project layout
- `.kiro/steering/product.md`: if the flow or safety rules change
- `.kiro/steering/structure.md`: if files are added, removed or change responsibility
- this file: if commands, tooling or conventions change
