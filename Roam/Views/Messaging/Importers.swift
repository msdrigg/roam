import UniformTypeIdentifiers
import PhotosUI
import SwiftUI

struct DiagnosticsImport: PendingAttachment {
    nonisolated let utType: UTType = .json
    nonisolated let id: String

    nonisolated let userInitiated: Bool

    nonisolated var filename: String {
        "Diagnostics.json"
    }

    nonisolated init(userInitiated: Bool = false) {
        id = "diagnostics-\(UUID().uuidString)"
        self.userInitiated = userInitiated
    }

    nonisolated func load() async -> Result<AttachmentUpload, AttachmentError> {
        let loggingAt = Date.now
        Log.userInteraction.notice("Starting to send logs \(loggingAt, privacy: .public)")
        let logs = await getDebugInfo(userInitiated: userInitiated)
        Log.userInteraction.notice("Sending logs \(logs.installationInfo.userId, privacy: .public)")

        if let data = trimmedDebugInfoIfNeeded(logs) {
            let hash = fastHashData(data: data)
            do {
                try storeAttachmentToDisk(attachmentData: data, hash: hash, filename: self.filename)
            } catch let error as DataHandlerError {
                if case DataHandlerError.noSpaceOnDisk = error {
                    return .failure(.noSpaceOnDisk)
                } else {
                    return .failure(.loadingFailed)
                }
            } catch {
                return .failure(.loadingFailed)
            }
            return .success(AttachmentUpload(
                filename: self.filename,
                dataHash: hash,
                dataSize: Int64(data.count),
                contentType: "application/json",
                id: self.id, pairedMessages: Self.getDebugLogMessages(logs)
            ))
        } else {
            return .failure(.failedToEncode)
        }
    }

    /// A human summary to post alongside the diagnostics file, split across as
    /// many Discord messages as it takes to say all of it.
    ///
    /// The backend posts each element of `pairedMessages` as its own Discord
    /// message before it uploads the attachment, so each one is bound by
    /// Discord's 4000 character body limit - but the *summary* is not, because
    /// there can be several. This used to be a single unbounded string:
    /// fifteen lines per device and five per interface, which a user with a
    /// handful of devices sails straight past. Discord then rejects the whole
    /// send with `50035 BASE_TYPE_MAX_LENGTH`, the attachment never uploads,
    /// and the message sits in the outbox retrying a megabyte forever because
    /// nothing about it will ever change.
    ///
    /// Entries are packed greedily and never split down the middle: a device or
    /// interface block that will not fit in the message being built starts the
    /// next one instead. Packing rather than emitting one message per device
    /// keeps a thread readable for someone with a dozen devices while still
    /// dropping nothing, and a device big enough to need a message to itself
    /// gets one.
    nonisolated static func getDebugLogMessages(_ debugInfo: DebugInfo) -> [String] {
        var entries: [String] = []

        // No `:ninja:` here - `packIntoDiscordMessages` puts one on every
        // message it produces, including this one.
        var installation: String = "\n"
        installation += "### Installation Info\n\n"
        installation += "- **User ID**: \(debugInfo.installationInfo.userId)\n"
        installation += "- **Build Version**: \(debugInfo.installationInfo.buildVersion ?? "--")\n"
        installation += "- **OS Platform**: \(debugInfo.installationInfo.osPlatform ?? "--")\n"
        installation += "- **OS Version**: \(debugInfo.installationInfo.osVersion ?? "--")\n"
        installation += "- **Locale**: \(debugInfo.installationInfo.userLocale ?? "--")\n"
        installation += "- **Device Language**: \(debugInfo.language.deviceLanguageCode)\n"
        installation += "- **Translated Language**: \(debugInfo.language.translatedLanguageCode)\n"
        entries.append(installation)

        entries.append("\n### Devices\n")

        if debugInfo.devices.isEmpty {
            entries.append("- No devices found.\n")
        }
        for device in debugInfo.devices {
            var message = ""
            message += "- \(device.device.name)\n"
            message += "   - **Location**: \(device.device.location)\n"
            message += "   - **UDN**: \(device.device.udn)\n"
            message += "   - **ID**: \(device.device.id)\n"
            message += "   - **Hidden At**: \(device.device.hiddenAt?.ISO8601Format() ?? "--")\n"
            message += "   - **Ethernet MAC**: \(device.device.ethernetMAC ?? "--")\n"
            message += "   - **Wifi MAC**: \(device.device.wifiMAC ?? "--")\n"
            message += "   - **Network Type**: \(device.device.networkType ?? "--")\n"
            message += "   - **RTCP Port**: \(String(describing: device.device.rtcpPort))\n"
            message += "   - **Supports Datagram**: \(String(describing: device.device.supportsDatagram))\n"
            message += "   - **Connectable Now**: \(device.successResponse != nil)\n"
            message += "   - **Device Info Query**: \(device.successResponse.map { "HTTP \($0.statusCode)" } ?? device.errorResponse ?? "--")\n"
            message += "   - **Apps Query**: \(device.appsResponse.map { "HTTP \($0.statusCode)" } ?? device.appsErrorResponse ?? "--")\n"
            message += "   - **Last Online**: \(device.device.lastOnlineAt?.ISO8601Format() ?? "--")\n"
            message += "   - **Last Scanned**: \(device.device.lastScannedAt?.ISO8601Format() ?? "--")\n"
            message += "   - **Last Selected**: \(device.device.lastSelectedAt?.ISO8601Format() ?? "--")\n"
            message += "   - **Last Sent to Watch**: \(device.device.lastSentToWatch?.ISO8601Format() ?? "--")\n"
            entries.append(message)
        }

        entries.append("\n### Interfaces\n")

        if debugInfo.interfaces.isEmpty {
            entries.append("- No interfaces found.\n")
        }
        for interface in debugInfo.interfaces {
            var message = ""
            message += "- \(interface.name)\n"
            message += "   - **Self Address**: \(interface.address.addressString)\n"
            message += "   - **Netmask**: \(interface.netmask.addressString)\n"
            message += "   - **Flags**: \(interface.getFlagList().joined(separator: ", "))\n"
            message += "   - **Start Scannable**: \(interface.scannableIPV4NetworkRange.first?.addressString ?? "--")\n"
            message += "   - **End Scannable**: \(interface.scannableIPV4NetworkRange.last?.addressString ?? "--")\n"
            entries.append(message)
        }

        return packIntoDiscordMessages(entries, label: "diagnostics summary")
    }
}

/// Packs whole entries into as few Discord-sized messages as possible.
///
/// An entry is never split across two messages: one that will not fit starts a
/// new message instead, so a device's fields always arrive together and in
/// order. `clampToDiscordLimit` is the backstop for the one case packing cannot
/// solve - a single entry longer than the limit all by itself, which only a
/// pathologically long field can produce.
///
/// Every message gets the `:ninja:` marker, not just the first. The backend
/// posts each one as its own Discord message and the app hides a message by
/// looking for that prefix, so a summary that packed into more than one message
/// used to put every message after the first into the user's own chat. The
/// marker is charged against the budget here so prefixing cannot push a message
/// back over the limit that packing just kept it under.
public nonisolated func packIntoDiscordMessages(_ entries: [String], label: String) -> [String] {
    let marker = ":ninja:\n"
    let budget = discordMessageContentLimit - marker.count
    var messages: [String] = []
    var current = ""

    for entry in entries {
        if current.isEmpty {
            current = entry
        } else if current.count + entry.count <= budget {
            current += entry
        } else {
            messages.append(current)
            current = entry
        }
    }
    if !current.isEmpty {
        messages.append(current)
    }

    return messages.map { marker + clampToDiscordLimit($0, label: label, limit: budget) }
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
                let hash = fastHashData(data: pngData)
                do {
                    try storeAttachmentToDisk(attachmentData: pngData, hash: hash, filename: filename)
                } catch {
                    return .failure(.loadingFailed)
                }
                return .success(AttachmentUpload(
                    filename: filename,
                    dataHash: hash,
                    dataSize: Int64(pngData.count),
                    contentType: "image/png",
                    id: self.id
                ))
            }
#else
            if let image = UIImage(data: data), let pngData = await image.compressedPNGData() {
                let hash = fastHashData(data: pngData)
                do {
                    try storeAttachmentToDisk(attachmentData: pngData, hash: hash, filename: filename)
                } catch {
                    return .failure(.loadingFailed)
                }
                return .success(AttachmentUpload(
                    filename: filename,
                    dataHash: hash,
                    dataSize: Int64(pngData.count),
                    contentType: "image/png",
                    id: self.id
                ))
            }
#endif

            let hash = fastHashData(data: data)
            do {
                try storeAttachmentToDisk(attachmentData: data, hash: hash, filename: filename)
            } catch {
                return .failure(.loadingFailed)
            }
            return .success(AttachmentUpload(
                filename: filename,
                dataHash: hash,
                dataSize: Int64(data.count),
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

                let hash = fastHashData(data: data)
                do {
                    try storeAttachmentToDisk(attachmentData: data, hash: hash, filename: filename)
                } catch {
                    continuation.resume(returning: Result.failure(AttachmentError.loadingFailed))
                    return
                }

                continuation.resume(returning: .success(
                    AttachmentUpload(
                        filename: filename,
                        dataHash: hash,
                        dataSize: Int64(data.count),
                        contentType: utType.preferredMIMEType ?? "application/octet-stream",
                        id: self.id
                    )
                ))
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

            let hash = fastHashData(data: data)
            do {
                try storeAttachmentToDisk(attachmentData: data, hash: hash, filename: filename)
            } catch {
                return Result.failure(AttachmentError.loadingFailed)
            }

            return .success(AttachmentUpload(
                filename: filename,
                dataHash: hash,
                dataSize: Int64(data.count),
                contentType: utType.preferredMIMEType ?? "application/octet-stream",
                id: self.id
            ))
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
