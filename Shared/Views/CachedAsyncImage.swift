import Foundation
import SwiftUI
import Combine

// MARK: - Platform Image Type
#if os(iOS) || os(visionOS) || os(watchOS)
import UIKit
typealias PlatformImage = UIImage
extension Image {
    init(platformImage: UIImage) {
        self = Image(uiImage: platformImage)
    }
}
#elseif os(macOS)
import AppKit
typealias PlatformImage = NSImage
extension Image {
    init(platformImage: NSImage) {
        self = Image(nsImage: platformImage)
    }
}
#endif

#if canImport(PDFKit)
import PDFKit
#endif

let globalMaxThumbnailSize: CGFloat = 400

// MARK: - Thumbnail Generator
enum ThumbnailSize: CustomStringConvertible {
    case small
    case large

    var dimensions: (width: CGFloat, height: CGFloat) {
        switch self {
        case .small:
            return (150, 150)
        case .large:
            return (globalMaxThumbnailSize, globalMaxThumbnailSize)
        }
    }

    var suffix: String {
        switch self {
        case .small: return "thumbnail.small"
        case .large: return "thumbnail.large"
        }
    }

    var description: String {
        switch self {
        case .small: return "small"
        case .large: return "large"
        }
    }
}

final actor ThumbnailGenerator: Sendable {
    nonisolated static let shared = ThumbnailGenerator()

    private let thumbnailQueue = DispatchQueue(label: "com.cachedAsyncImage.thumbnailQueue", qos: .userInitiated, attributes: .concurrent)

    private init() {}

    // Determine file extension based on format support
    private func getFileExtension() -> String {
        return "png"
    }

    func thumbnailPath(for url: URL, size: ThumbnailSize) -> String {
        let directory = url.deletingLastPathComponent().path
        let filename = url.deletingPathExtension().lastPathComponent
        let ext = getFileExtension()
        let path = "\(directory)/\(filename).\(size.suffix).\(ext)"
        Log.interface.notice("Thumbnail path computed: \(path, privacy: .public)")
        return path
    }

    func thumbnailExists(for path: URL, size: ThumbnailSize) -> Bool {
        let thumbnailPath = self.thumbnailPath(for: path, size: size)
        Log.interface.notice("Checking existence of thumbnail at path: \(thumbnailPath, privacy: .public)")
        return FileManager.default.fileExists(atPath: thumbnailPath)
    }

    func loadThumbnail(for path: URL, size: ThumbnailSize) -> sending PlatformImage? {
        let thumbnailPath = self.thumbnailPath(for: path, size: size)
        if FileManager.default.fileExists(atPath: thumbnailPath) {
            #if os(iOS) || os(visionOS) || os(watchOS)
            let image = PlatformImage(contentsOfFile: thumbnailPath)
            Log.interface.notice("Loaded thumbnail from path: \(thumbnailPath, privacy: .public)")
            return image
            #elseif os(macOS)
            let image = PlatformImage(contentsOfFile: thumbnailPath)
            Log.interface.notice("Loaded thumbnail from path: \(thumbnailPath, privacy: .public)")
            return image
            // Precache bitmap data due to https://wadetregaskis.com/nsimage-is-dangerous/
            #endif
        }
        return nil
    }

    @discardableResult
    func createThumbnails(for url: URL, smallSize: CGSize? = nil, largeSize: CGSize? = nil) throws -> (small: String, large: String) {
        Log.data.notice("Creating thumbnails for \(url, privacy: .public)")
        let smallThumbnailPath = self.thumbnailPath(for: url, size: .small)
        let largeThumbnailPath = self.thumbnailPath(for: url, size: .large)

        // Check if the file is a PDF
        let isPdf = url.pathExtension.lowercased() == "pdf"

        // Get the original image
        #if os(iOS) || os(visionOS) || os(watchOS)
        let originalImage: UIImage?

        if isPdf {
            // Handle PDF with white background
            originalImage = self.createImageFromPDF(url: url)
        } else {
            guard let data = try? Data(contentsOf: url) else {
                try? self.saveEmptyThumbnail(to: smallThumbnailPath)
                try? self.saveEmptyThumbnail(to: largeThumbnailPath)
                throw NSError(domain: "ThumbnailGeneratorError", code: 1, userInfo: [NSLocalizedDescriptionKey: "Failed to load image from path"])
            }
            originalImage = UIImage(data: data)
        }

        guard let originalImage = originalImage else {
            try? self.saveEmptyThumbnail(to: smallThumbnailPath)
            try? self.saveEmptyThumbnail(to: largeThumbnailPath)
            throw NSError(domain: "ThumbnailGeneratorError", code: 1, userInfo: [NSLocalizedDescriptionKey: "Failed to load image from path"])
        }
        #elseif os(macOS)
        let originalImage: NSImage?

        if isPdf {
            // Handle PDF with white background
            originalImage = self.createImageFromPDF(url: url)
        } else {
            originalImage = NSImage(contentsOf: url)
        }

        guard let originalImage = originalImage else {
            try? self.saveEmptyThumbnail(to: smallThumbnailPath)
            try? self.saveEmptyThumbnail(to: largeThumbnailPath)
            throw NSError(domain: "ThumbnailGeneratorError", code: 1, userInfo: [NSLocalizedDescriptionKey: "Failed to load image from path"])
        }
        #endif

        let originalSize = originalImage.size
        let originalAspectRatio = originalSize.width / originalSize.height

        // Generate the small thumbnail
        let smallMaxDimension = smallSize?.width ?? ThumbnailSize.small.dimensions.width
        let smallThumbnailDimensions: CGSize
        if originalSize.width > originalSize.height {
            // Landscape orientation
            smallThumbnailDimensions = CGSize(
                width: smallMaxDimension,
                height: smallMaxDimension / originalAspectRatio
            )
        } else {
            // Portrait orientation
            smallThumbnailDimensions = CGSize(
                width: smallMaxDimension * originalAspectRatio,
                height: smallMaxDimension
            )
        }

        // Calculate large thumbnail dimensions while preserving aspect ratio
        let largeMaxDimension = largeSize?.width ?? ThumbnailSize.large.dimensions.width
        let largeThumbnailDimensions: CGSize
        if originalSize.width > originalSize.height {
            // Landscape orientation
            largeThumbnailDimensions = CGSize(
                width: largeMaxDimension,
                height: largeMaxDimension / originalAspectRatio
            )
        } else {
            // Portrait orientation
            largeThumbnailDimensions = CGSize(
                width: largeMaxDimension * originalAspectRatio,
                height: largeMaxDimension
            )
        }

        let smallThumbnail = self.resize(originalImage, to: smallThumbnailDimensions)
        try self.saveThumbnail(smallThumbnail, to: smallThumbnailPath, isPdf: isPdf)

        let largeThumbnail = self.resize(originalImage, to: largeThumbnailDimensions)
        try self.saveThumbnail(largeThumbnail, to: largeThumbnailPath, isPdf: isPdf)

        return (small: smallThumbnailPath, large: largeThumbnailPath)
    }

    private func resize(_ image: PlatformImage, to size: CGSize) -> PlatformImage {
        Log.interface.notice("Resizing image to: \(size.width, privacy: .public)x\(size.height, privacy: .public)")
        #if os(iOS) || os(visionOS)
        let renderer = UIGraphicsImageRenderer(size: size)
        return renderer.image { _ in
            image.draw(in: CGRect(origin: .zero, size: size))
        }
        #elseif os(macOS)
        let newImage = NSImage(size: size)
        newImage.lockFocus()

        let sourceRect = NSRect(x: 0, y: 0, width: image.size.width, height: image.size.height)
        let destRect = NSRect(x: 0, y: 0, width: size.width, height: size.height)

        image.draw(in: destRect, from: sourceRect, operation: .copy, fraction: 1.0)

        newImage.unlockFocus()
        return newImage
        #elseif os(watchOS)
        return image
        #endif
    }

    private func saveEmptyThumbnail(to path: String) throws {
        Log.interface.notice("Saving empty thumbnail at path: \(path, privacy: .public)")
        try Data().write(to: URL(fileURLWithPath: path))
    }

    #if canImport(PDFKit)
    private func createImageFromPDF(url: URL) -> PlatformImage? {
        guard let document = PDFDocument(url: url), let page = document.page(at: 0) else {
            return nil
        }

        let pdfSize = page.bounds(for: .mediaBox).size

        return page.thumbnail(of: pdfSize, for: .mediaBox)
    }
    #else
    private func createImageFromPDF(url: URL) -> PlatformImage? {
        return nil
    }
    #endif

    private func saveThumbnail(_ image: PlatformImage, to path: String, isPdf: Bool = false) throws {
        Log.interface.notice("Saving thumbnail to path: \(path, privacy: .public)")
        var data: Data?

        #if os(iOS) || os(visionOS) || os(watchOS)
        data = image.pngData()
        #elseif os(macOS)
        guard let tiffRepresentation = image.tiffRepresentation,
              let bitmapImage = NSBitmapImageRep(data: tiffRepresentation),
              let pngData = bitmapImage.representation(using: .png, properties: [:]) else {
            throw NSError(domain: "ThumbnailGeneratorError", code: 2, userInfo: [NSLocalizedDescriptionKey: "Failed to create PNG data"])
        }
        data = pngData
        #endif

        guard let finalData = data else {
            throw NSError(domain: "ThumbnailGeneratorError", code: 2, userInfo: [NSLocalizedDescriptionKey: "Failed to create image data"])
        }

        try finalData.write(to: URL(fileURLWithPath: path))
    }
}

// MARK: - Image Phase
public enum ImagePhase {
    case empty
    case loading
    case success(Image)
    case failure(any Error)
}

enum ThumbnailError: Error {
    case failedToLoad
}

// MARK: - Thumbnail Cache
@MainActor
final class ThumbnailCache {
    static let shared = ThumbnailCache()

    private let cache = NSCache<NSString, CacheEntry>()
    private let imageFails = NSCache<NSString, CacheFail>()
    private let fileManager = FileManager.default
    private let maxMemoryUsage: Int = 100 * 1024 * 1024 // 100 MB
    private var currentMemoryUsage: Int = 0
    private var lastAccessTimes: [URL: Date] = [:]

    private init() {
        cache.totalCostLimit = maxMemoryUsage
    }

    func getImage(for path: URL) throws -> (PlatformImage, ThumbnailSize)? {
        guard let cacheEntry = cache.object(forKey: path.absoluteString as NSString) else {
            if let lastFailed = imageFails.object(forKey: path.absoluteString as NSString)?.lastFailed, abs(lastFailed.timeIntervalSinceNow) < 30 {
                throw ThumbnailError.failedToLoad
            }
            return nil
        }
        // Update last access time
        lastAccessTimes[path] = Date()
        return (cacheEntry.image, cacheEntry.thumbnailScale)
    }

    func setFailure(for path: URL) {
        self.imageFails.setObject(CacheFail(lastFailed: .now), forKey: path.absoluteString as NSString)
    }

    func setImage(_ image: PlatformImage, for path: URL, withSize size: ThumbnailSize) {
        let key = path.absoluteString as NSString
        let estimatedSize = estimateImageMemorySize(image)
        let entry = CacheEntry(image: image, size: estimatedSize, scale: size)

        // Update last access time
        lastAccessTimes[path] = Date()

        // Add to cache with cost
        if let obj = cache.object(forKey: key), obj.thumbnailScale == .large && entry.thumbnailScale == .small {
            return
        }
        cache.setObject(entry, forKey: key, cost: estimatedSize)

        // Update current memory usage
        currentMemoryUsage += estimatedSize

        // Evict if needed
        evictIfNeeded()
    }

    private func evictIfNeeded() {
        if currentMemoryUsage <= maxMemoryUsage { return }

        // Sort by last access time (LRU eviction policy)
        let sortedPaths = lastAccessTimes.sorted { $0.value < $1.value }

        for (path, _) in sortedPaths {
            if currentMemoryUsage <= maxMemoryUsage * 8 / 10 { break }

            if let cacheEntry = cache.object(forKey: path.absoluteString as NSString) {
                cache.removeObject(forKey: path.absoluteString as NSString)
                currentMemoryUsage -= cacheEntry.size
                lastAccessTimes.removeValue(forKey: path)
            }
        }
    }

    private func estimateImageMemorySize(_ image: PlatformImage) -> Int {
        #if os(iOS) || os(visionOS) || os(watchOS)
        guard let cgImage = image.cgImage else { return 1024 * 1024 } // Default to 1MB if unknown
        return cgImage.height * cgImage.bytesPerRow
        #elseif os(macOS)
        guard let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else { return 1024 * 1024 }
        return cgImage.height * cgImage.bytesPerRow
        #endif
    }

    func clear() {
        cache.removeAllObjects()
        lastAccessTimes.removeAll()
        currentMemoryUsage = 0
    }

    class CacheEntry {
        let image: PlatformImage
        let size: Int
        let thumbnailScale: ThumbnailSize

        init(image: PlatformImage, size: Int, scale: ThumbnailSize) {
            self.image = image
            self.size = size
            self.thumbnailScale = scale
        }
    }

    class CacheFail {
        let lastFailed: Date

        init(lastFailed: Date) {
            self.lastFailed = lastFailed
        }
    }
}

// MARK: - Image Loader
enum ImageLoadingPhase {
    case empty
    case loading
    case success(PlatformImage)
    case failure(any Error)

    var isSuccess: Bool {
        if case .success = self {
            return true
        } else {
            return false
        }
    }

    func getImage() -> PlatformImage? {
        if case let .success(image) = self {
            return image
        } else {
            return nil
        }
    }
}

@MainActor
@Observable class ImageLoader {
    var phase: ImageLoadingPhase = .empty

    private let path: URL
    private let cache = ThumbnailCache.shared
    private let thumbnailGenerator = ThumbnailGenerator.shared

    init(path: URL) {
        self.path = path
    }

    func prefetch() {
        if let (cachedImage, _) = try? cache.getImage(for: path) {
            phase = .success(cachedImage)
        }
    }

    func load(maxSize: CGFloat) async {
        do {
            if let (cachedImage, cachedSize) = try cache.getImage(for: path) {
                if maxSize < 150 {
                    phase = .success(cachedImage)
                    return
                } else {
                    if cachedSize == .large {
                        phase = .success(cachedImage)
                        return
                    } else {
                        phase = .success(cachedImage)
                    }
                }
            } else {
                Log.interface.notice("Cache miss for path: \(self.path, privacy: .public)")
            }
        } catch {
            Log.data.notice("Error reading from cache for \(self.path, privacy: .public): \(error, privacy: .public)")
            phase = .failure(ThumbnailError.failedToLoad)
            return
        }

        if maxSize < 150 {
            Log.interface.notice("Loading small thumbnail for \(self.path, privacy: .public) (maxSize <= 150)")
            phase = .loading

            if let smallThumbnail = await thumbnailGenerator.loadThumbnail(for: path, size: .small) {
                cache.setImage(smallThumbnail, for: path, withSize: .small)
                phase = .success(smallThumbnail)
                Log.interface.notice("Phase changed to: success (loaded small thumbnail)")
            } else {
                Log.interface.notice("Small thumbnail not found, attempting generation for \(self.path, privacy: .public)...")
                do {
                    try await thumbnailGenerator.createThumbnails(for: path)
                    if let generatedSmallThumbnail = await thumbnailGenerator.loadThumbnail(for: path, size: .small) {
                        cache.setImage(generatedSmallThumbnail, for: path, withSize: .small)
                        phase = .success(generatedSmallThumbnail)
                        Log.interface.notice("Phase changed to: success (generated and loaded small thumbnail)")
                    } else {
                        phase = .failure(ThumbnailError.failedToLoad)
                        Log.interface.notice("Phase changed to: failure (could not load small thumbnail after generation)")
                    }
                } catch {
                    Log.data.notice("Error creating thumbnails for \(self.path, privacy: .public): \(error, privacy: .public)")
                    cache.setFailure(for: path)
                    phase = .failure(ThumbnailError.failedToLoad)
                    Log.interface.notice("Phase changed to: failure (error during thumbnail generation)")
                }
            }
        } else {
            let needsToLoadSmall = !phase.isSuccess

            if needsToLoadSmall {
                 phase = .loading
                 Log.interface.notice("Phase changed to: loading (preparing to load for maxSize > 150)")
            }

            var smallImageLoaded: PlatformImage? = phase.getImage()
            var largeImageLoaded: PlatformImage?

            if !phase.isSuccess {
                 if let existingSmall = await thumbnailGenerator.loadThumbnail(for: path, size: .small) {
                    smallImageLoaded = existingSmall
                    cache.setImage(existingSmall, for: path, withSize: .small)
                    phase = .success(existingSmall)
                    Log.interface.notice("Phase changed to: success (loaded existing small thumbnail for maxSize > 150)")
                }
            }

            if let existingLarge = await thumbnailGenerator.loadThumbnail(for: path, size: .large) {
                largeImageLoaded = existingLarge
                cache.setImage(existingLarge, for: path, withSize: .large)
                phase = .success(existingLarge)
                Log.interface.notice("Phase changed to: success (loaded existing large thumbnail)")
                return
            }

            if smallImageLoaded == nil || largeImageLoaded == nil {
                Log.interface.notice("Thumbnails not fully available, attempting generation for \(self.path, privacy: .public)...")
                if smallImageLoaded == nil {
                    phase = .loading
                    Log.interface.notice("Phase changed to: loading (before generation)")
                }

                do {
                    try await thumbnailGenerator.createThumbnails(for: path)
                    Log.interface.notice("Thumbnail generation completed for \(self.path, privacy: .public).")

                    if smallImageLoaded == nil {
                        if let generatedSmall = await thumbnailGenerator.loadThumbnail(for: path, size: .small) {
                            smallImageLoaded = generatedSmall
                            cache.setImage(generatedSmall, for: path, withSize: .small)
                            if largeImageLoaded == nil {
                                phase = .success(generatedSmall)
                                Log.interface.notice("Phase changed to: success (generated and loaded small)")
                            }
                        } else {
                            Log.data.notice("Failed to load small thumbnail for \(self.path, privacy: .public) after generation.")
                        }
                    }

                    if let generatedLarge = await thumbnailGenerator.loadThumbnail(for: path, size: .large) {
                        largeImageLoaded = generatedLarge
                        cache.setImage(generatedLarge, for: path, withSize: .large)
                        phase = .success(generatedLarge)
                        Log.interface.notice("Phase changed to: success (generated and loaded large)")
                    } else {
                        if smallImageLoaded == nil {
                            phase = .failure(ThumbnailError.failedToLoad)
                            Log.interface.notice("Phase changed to: failure (failed to load large and small after generation)")
                        } else {
                            Log.interface.notice("Successfully loaded small, but large failed to load after generation.")
                        }
                    }
                } catch {
                    Log.data.notice("Error creating thumbnails for \(self.path, privacy: .public): \(error, privacy: .public)")
                    cache.setFailure(for: path)
                    if smallImageLoaded == nil {
                        phase = .failure(ThumbnailError.failedToLoad)
                        Log.interface.notice("Phase changed to: failure (error during thumbnail generation process)")
                    } else {
                        Log.interface.notice("Error during thumbnail generation, but a small image was already loaded/displayed.")
                    }
                }
            }
        }
    }
}

@MainActor
func loadThumbnailForUrl(_ path: URL, maxSize: CGFloat = 400) async throws -> Image {
    let cache = ThumbnailCache.shared
    let thumbnailGenerator = ThumbnailGenerator.shared

    do {
        if let (cachedImage, cachedSize) = try cache.getImage(for: path) {
            Log.interface.notice("Cache hit for path: \(path, privacy: .public) with size: \(cachedSize)")
            if maxSize <= 150 {
                Log.interface.notice("Returning cached image (any size ok for maxSize <= 150)")
                return Image(platformImage: cachedImage)
            } else {
                if cachedSize == .large {
                    Log.interface.notice("Returning cached large image")
                    return Image(platformImage: cachedImage)
                } else {
                    Log.interface.notice("Cached small image found, but large is preferred for maxSize > 150. Will attempt to load large.")
                }
            }
        } else {
            Log.interface.notice("Cache miss for path: \(path, privacy: .public)")
        }
    } catch {
        Log.data.notice("Error reading from cache for \(path, privacy: .public): \(error, privacy: .public). Proceeding to load/generate.")
    }

    if maxSize <= 150 {
        Log.interface.notice("Handling image for maxSize <= 150 for path: \(path, privacy: .public)")
        if let smallThumbnail = await thumbnailGenerator.loadThumbnail(for: path, size: .small) {
            Log.interface.notice("Loaded existing small thumbnail.")
            cache.setImage(smallThumbnail, for: path, withSize: .small)
            return Image(platformImage: smallThumbnail)
        }

        Log.interface.notice("Small thumbnail not found directly, attempting generation...")
        do {
            try await thumbnailGenerator.createThumbnails(for: path)
            if let generatedSmallThumbnail = await thumbnailGenerator.loadThumbnail(for: path, size: .small) {
                Log.interface.notice("Generated and loaded small thumbnail.")
                cache.setImage(generatedSmallThumbnail, for: path, withSize: .small)
                return Image(platformImage: generatedSmallThumbnail)
            } else {
                Log.data.notice("Failed to load small thumbnail after generation.")
                throw ThumbnailError.failedToLoad
            }
        } catch {
            Log.data.notice("Error creating thumbnails: \(error, privacy: .public)")
            cache.setFailure(for: path)
            throw ThumbnailError.failedToLoad
        }
    } else {
        Log.interface.notice("Handling image for maxSize > 150 for path: \(path, privacy: .public)")
        var smallImageCandidate: PlatformImage?

        if let (cachedImage, cachedSize) = try? cache.getImage(for: path), cachedSize == .small {
            smallImageCandidate = cachedImage
            Log.interface.notice("Noted small image from cache as a fallback candidate.")
        }

        if let largeThumbnail = await thumbnailGenerator.loadThumbnail(for: path, size: .large) {
            Log.interface.notice("Loaded existing large thumbnail.")
            cache.setImage(largeThumbnail, for: path, withSize: .large)
            return Image(platformImage: largeThumbnail)
        }

        if smallImageCandidate == nil {
            if let smallThumbnail = await thumbnailGenerator.loadThumbnail(for: path, size: .small) {
                Log.interface.notice("Loaded existing small thumbnail (as large was not found).")
                cache.setImage(smallThumbnail, for: path, withSize: .small)
                smallImageCandidate = smallThumbnail
            }
        }

        Log.interface.notice("Large thumbnail not found directly, attempting generation...")
        do {
            try await thumbnailGenerator.createThumbnails(for: path)
            Log.interface.notice("Thumbnail generation attempt complete.")

            if let generatedLargeThumbnail = await thumbnailGenerator.loadThumbnail(for: path, size: .large) {
                Log.interface.notice("Generated and loaded large thumbnail.")
                cache.setImage(generatedLargeThumbnail, for: path, withSize: .large)
                if let generatedSmall = await thumbnailGenerator.loadThumbnail(for: path, size: .small) {
                     cache.setImage(generatedSmall, for: path, withSize: .small)
                }
                return Image(platformImage: generatedLargeThumbnail)
            } else {
                Log.data.notice("Failed to load large thumbnail after generation.")
                if smallImageCandidate == nil {
                     if let generatedSmallThumbnail = await thumbnailGenerator.loadThumbnail(for: path, size: .small) {
                        Log.interface.notice("Loaded small thumbnail after large generation failed.")
                        cache.setImage(generatedSmallThumbnail, for: path, withSize: .small)
                        return Image(platformImage: generatedSmallThumbnail)
                    }
                } else if let smallFallback = smallImageCandidate {
                    Log.interface.notice("Returning pre-existing/cached small thumbnail as large generation/load failed.")
                    return Image(platformImage: smallFallback)
                }
                throw ThumbnailError.failedToLoad
            }
        } catch {
            Log.data.notice("Error creating thumbnails: \(error, privacy: .public)")
            cache.setFailure(for: path)
            if let smallFallback = smallImageCandidate {
                Log.interface.notice("Thumbnail creation failed, returning previously available small image.")
                return Image(platformImage: smallFallback)
            }
            throw ThumbnailError.failedToLoad
        }
    }
}

// MARK: - CachedAsyncImage View
public struct CachedAsyncImage<Content: View>: View {
    @State private var loader: ImageLoader
    private let content: (ImagePhase) -> Content
    private let maxSize: CGFloat

    public init(path: URL, maxSize: CGFloat, @ViewBuilder content: @escaping (ImagePhase) -> Content) {
        self.loader = ImageLoader(path: path)
        self.content = content
        self.maxSize = maxSize
        loader.prefetch()
    }

    public var body: some View {
        content(convertPhase(loader.phase))
            .task {
                await loader.load(maxSize: maxSize)
            }
    }

    private func convertPhase(_ phase: ImageLoadingPhase) -> ImagePhase {
        switch phase {
        case .empty:
            return .empty
        case .loading:
            return .loading
        case .success(let image):
            return .success(Image(platformImage: image))
        case .failure(let error):
            return .failure(error)
        }
    }
}
