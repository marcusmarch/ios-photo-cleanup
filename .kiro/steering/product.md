# Product: Photo Cleanup

An iOS app that frees iPhone storage by replacing large, old photos with smaller JPEG copies. Target user: someone who has **already backed up** their originals and wants the phone library to take less space.

## Core flow

1. User sets rules: taken before a date, larger than N MB, include Live Photos or not, longest side, JPEG quality, deletion batch size.
2. **Scan + preview** (read-only): matching photos, total size, and estimated savings measured by actually resizing a small sample. There's a per-photo before/after viewer.
3. **Run**: for each photo, resize → save as a new asset (keeping date, location, favorite, albums) → record in the journal. Every batch, delete the replaced originals (iOS shows a confirmation).
4. Originals go to Recently Deleted. Space returns when that is emptied.

## Safety rules (must be preserved by any change)

- **Preview never modifies the library.** Only `CleanupModel.startRun()` writes.
- **Never delete an original before its copy is saved and recorded** in `Journal` (`replacements` + `pendingDeletion`).
- **Never re-process our own copies.** `Journal.excludedIDs` includes copy IDs.
- **Skip photos whose copy isn't meaningfully smaller** (`CleanupSettings.isWorthReplacing`, currently ≥20% smaller).
- **Deletion only via PhotoKit** (`PHAssetChangeRequest.deleteAssets`), so iOS's confirmation and Recently Deleted always apply. Never try to bypass them.
- If the user declines a deletion, **stop the run**. Otherwise copies would pile up and use *more* space.
- Output is **always JPEG** (compatibility was an explicit user choice), including for HEIC originals.
- Live Photos are **opt-in**, because the copy becomes a still photo.

## Platform constraints to keep in mind

- iOS cannot shrink a photo in place. PhotoKit edits keep the original, so the app uses replace-and-delete.
- Apps are suspended in the background. Runs are foreground-only and resumable via the journal.
- With iCloud Photos on, deleting removes the photo from iCloud and all devices. The UI and README must keep warning about this.
