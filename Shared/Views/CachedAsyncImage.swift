import Foundation
import SwiftUI
import Combine

// MARK: - Platform Image Type
#if os(iOS) || os(visionOS) || os(watchOS)
import UIKit
typealias PlatformImage = UIImage
#elseif os(macOS)
import AppKit
typealias PlatformImage = NSImage
#endif

#if canImport(PDFKit)
import PDFKit
#endif

let globalMaxThumbnailSize: CGFloat = 400

// MARK: - Thumbnail Generator
enum ThumbnailSize {
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
        return "\(directory)/\(filename).\(size.suffix).\(ext)"
    }

    func thumbnailExists(for path: URL, size: ThumbnailSize) -> Bool {
        let thumbnailPath = self.thumbnailPath(for: path, size: size)
        return FileManager.default.fileExists(atPath: thumbnailPath)
    }

    func loadThumbnail(for path: URL, size: ThumbnailSize) -> sending PlatformImage? {
        let thumbnailPath = self.thumbnailPath(for: path, size: size)
        if FileManager.default.fileExists(atPath: thumbnailPath) {
            #if os(iOS) || os(visionOS) || os(watchOS)
            return PlatformImage(contentsOfFile: thumbnailPath)
            #elseif os(macOS)
            return PlatformImage(contentsOfFile: thumbnailPath)
            // Precache bitmap data due to https://wadetregaskis.com/nsimage-is-dangerous/
            #endif
        }
        return nil
    }

    @discardableResult
    func createThumbnails(for url: URL, smallSize: CGSize? = nil, largeSize: CGSize? = nil) async throws -> (small: String, large: String) {
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

    func getImage(for path: URL) throws -> PlatformImage? {
        guard let cacheEntry = cache.object(forKey: path.absoluteString as NSString) else {
            if let lastFailed = imageFails.object(forKey: path.absoluteString as NSString)?.lastFailed, abs(lastFailed.timeIntervalSinceNow) < 30 {
                throw ThumbnailError.failedToLoad
            }
            return nil
        }
        // Update last access time
        lastAccessTimes[path] = Date()
        return cacheEntry.image
    }

    func setFailure(for path: URL) {
        self.imageFails.setObject(CacheFail(lastFailed: .now), forKey: path.absoluteString as NSString)
    }

    func setImage(_ image: PlatformImage, for path: URL) {
        let estimatedSize = estimateImageMemorySize(image)
        let entry = CacheEntry(image: image, size: estimatedSize)

        // Update last access time
        lastAccessTimes[path] = Date()

        // Add to cache with cost
        cache.setObject(entry, forKey: path.absoluteString as NSString, cost: estimatedSize)

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

        init(image: PlatformImage, size: Int) {
            self.image = image
            self.size = size
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
}

@MainActor
class ImageLoader: ObservableObject {
    @Published var phase: ImageLoadingPhase = .empty

    private let path: URL
    private let cache = ThumbnailCache.shared
    private let thumbnailGenerator = ThumbnailGenerator.shared

    init(path: URL) {
        self.path = path
    }

    func load(maxSize: CGFloat) async {
        // Check if image is in cache
        do {
            if let cachedImage = try cache.getImage(for: path) {
                phase = .success(cachedImage)
                return
            }
        } catch {
            phase = .failure(ThumbnailError.failedToLoad)
            return
        }

        var exists = false
        var needsSmall = false
        var needsBig = false

        // Check if thumbnails exist
        if let thumbnailImage = await thumbnailGenerator.loadThumbnail(for: path, size: .small) {
            cache.setImage(thumbnailImage, for: path)
            phase = .success(thumbnailImage)
            exists = true
        } else {
            needsSmall = true
        }
        if maxSize > 150 {
            if let thumbnailImage = await thumbnailGenerator.loadThumbnail(for: path, size: .large) {
                cache.setImage(thumbnailImage, for: path)
                phase = .success(thumbnailImage)
                exists = true
            } else {
                needsBig = true
            }
        }

        if !(needsBig || needsSmall) {
            return
        }

        if !exists {
            phase = .loading
        }

        do {
            try await thumbnailGenerator.createThumbnails(for: path)

            if let thumbnailImage = await thumbnailGenerator.loadThumbnail(for: path, size: .small) {
                cache.setImage(thumbnailImage, for: path)
                phase = .success(thumbnailImage)
            } else {
                Log.data.notice("Failed to load thumbnail")
                phase = .failure(NSError(domain: "ImageLoaderError", code: 3, userInfo: [NSLocalizedDescriptionKey: "Failed to load generated thumbnail"]))
            }
        } catch {
            Log.data.notice("Error creating thumbnails for \(self.path, privacy: .public): \(error, privacy: .public)")
            cache.setFailure(for: path)
            phase = .failure(error)
        }
    }
}

// MARK: - CachedAsyncImage View
public struct CachedAsyncImage<Content: View>: View {
    @StateObject private var loader: ImageLoader
    private let content: (ImagePhase) -> Content
    private let maxSize: CGFloat

    public init(path: URL, maxSize: CGFloat, @ViewBuilder content: @escaping (ImagePhase) -> Content) {
        self._loader = StateObject(wrappedValue: ImageLoader(path: path))
        self.content = content
        self.maxSize = maxSize
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
            #if os(iOS) || os(visionOS) || os(watchOS)
            return .success(Image(uiImage: image))
            #elseif os(macOS)
            return .success(Image(nsImage: image))
            #endif
        case .failure(let error):
            return .failure(error)
        }
    }
}
