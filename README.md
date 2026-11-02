# Photo Cleanup

1. Back up your photos
2. Set your settings:
<img  height="486" alt="image" src="https://github.com/user-attachments/assets/d9868fe2-3ac2-4545-9a95-3b3262745a57" />

4. Then hit Start and watch it run!
<img  height="486" alt="image" src="https://github.com/user-attachments/assets/de528f4f-e2c5-40cc-9213-2c637050948f" />

6. Confirm every batch delete
<img height="486" alt="image" src="https://github.com/user-attachments/assets/03b589f6-32c5-4991-a8a9-67d6d9733db6" />

6. Done!


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

### 1. One-time Xcode setup

1. Install Xcode from the App Store and open it once, so it can finish installing its components (including an iOS Simulator).
2. Point the command-line tools at Xcode. If you skip this, the Terminal commands below (`xcodebuild`, `xcrun simctl`) fail with *"requires Xcode, but active developer directory … is a command line tools instance"*. It asks for your password:

   ```sh
   sudo xcode-select -s /Applications/Xcode.app/Contents/Developer
   sudo xcodebuild -license accept
   ```

   Check it worked with `xcodebuild -version`.

### 2. Open, sign and run

1. Fork and clone the repo, then open `app_pic_cleanup.xcodeproj`.
2. **Signing:** select the project, then each target (`app_pic_cleanup` and `app_pic_cleanupTests`) → *Signing & Capabilities*:
   - set **Team** to your Apple ID (a free personal team works for running on your own phone)
   - change the **Bundle Identifier** to something unique, such as `com.yourname.photocleanup`

   Signing is only needed for a real iPhone. The Simulator and the tests work without it.
3. Choose a simulator (e.g. *iPhone 18 Pro*) or your iPhone as the run destination and press **⌘R**.
4. On a real iPhone, the first run also needs *Settings → Privacy & Security → Developer Mode* turned on.

## Trying it in the Simulator

The Simulator comes with 6 of Apple's sample photos (dated 2009–2018), all under 3 MB, so with default settings the scan finds nothing. A script generates realistic test photos with old capture dates, JPEG and HEIC, including some that should be filtered out.

You can drag your own photos onto the Simulator window instead. Photos keep the capture date stored in their EXIF info. Images without one (screenshots, many downloads) are dated the day you add them, so they won't match "taken before".

### Step by step

1. **Start the app in the Simulator** (⌘R in Xcode). The next commands add photos to the *running* ("booted") simulator; with none running they fail with *"No devices are booted"*.
2. **Allow photo access** when the app asks. Choose full access, not *Limited*.
3. **Generate the test photos and add them.** Run these from the repo folder:

   ```sh
   swift scripts/make_test_photos.swift /tmp/test_photos
   xcrun simctl addmedia booted /tmp/test_photos/*
   ```

   The first command can take a minute or more (one test photo is 48 megapixels). It prints each file as it's written. Open the Simulator's Photos app to see them under their original years.
4. **Back in the app, tap *Scan library*** with the default settings (taken before one year ago, larger than 3 MB, longest side 2048 px, quality 70%).

### What you should see

| File | Size | With default settings |
|---|---|---|
| `2014_beach.jpg` | 3.9 MB | Listed, then replaced |
| `2016_mountains.jpg` | 5.9 MB | Listed, then replaced |
| `2017_portrait.jpg` | 5.9 MB | Listed, then replaced. Stored sideways (EXIF orientation 6); the copy must look upright |
| `2018_city.jpg` | 5.8 MB | Listed, then replaced |
| `2019_heic.heic` | 6.3 MB | Listed, then replaced (HEIC → JPEG) |
| `2021_heic_48mp.heic` | 18.2 MB | Listed, then replaced (48 MP HEIC → JPEG) |
| `2022_park.jpg` | 5.9 MB | Listed, then replaced |
| `2015_small.jpg` | 0.2 MB | Not listed: below the size filter |
| `2020_compact.heic` | 0.3 MB | Not listed: below the size filter (smaller than the lowest setting, 0.5 MB) |
| `recent.jpg` | 5.9 MB | Not listed: taken last week, after the date filter |
| Apple's 6 sample photos | 1.3–2.8 MB | Not listed. Lower *Larger than* to 1.5 MB and 5 of them appear |

- **Preview:** *Photos* should be **7** and *Current size* about **52 MB**. *Space freed* appears a few seconds later and should be most of that, since the copies total only a few MB.
- **Review photos:** tap a few, and switch *Original* / *Resized* to compare quality and see exact sizes.
- **Run:** tap *Resize 7 photos* and confirm. At the end, iOS asks to delete 7 photos; tap *Delete*.
- **Result:** in the Simulator's Photos app, each old photo now appears once, as a 2048 px JPEG of roughly 0.3–0.7 MB (about 4 MB in total), still under its original date. The originals are in the *Recently Deleted* album.
- **History** in the app shows *Photos replaced: 7*.

### Comparing original and copy side by side

Open the *Recently Deleted* album in the Simulator's Photos app, select an original and tap *Recover*. It's back next to its smaller copy, so you can compare them full screen. The app remembers recovered originals as already replaced, so scanning again won't shrink them a second time.

### Starting over

*Device → Erase All Content and Settings* in the Simulator removes all photos, the app and its progress history. Then repeat the steps above. To keep the photos but reset only the app's history (*Photos replaced*, *Skipped*), delete the app from the Simulator's home screen and run it again from Xcode.

## Before the first run on your real iPhone

1. **Make sure your backup really has these photos.** Spot-check a few of the oldest and newest in the date range in your backup itself.
2. **Check iCloud Photos** (*Settings → [your name] → iCloud → Photos*). If it's on, deleted originals are removed from iCloud and all your devices too. With *Optimize iPhone Storage* on, the phone may only hold small previews of old photos, so you'll mostly free iCloud space rather than phone space.
3. **Start small:** set *Taken before* to cover just one month, scan, and look through *Review photos*.
4. **Do one run, then check the copies** in Photos: date, location, and that they look good enough to you. If not, change *Longest side* or *Quality* before going further. The photos already done stay as they are (their originals are in *Recently Deleted* for 30 days), because the app never processes a photo twice.
5. **Then widen the date** to your full backup cutoff. Keep the phone plugged in with the app open; it keeps the screen on.
6. **Empty *Recently Deleted*** when you're happy. That's when the space actually comes back.

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
- `decisions.md`: the key design decisions, the alternatives that were rejected, and why. Read this before "simplifying" something.
- `tech.md`: stack, build/test commands, simulator testing, and coding conventions
- `structure.md`: where things live and how data flows

These are plain Markdown, so other tools can read them too. Point your assistant at them, or copy them into its rules file. The steering also tells the assistant to keep this README, the steering files and the tests up to date with every change, and to record new design decisions in `decisions.md`.

Example requests that work well with this context:

- "Add a setting to skip favorites, with tests."
- "Add an option to keep HEIC output instead of JPEG."
- "Set up the Simulator with test photos and tell me what the scan should show."

## License

Not yet chosen. Add a `LICENSE` file before publishing. MIT is a common choice for projects meant to be forked.
