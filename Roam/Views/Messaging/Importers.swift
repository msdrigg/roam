import UniformTypeIdentifiers
import PhotosUI
import SwiftUI

struct DiagnosticsImport: PendingAttachment {
    let utType: UTType = .json
    let id: String

    var filename: String {
        "Diagnostics.json"
    }

    init() {
        id = "diagnostics-\(UUID().uuidString)"
    }

    func load() async -> Result<AttachmentUpload, AttachmentError> {
        let loggingAt = Date.now
        Log.userInteraction.notice("Starting to send logs \(loggingAt, privacy: .public)")
        let logs = await getDebugInfo(container: getSharedModelContainer())
        Log.userInteraction.notice("Sending logs \(logs.installationInfo.userId, privacy: .public)")

        if let data = trimmedDebugInfoIfNeeded(logs) {
            return .success(AttachmentUpload(filename: self.filename, data: data, contentType: "application/json", id: self.id, pairedMessages: [Self.getDebugLogMessageString(logs)]))
        } else {
            return .failure(.failedToEncode)
        }
    }

    private static func getDebugLogMessageString(_ debugInfo: DebugInfo) -> String {
        var message: String = ":ninja:\n\n"

        message += "### Installation Info\n\n"
        message += "- **User ID**: \(debugInfo.installationInfo.userId)\n"
        message += "- **Build Version**: \(debugInfo.installationInfo.buildVersion ?? "--")\n"
        message += "- **OS Platform**: \(debugInfo.installationInfo.osPlatform ?? "--")\n"
        message += "- **OS Version**: \(debugInfo.installationInfo.osVersion ?? "--")\n"
        message += "- **Locale**: \(debugInfo.installationInfo.userLocale ?? "--")\n"
        message += "- **Device Language**: \(debugInfo.language.deviceLanguageCode)\n"
        message += "- **Translated Language**: \(debugInfo.language.translatedLanguageCode)\n"

        message += "\n### Devices\n\n"

        for device in debugInfo.devices {
            message += "- \(device.device.name)\n"
            message += "   - **Location**: \(device.device.location)\n"
            message += "   - **UDN**: \(device.device.udn)\n"
            message += "   - **ID**: \(device.device.id)\n"
            message += "   - **Deleted At**: \(device.device.deletedAt?.ISO8601Format() ?? "--")\n"
            message += "   - **Hidden At**: \(device.device.hiddenAt?.ISO8601Format() ?? "--")\n"
            message += "   - **Ethernet MAC**: \(device.device.ethernetMAC ?? "--")\n"
            message += "   - **Wifi MAC**: \(device.device.wifiMAC ?? "--")\n"
            message += "   - **Network Type**: \(device.device.networkType ?? "--")\n"
            message += "   - **RTCP Port**: \(String(describing: device.device.rtcpPort))\n"
            message += "   - **Supports Datagram**: \(String(describing: device.device.supportsDatagram))\n"
            message += "   - **Connectable Now**: \(device.successResponse != nil)\n"
            message += "   - **Last Online**: \(device.device.lastOnlineAt?.ISO8601Format() ?? "--")\n"
            message += "   - **Last Scanned**: \(device.device.lastScannedAt?.ISO8601Format() ?? "--")\n"
            message += "   - **Last Selected**: \(device.device.lastSelectedAt?.ISO8601Format() ?? "--")\n"
            message += "   - **Last Sent to Watch**: \(device.device.lastSentToWatch?.ISO8601Format() ?? "--")\n"
        }

        if debugInfo.devices.isEmpty {
            message += "- No devices found.\n"
        }

        message += "\n### Interfaces\n\n"

        for interface in debugInfo.interfaces {
            message += "- \(interface.name)\n"
            message += "   - **Self Address**: \(interface.address.addressString)\n"
            message += "   - **Netmask**: \(interface.netmask.addressString)\n"
            message += "   - **Flags**: \(interface.getFlagList().joined(separator: ", "))\n"
            message += "   - **Start Scannable**: \(interface.scannableIPV4NetworkRange.first?.addressString ?? "--")\n"
            message += "   - **End Scannable**: \(interface.scannableIPV4NetworkRange.last?.addressString ?? "--")\n"
        }

        if debugInfo.interfaces.isEmpty {
            message += "- No interfacesfound.\n"
        }

        return message
    }
}

struct PhotoImport: PendingAttachment {
    let item: PhotosPickerItem
    let filename: String
    let utType: UTType
    let id: String

    init?(item: PhotosPickerItem) {
        self.item = item
        self.id = UUID().uuidString

        if let itemType = item.supportedContentTypes.first {
            self.utType = itemType
        } else {
            return nil
        }

        self.filename = "Photo.png"
    }

    func load() async -> Result<AttachmentUpload, AttachmentError> {
        do {
            let filename = rewriteName(.png, self.filename)

            guard let data = try await item.loadTransferable(type: Data.self) else {
                return .failure(.loadingFailed)
            }

#if os(macOS)
            if let image = NSImage(data: data), let pngData = await image.compressedPNGData() {
                return .success(AttachmentUpload(
                    filename: filename,
                    data: pngData,
                    contentType: "image/png",
                    id: self.id
                ))
            }
#else
            if let image = UIImage(data: data), let pngData = await image.compressedPNGData() {
                return .success(AttachmentUpload(
                    filename: filename,
                    data: pngData,
                    contentType: "image/png",
                    id: self.id
                ))
            }
#endif

            return .success(AttachmentUpload(
                filename: filename,
                data: data,
                contentType: utType.preferredMIMEType ?? "application/octet-stream",
                id: self.id
            ))

        } catch {
            return .failure(.loadingFailed)
        }
    }
}

#if !os(watchOS)
struct ItemProviderAttachment: PendingAttachment {
    let filename: String
    let utType: UTType
    let id: String
    let provider: ItemProvider

    init?(_ provider: ItemProvider, name: String) {
        guard let contentType = provider.registeredContentTypes.first else {
            Log.userInteraction.warning("Unsupported file type for \(provider, privacy: .public)")
            return nil
        }
        self.utType = contentType
        self.filename = rewriteName(contentType, provider.suggestedName ?? name)

        id = "ItemProvider-\(UUID().uuidString)"
        self.provider = provider
    }

    func load() async -> Result<AttachmentUpload, AttachmentError> {
        return await withCheckedContinuation { (continuation: CheckedContinuation<Result<AttachmentUpload, AttachmentError>, Never>) in
            Log.userInteraction.notice("Loading attachment for type \(utType, privacy: .public)")
            _ = provider.loadDataRepresentation(for: utType) { data, error in
                if let error {
                    Log.userInteraction.error("Error loading data for uttype (\(utType, privacy: .public)):  \(error, privacy: .public)")
                }
                guard let data else {
                    continuation.resume(returning: Result.failure(AttachmentError.loadingFailed))
                    return
                }

                continuation.resume(returning: .success(AttachmentUpload(filename: filename, data: data, contentType: utType.preferredMIMEType ?? "application/octet-stream", id: self.id)))
            }
        }
    }
}

struct FileImport: PendingAttachment {
    let url: URL
    let filename: String
    let utType: UTType
    let id: String

    init?(url: URL) {
        self.url = url
        self.id = url.absoluteString

        // Get file type (UTType)
        let type: UTType?

        guard url.startAccessingSecurityScopedResource() else {
            Log.userInteraction.notice("Failed to access security scoped resource at \(url, privacy: .public)")
            return nil
        }
        defer { url.stopAccessingSecurityScopedResource() }
        do {
            type = try url.resourceValues(forKeys: [.contentTypeKey]).contentType
        } catch {
            Log.userInteraction.notice("Error loading file from url\(url, privacy: .public) \(error, privacy: .public)")
            return nil
        }
        let utType = type ?? .data
        self.filename = rewriteName(utType, url.lastPathComponent)
        self.utType = utType
    }

    func load() async -> Result<AttachmentUpload, AttachmentError> {
        do {
            guard url.startAccessingSecurityScopedResource() else {
                return .failure(.loadingFailed)
            }
            defer { url.stopAccessingSecurityScopedResource() }
            // Read file data asynchronously for local files
            // Handle remote URLs
            let (data, _) = try await URLSession.shared.data(from: url)

            let filename = url.lastPathComponent

            return .success(AttachmentUpload(filename: filename, data: data, contentType: utType.preferredMIMEType ?? "application/octet-stream", id: self.id))
        } catch {
            return .failure(.loadingFailed)
        }
    }
}
#endif

func rewriteName(_ utType: UTType, _ filename: String) -> String {
    if let preferredExtension = utType.preferredFilenameExtension {
        let baseName = (filename as NSString).deletingPathExtension
        return "\(baseName).\(preferredExtension)"
    } else {
        return filename
    }
}
