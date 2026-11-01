# Design decisions

Why the app works the way it does. Before changing any of these, read the reasoning; most exist because the obvious alternative fails on iOS. When you make a new significant decision, add an entry here (newest at the bottom), and update `product.md` if it changes a safety rule.

Format: **Decision**, then *Why*, *Rejected alternatives*, *Consequences*.

---

## 1. Replace-and-delete instead of editing photos in place

**Decision:** For each photo, save a new smaller asset, then delete the original.

- *Why:* iOS has no API to shrink an existing photo. PhotoKit edits (`PHContentEditingOutput`) keep the original alongside the edited render so edits can be reverted, so "editing to a smaller size" **increases** storage.
- *Rejected:* in-place PhotoKit edits (use more space); exporting to Files (doesn't free library space).
- *Consequences:* the copy is a new asset, so the app must copy date, location, favorite and album membership itself (`PhotoLibrary.saveReplacement`). The "date added" becomes today, edit history is lost (edits are baked in), and Live Photos become stills.

## 2. Deletion goes through PhotoKit, in confirmed batches

**Decision:** Collect replaced originals in `Journal.pendingDeletion`, and every `batchSize` photos call `PHAssetChangeRequest.deleteAssets`, which shows iOS's confirmation.

- *Why:* iOS always asks the user to approve deletions; apps can't bypass it, and shouldn't. Deleted items go to Recently Deleted (a 30-day safety net).
- *Rejected:*
  - deleting each photo right after its copy: one prompt per photo, unusable for hundreds
  - deleting everything at the end: copies of a whole run pile up first, which can fail on a phone that's already full, the exact situation this app is for
- *Consequences:* long runs pause for a tap at each batch. Batch size is a user setting (default 50): fewer taps against less extra space in use.

## 3. Stop the run if a deletion isn't approved

**Decision:** If the user declines (or deletion fails), stop. Don't keep making copies.

- *Why:* continuing would add copies without removing originals, using **more** space.
- *Consequences:* originals stay in `pendingDeletion`; "Delete replaced originals" in History retries.

## 4. Save before delete, and record everything in a journal

**Decision:** Write `Journal` (`replacements`, `pendingDeletion`, `skipped`) to disk after every photo. A scan excludes `Journal.excludedIDs`, which includes the IDs of our own copies.

- *Why:* runs can last a long time and iOS suspends or kills apps in the background. The journal makes runs resumable without duplicates, guarantees an original is never deleted unless its copy was saved, and stops the app from shrinking its own copies again on the next scan.
- *Rejected:* in-memory progress only (lost when iOS closes the app).
- *Consequences:* originals recovered from Recently Deleted stay marked as replaced and won't be processed again. Deleting the app resets the journal.

## 5. Always output JPEG

**Decision:** Copies are always JPEG, even for HEIC originals.

- *Why:* explicit choice by the project owner for maximum compatibility (old PCs, websites, other tools). Many users' older photos are already JPEG.
- *Rejected:* HEIC output, which makes files about half the size but doesn't open everywhere. It was the first implementation.
- *Consequences:* copies are bigger than HEIC copies would be. A HEIC original that isn't downscaled usually gets a bigger JPEG, so it's skipped by decision 6 and stays HEIC. Making the format a setting is a reasonable fork.

## 6. Skip photos whose copy isn't at least 20% smaller

**Decision:** `CleanupSettings.isWorthReplacing`: the copy must be ≤ 80% of the original's size (`maxSizeRatio = 0.8`), or the photo is left alone and recorded in `journal.skipped`.

- *Why:* re-encoding always loses a bit of quality and loses the edit history, date added and Live Photo motion. That's not worth it for a small saving, and some copies would even be larger.
- *Consequences:* "original size" is the total of all the asset's stored resources (original + edits + Live Photo video), since that's what deleting frees. "Retry skipped photos" clears `skipped` after settings change.

## 7. Estimate savings from real samples

**Decision:** After a scan, actually resize up to 6 photos spread across the list (`sampleIndices`) and average the ratios (`estimatedRatio`), counting would-be-skipped samples as unchanged.

- *Why:* JPEG output size depends heavily on content, noise and the original's compression, so a formula based on pixel count can't predict it reliably. For example, a smooth wallpaper and a grainy photo with the same dimensions shrink very differently.
- *Rejected:* a pixel-ratio formula; resizing every photo for the preview (far too slow for thousands of photos, and may download from iCloud).
- *Consequences:* the estimate takes a few seconds and is approximate. The per-photo before/after viewer shows exact results.

## 8. Preview is strictly read-only

**Decision:** Scanning, estimating and the before/after viewer never write to the library. Only `CleanupModel.startRun()` does, after a confirmation dialog.

- *Why:* the user's core requirement is to see what the settings will do before anything happens.
- *Consequences:* any change to the settings clears the preview, so a run always matches what was previewed.

## 9. Live Photos are opt-in

**Decision:** Excluded unless "Include Live Photos" is on.

- *Why:* the copy is a still image; the motion part is lost. That should be a conscious choice.

## 10. Foreground-only runs that keep the screen on

**Decision:** Disable the idle timer during a run, and request a short background grace period (`beginBackgroundTask`). No background processing.

- *Why:* iOS gives apps about 30 seconds in the background. Background processing tasks (`BGProcessingTask`) run at the system's discretion and can't show the deletion confirmation. The journal (decision 4) covers interruptions.
- *Consequences:* users should keep the app open and the phone plugged in.

## 11. Scope: iPhone and iPad, no dependencies, iOS 27.2 target

**Decision:** `SUPPORTED_PLATFORMS = iphoneos iphonesimulator`. Apple frameworks only. The deployment target is what the Xcode 27 template created.

- *Why:* the problem is a full iPhone, and there's nothing on macOS to clean up this way. With no dependencies there are no supply-chain risks, and forking is easy.
- *Consequences:* the target could be lowered to about iOS 17 (see README → Requirements).

## 12. Decision logic lives in pure, tested functions

**Decision:** Rules that decide what is scanned, skipped or estimated are `nonisolated` pure functions in `CleanupSettings` (and `Journal.excludedIDs`). PhotoKit code in `PhotoLibrary` stays thin.

- *Why:* PhotoKit needs a real library and permission prompts, so it can't be unit tested. Pure rules can be. The 20% rule was duplicated in 3 places before this.
- *Consequences:* new rules need unit tests in `app_pic_cleanupTests/`. End-to-end behavior is checked by hand in the Simulator (README → Trying it in the Simulator).
