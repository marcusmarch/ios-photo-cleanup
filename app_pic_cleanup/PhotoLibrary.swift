import Foundation
import Photos
import UIKit

nonisolated enum PhotoError: LocalizedError {
    case assetNotFound, noImageData, couldNotCreateAsset

    var errorDescription: String? {
        switch self {
        case .assetNotFound: "The photo is no longer in the library."
        case .noImageData: "The photo's data couldn't be loaded (it may still be downloading from iCloud)."
        case .couldNotCreateAsset: "The resized copy couldn't be saved."
        }
    }
}

/// Thin async wrapper around PhotoKit.
nonisolated enum PhotoLibrary {
    static var authorizationStatus: PHAuthorizationStatus {
        PHPhotoLibrary.authorizationStatus(for: .readWrite)
    }

    static func requestAccess() async -> PHAuthorizationStatus {
        await PHPhotoLibrary.requestAuthorization(for: .readWrite)
    }

    static func asset(_ id: String) -> PHAsset? {
        PHAsset.fetchAssets(withLocalIdentifiers: [id], options: nil).firstObject
    }

    /// Finds photos matching the settings. Slow on big libraries; call off the main actor.
    static func scan(
        settings: CleanupSettings,
        excluding excluded: Set<String>,
        progress: @Sendable (_ done: Int, _ total: Int) -> Void
    ) -> [Candidate] {
        let options = PHFetchOptions()
        options.predicate = NSPredicate(
            format: "mediaType == %d AND creationDate < %@",
            PHAssetMediaType.image.rawValue,
            settings.cutoffStartOfDay as NSDate
        )
        options.sortDescriptors = [NSSortDescriptor(key: "creationDate", ascending: true)]
        // Skip shared albums and photos synced from a computer; those can't be deleted.
        options.includeAssetSourceTypes = [.typeUserLibrary]

        let assets = PHAsset.fetchAssets(with: options)
        let total = assets.count
        var candidates: [Candidate] = []

        for index in 0..<total {
            if index % 100 == 0 { progress(index, total) }
            let asset = assets.object(at: index)
            guard !excluded.contains(asset.localIdentifier),
                  asset.canPerform(.delete)
            else { continue }

            let isLive = asset.mediaSubtypes.contains(.photoLive)
            if isLive && !settings.includeLivePhotos { continue }

            // Live check above runs first because reading the size is the slow part.
            let size = totalFileSize(of: asset)
            guard settings.includes(fileSize: size, isLivePhoto: isLive) else { continue }

            candidates.append(Candidate(
                id: asset.localIdentifier,
                creationDate: asset.creationDate,
                fileSize: size,
                pixelWidth: asset.pixelWidth,
                pixelHeight: asset.pixelHeight,
                isLivePhoto: isLive
            ))
        }
        progress(total, total)
        return candidates
    }

    /// Sum of all stored resources (original, edits, Live Photo video).
    /// `fileSize` isn't public API, but is the standard way to read it without downloading.
    static func totalFileSize(of asset: PHAsset) -> Int64 {
        PHAssetResource.assetResources(for: asset).reduce(0) { sum, resource in
            sum + ((resource.value(forKey: "fileSize") as? NSNumber)?.int64Value ?? 0)
        }
    }

    /// Full-quality image data of the current (edited, if any) version. Downloads from iCloud if needed.
    static func loadImageData(id: String) async throws -> Data {
        guard let asset = asset(id) else { throw PhotoError.assetNotFound }
        let options = PHImageRequestOptions()
        options.version = .current
        options.deliveryMode = .highQualityFormat
        options.isNetworkAccessAllowed = true

        return try await withCheckedThrowingContinuation { continuation in
            PHImageManager.default().requestImageDataAndOrientation(for: asset, options: options) { data, _, _, info in
                if let data {
                    continuation.resume(returning: data)
                } else {
                    let error = info?[PHImageErrorKey] as? Error ?? PhotoError.noImageData
                    continuation.resume(throwing: error)
                }
            }
        }
    }

    static func thumbnail(id: String, side: CGFloat) async -> UIImage? {
        guard let asset = asset(id) else { return nil }
        let options = PHImageRequestOptions()
        options.deliveryMode = .highQualityFormat // single callback
        options.resizeMode = .fast
        options.isNetworkAccessAllowed = true

        return await withCheckedContinuation { continuation in
            PHImageManager.default().requestImage(
                for: asset,
                targetSize: CGSize(width: side, height: side),
                contentMode: .aspectFill,
                options: options
            ) { image, _ in
                continuation.resume(returning: image)
            }
        }
    }

    private final class IDBox: @unchecked Sendable {
        var id: String?
    }

    /// Saves `fileURL` as a new photo that copies the original's date, location,
    /// favorite flag and album membership. Returns the new asset's ID.
    static func saveReplacement(fileURL: URL, fileExtension: String, replacing originalID: String) async throws -> String {
        guard let original = asset(originalID) else { throw PhotoError.assetNotFound }

        let originalName = PHAssetResource.assetResources(for: original)
            .first { $0.type == .photo }?.filename
        let newName = originalName.map { ($0 as NSString).deletingPathExtension + "." + fileExtension }

        var albums: [PHAssetCollection] = []
        PHAssetCollection.fetchAssetCollectionsContaining(original, with: .album, options: nil)
            .enumerateObjects { album, _, _ in
                if album.canPerform(.addContent) { albums.append(album) }
            }

        let creationDate = original.creationDate
        let location = original.location
        let isFavorite = original.isFavorite
        let box = IDBox()

        try await PHPhotoLibrary.shared().performChanges {
            let request = PHAssetCreationRequest.forAsset()
            let resourceOptions = PHAssetResourceCreationOptions()
            resourceOptions.originalFilename = newName
            request.addResource(with: .photo, fileURL: fileURL, options: resourceOptions)
            request.creationDate = creationDate
            request.location = location
            request.isFavorite = isFavorite

            guard let placeholder = request.placeholderForCreatedAsset else { return }
            box.id = placeholder.localIdentifier
            for album in albums {
                PHAssetCollectionChangeRequest(for: album)?.addAssets([placeholder] as NSArray)
            }
        }

        guard let newID = box.id else { throw PhotoError.couldNotCreateAsset }
        return newID
    }

    /// Moves assets to Recently Deleted. iOS shows its own confirmation;
    /// returns `false` if the user declined it.
    static func deleteAssets(ids: [String]) async throws -> Bool {
        let assets = PHAsset.fetchAssets(withLocalIdentifiers: ids, options: nil)
        guard assets.count > 0 else { return true }
        do {
            try await PHPhotoLibrary.shared().performChanges {
                PHAssetChangeRequest.deleteAssets(assets)
            }
            return true
        } catch let error as NSError
            where (error.domain == PHPhotosErrorDomain && error.code == PHPhotosError.userCancelled.rawValue)
            || (error.domain == NSCocoaErrorDomain && error.code == NSUserCancelledError) {
            return false
        }
    }
}
