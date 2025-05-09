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

// MARK: - Image Phase
public enum ImagePhase {
    case empty
    case loading
    case success(Image)
    case failure(any Error)
}

// MARK: - Thumbnail Cache
@MainActor
final class ThumbnailCache {
    static let shared = ThumbnailCache()

    private let cache = NSCache<NSString, CacheEntry>()
    private let fileManager = FileManager.default
    private let maxMemoryUsage: Int = 100 * 1024 * 1024 // 100 MB
    private var currentMemoryUsage: Int = 0
    private var lastAccessTimes: [URL: Date] = [:]

    private init() {
        cache.totalCostLimit = maxMemoryUsage
    }

    func getImage(for path: URL) -> PlatformImage? {
        guard let cacheEntry = cache.object(forKey: path.absoluteString as NSString) else { return nil }
        // Update last access time
        lastAccessTimes[path] = Date()
        return cacheEntry.image
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
}

// MARK: - Thumbnail Generator
enum ThumbnailSize {
    case small
    case large

    var dimensions: (width: CGFloat, height: CGFloat) {
        switch self {
        case .small:
            return (150, 150)
        case .large:
            return (300, 300)
        }
    }

    var suffix: String {
        switch self {
        case .small: return "thumbnail.small"
        case .large: return "thumbnail.large"
        }
    }
}

final class ThumbnailGenerator: Sendable {
    static let shared = ThumbnailGenerator()

    private let thumbnailQueue = DispatchQueue(label: "com.cachedAsyncImage.thumbnailQueue", qos: .userInitiated, attributes: .concurrent)

    private init() {}

    func thumbnailPath(for url: URL, size: ThumbnailSize) -> String {
        let directory = url.deletingLastPathComponent().path
        let filename = url.deletingPathExtension().lastPathComponent
        return "\(directory)/\(filename).\(size.suffix)"
    }

    func thumbnailExists(for path: URL, size: ThumbnailSize) -> Bool {
        let thumbnailPath = self.thumbnailPath(for: path, size: size)
        return FileManager.default.fileExists(atPath: thumbnailPath)
    }

    func loadThumbnail(for path: URL, size: ThumbnailSize) -> PlatformImage? {
        let thumbnailPath = self.thumbnailPath(for: path, size: size)
        if FileManager.default.fileExists(atPath: thumbnailPath) {
            #if os(iOS) || os(visionOS) || os(watchOS)
            return UIImage(contentsOfFile: thumbnailPath)
            #elseif os(macOS)
            return NSImage(contentsOfFile: thumbnailPath)
            #endif
        }
        return nil
    }

    @discardableResult
    func createThumbnails(for url: URL, smallSize: CGSize? = nil, largeSize: CGSize? = nil) async throws -> (small: String, large: String) {
        Log.data.notice("Creating thumbnails for \(url, privacy: .public)")
        return try await withCheckedThrowingContinuation { continuation in
            thumbnailQueue.async {
                do {
                    let smallThumbnailPath = self.thumbnailPath(for: url, size: .small)
                    let largeThumbnailPath = self.thumbnailPath(for: url, size: .large)
                    // Get the original image
                    #if os(iOS) || os(visionOS) || os(watchOS)
                    guard let data = try? Data(contentsOf: url), let originalImage = UIImage(data: data) else {
                        try? self.saveEmptyThumbnail(to: smallThumbnailPath)
                        try? self.saveEmptyThumbnail(to: largeThumbnailPath)
                        throw NSError(domain: "ThumbnailGeneratorError", code: 1, userInfo: [NSLocalizedDescriptionKey: "Failed to load image from path"])
                    }
                    #elseif os(macOS)
                    guard let originalImage = NSImage(contentsOf: url) else {
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
                    try self.saveThumbnail(smallThumbnail, to: smallThumbnailPath)

                    let largeThumbnail = self.resize(originalImage, to: largeThumbnailDimensions)
                    try self.saveThumbnail(largeThumbnail, to: largeThumbnailPath)

                    continuation.resume(returning: (small: smallThumbnailPath, large: largeThumbnailPath))
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
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
    private func saveThumbnail(_ image: PlatformImage, to path: String) throws {
        #if os(iOS) || os(visionOS) || os(watchOS)
        guard let data = image.jpegData(compressionQuality: 0.7) else {
            throw NSError(domain: "ThumbnailGeneratorError", code: 2, userInfo: [NSLocalizedDescriptionKey: "Failed to create JPEG data"])
        }
        #elseif os(macOS)
        guard let tiffRepresentation = image.tiffRepresentation,
              let bitmapImage = NSBitmapImageRep(data: tiffRepresentation),
              let data = bitmapImage.representation(using: .jpeg, properties: [.compressionFactor: 0.7]) else {
            throw NSError(domain: "ThumbnailGeneratorError", code: 2, userInfo: [NSLocalizedDescriptionKey: "Failed to create JPEG data"])
        }
        #endif

        try data.write(to: URL(fileURLWithPath: path))
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
    private var cancellables = Set<AnyCancellable>()

    init(path: URL) {
        self.path = path
    }

    func load() {
        // Check if image is in cache
        if let cachedImage = cache.getImage(for: path) {
            phase = .success(cachedImage)
            return
        }

        // Check if thumbnails exist
        if thumbnailGenerator.thumbnailExists(for: path, size: .small) {
            if let thumbnailImage = thumbnailGenerator.loadThumbnail(for: path, size: .small) {
                cache.setImage(thumbnailImage, for: path)
                phase = .success(thumbnailImage)
                return
            }
        } else if thumbnailGenerator.thumbnailExists(for: path, size: .large) {
            if let thumbnailImage = thumbnailGenerator.loadThumbnail(for: path, size: .large) {
                cache.setImage(thumbnailImage, for: path)
                phase = .success(thumbnailImage)
                return
            }
        }

        // Need to generate thumbnails
        phase = .loading

        Task {
            do {
                try await thumbnailGenerator.createThumbnails(for: path)

                if let thumbnailImage = thumbnailGenerator.loadThumbnail(for: path, size: .small) {
                    await MainActor.run {
                        cache.setImage(thumbnailImage, for: path)
                        phase = .success(thumbnailImage)
                    }
                } else {
                    Log.data.notice("Failed to load thumbnail")
                    await MainActor.run {
                        phase = .failure(NSError(domain: "ImageLoaderError", code: 3, userInfo: [NSLocalizedDescriptionKey: "Failed to load generated thumbnail"]))
                    }
                }
            } catch {
                Log.data.notice("Error creating thumbnails for \(self.path, privacy: .public): \(error, privacy: .public)")
                await MainActor.run {
                    phase = .failure(error)
                }
            }
        }
    }

    func cancel() {
        cancellables.removeAll()
    }
}

// MARK: - CachedAsyncImage View
public struct CachedAsyncImage<Content: View>: View {
    @StateObject private var loader: ImageLoader
    private let content: (ImagePhase) -> Content

    public init(path: URL, @ViewBuilder content: @escaping (ImagePhase) -> Content) {
        self._loader = StateObject(wrappedValue: ImageLoader(path: path))
        self.content = content
    }

    public var body: some View {
        content(convertPhase(loader.phase))
            .onAppear {
                loader.load()
            }
            .onDisappear {
                loader.cancel()
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

// MARK: - Convenience Initializers
extension CachedAsyncImage {
    public init<I: View, P: View>(
        path: URL,
        @ViewBuilder content: @escaping (Image) -> I,
        @ViewBuilder placeholder: @escaping () -> P
    ) where Content == _ConditionalContent<I, P> {
        self.init(path: path) { phase in
            switch phase {
            case .success(let image):
                content(image)
            case .empty, .loading, .failure:
                placeholder()
            }
        }
    }
}

// MARK: - Public Utility Function
public func createThumbnailsForImage(
    path: URL,
    smallSize: CGSize? = nil,
    largeSize: CGSize? = nil
) async throws -> (small: String, large: String) {
    try await ThumbnailGenerator.shared.createThumbnails(
        for: path,
        smallSize: smallSize,
        largeSize: largeSize
    )
}
