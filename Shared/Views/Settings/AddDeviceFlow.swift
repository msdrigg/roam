import SwiftUI
#if !os(macOS)
import UIKit
#endif

struct AddDeviceFlow: View {
    @Environment(\.dismiss) private var dismiss
    @State private var ipAddress: String = ""
    @State private var globalError: String?
    @State private var ipAddressError: String?
    private let isConnecting: AsyncLock = AsyncLock()
    @State private var connectionStatus: ConnectionStatus = .idle
    @State private var selfIpGuess: String = "192.168.1.1"
    @State private var connectTask: Task<Void, Never>?
    @FocusState private var isIpAddressFocused: Bool

    enum ConnectionStatus {
        case idle
        case connecting
        case success
        case permissionFailed
        case failure(AddDeviceError)

        var isSuccess: Bool {
            switch self {
            case .success: return true
            default: return false
            }
        }
        var isIdle: Bool {
            switch self {
            case .idle: return true
            default: return false
            }
        }
        var isInvalidIp: Bool {
            switch self {
            case .failure(let error):
                if case .invalidIPAddress = error {
                    return true
                } else {
                    return false
                }
            default: return false
            }
        }
    }

    var deviceTypeName: String {
        #if os(macOS)
        String(localized: "Mac")
        #elseif os(visionOS)
        String(localized: "Vision Pro")
        #elseif os(watchOS)
        String(localized: "Apple Watch")
        #else
        if UIDevice.current.userInterfaceIdiom == .pad {
            String(localized: "iPad")
        } else {
            String(localized: "iPhone")
        }
        #endif
    }
    var ipHint: String {
        selfIpGuess.split(separator: ".").dropLast(1).joined(separator: ".") + ".*"
    }
    var runningInLocalDevMode: Bool {
        #if DEBUG
        true
        #else
        false
        #endif
    }

    var body: some View {
        if runningInPreview {
            bodyContent
                .preferredColorScheme(.dark)
                .preferredColorScheme(.dark)
        } else {
            bodyContent
                .preferredColorScheme(.dark)
                .preferredColorScheme(.dark)
                .task {
                    let localInterfaces = await allAddressedInterfaces()
                    selfIpGuess = localInterfaces.filter({ localInterface in
                        localInterface.isNormal
                    }).first?.address.addressString ?? "192.168.1.1"
                }
        }
    }

    @ViewBuilder
    var bodyContent: some View {
        VStack(spacing: 0) {
            #if !os(watchOS)
            HStack(spacing: 0) {
                ZStack {
                    Circle()
                        .fill(Color.secondary.opacity(0.4))
                        .frame(width: 55, height: 55)

                    HStack(alignment: .center) {
                        Image(systemName: "tv.badge.wifi")
                            .resizable()
                            .aspectRatio(contentMode: .fit)
                            .frame(width: 35, height: 35)
                            .symbolEffect(.variableColor)
                            .offset(x: 4, y: 0)
                    }
                }
                .padding(.horizontal, 20)

                Spacer()

                Text("Add Device")
#if os(macOS)
                    .font(.title3.bold())
#else
                    .font(.title.bold())
#endif
                Spacer()

                Spacer()
                    .frame(maxWidth: 95)
            }
            .padding(.top, 30)
            #if os(visionOS)
            .padding(.bottom, 30)
            #endif
            #endif

            Form {
                Section {
                    TextField("IP Address", text: $ipAddress)
                        .disabled(connectionStatus.isSuccess)
#if !os(macOS) && !os(watchOS)
                        .keyboardType(.numbersAndPunctuation)
#endif
                        .focused($isIpAddressFocused)
                        .onChange(of: ipAddress) {
                            validateAndConnect()
                        }
                        .autocorrectionDisabled()
                }
                Section {
                    if !connectionStatus.isIdle {
                        connectionStatusView(status: connectionStatus)
                            .transaction { transaction in
                                transaction.animation = nil
                            }
                    }
                    if connectionStatus.isIdle || connectionStatus.isInvalidIp {
                        Text("Find the IP address of your Roku by going to **Settings > Network > About** in your Roku device's Settings. Your Roku's IP address will look something like **\(ipHint)**")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                    }
                }
            }
            .onSubmit {
                submit()
            }
            .scrollContentBackground(.hidden)
            .formStyle(.grouped)
            .presentationBackground(.thickMaterial)
            .presentationDetents([.medium, .large])
#if os(watchOS)
            .navigationTitle("Add Device")
            .navigationBarTitleDisplayMode(.inline)
#else
            .scrollDisabled(true)
#endif
        }
    }

    @ViewBuilder
    private func connectionStatusView(status: ConnectionStatus) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 12) {
                Group {
                    switch status {
                    case .idle:
                        Circle()
                            .fill(Color.gray.opacity(0.3))
                            .frame(width: 10, height: 10)
                    case .connecting:
                        ProgressView()
                            .controlSize(.small)
                    case .success:
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundColor(.green)
                    case .failure, .permissionFailed:
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundColor(.red)
                    }
                }
                .frame(width: 20)

                switch status {
                case .idle:
                    Text("Waiting to connect")
                        .foregroundColor(.secondary)
                case .connecting:
                    Text("Connecting to device...")
                        .foregroundColor(.secondary)
                case .success:
                    Text("Added device successfully")
                        .foregroundColor(.green)
                        .fontWeight(.medium)
                case .failure:
                    Text("Failed to add device")
                        .foregroundColor(.red)
                        .fontWeight(.medium)
                case .permissionFailed:
                    Text("TV permission disabled")
                        .foregroundColor(.red)
                        .fontWeight(.medium)
                }

                Spacer()
                #if !os(watchOS)
                if case .success = status {
                    Button("Close", action: {dismiss()})
                        .foregroundStyle(.primary)
                }
                #endif
            }

            if case .permissionFailed = status {
                // swiftlint:disable:next line_length
                Text("You need to enable \"Control by mobile apps\" in your TV's settings. You can update this setting by going to **Settings > System > Advanced system settings > Control by mobile apps > Network access** and make sure it's set to 'Permissive' or 'Enabled'")
            }

            if case .failure(let error) = status {
                Text(error.errorDescription ?? "Connection failed")
                    .font(.callout)
                    .foregroundColor(.primary.opacity(0.8))

                if let suggestion = error.recoverySuggestion {
                    Text(suggestion)
                        .font(.callout)
                        .foregroundColor(.red.opacity(0.8))
                }

                if runningInLocalDevMode {
                    Button("Force add device", action: {
                        Task {
                            await forceAddDevice()
                        }
                    })
                    .disabled(ipAddress.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    #if !os(watchOS)
                    .buttonStyle(.bordered)
                    #endif
                }
            }
        }

        if case .permissionFailed = status {
            Button("Try again", action: {
                Task {
                    await tryConnect()
                }
            }).foregroundStyle(.primary)
            #if !os(watchOS)
                .buttonStyle(.bordered)
            #endif
        }

#if os(watchOS)
        if case .success = status {
            Button("Close", action: {dismiss()})
                .foregroundStyle(Color.primary)
        }
#endif
    }

    private func isValidIPAddress(_ string: String) -> Bool {
        let components = string.components(separatedBy: ".")
        guard components.count == 4 else { return false }

        for component in components {
            guard let num = Int(component), (0...255).contains(num) else { return false }
        }

        return true
    }

    private func validateAndConnect() {
        globalError = nil

        guard !ipAddress.isEmpty else {
            withAnimation {
                connectionStatus = .idle
            }
            return
        }

        if ipAddress.filter({ $0 == "." }).count >= 1 {
            connectTask?.cancel()
            connectTask = Task {
                await tryConnect()
            }
        }
    }

    private func tryConnect() async {
        try? await isConnecting.withLock {
            await MainActor.run {
                withAnimation {
                    connectionStatus = .connecting
                }
            }

            let isValidIp = await isValidIPAddress(ipAddress)

            do {
                let location = "http://\(await ipAddress):8060/"
                Log.connection.info("Connecting to \(location, privacy: .public)")

                let preConnectInfo: PreconnectionDeviceInfo
                do {
                    preConnectInfo = try await fetchPreconnectionInfo(location: location)
                } catch {
                    if isValidIp {
                        throw AddDeviceError.deviceNotFound
                    } else {
                        throw AddDeviceError.invalidIPAddress
                    }
                }
                do {
                    try await addDevice(preConnectInfo: preConnectInfo, location: location)
                    await MainActor.run {
                        withAnimation {
                            connectionStatus = .success
                        }
                    }
                } catch let error as LocalizedError {
                    Log.data.warning("Error adding the device: \(error, privacy: .public)")
                    throw AddDeviceError.saveDeviceError(error)
                }
            } catch let error as AddDeviceError {
                await MainActor.run {
                    withAnimation {
                        globalError = error.errorDescription
                        connectionStatus = .failure(error)
                    }
                }
            } catch let error as DataHandlerError {
                await MainActor.run {
                    withAnimation {
                        globalError = error.errorDescription
                        connectionStatus = .failure(.saveDeviceError(error))
                    }
                }
            } catch {
                let deviceError = AddDeviceError.unknown(error.localizedDescription)
                await MainActor.run {
                    withAnimation {
                        globalError = deviceError.errorDescription
                        connectionStatus = .failure(deviceError)
                    }
                }
            }
        }
    }

    private func addDevice(preConnectInfo: PreconnectionDeviceInfo, location: String) async throws {
        let dataHandler = RoamDataHandler.shared

        let device = try await dataHandler.addDevice(
            location: location,
            friendlyDeviceName: preConnectInfo.friendlyName,
            udn: preConnectInfo.udn,
            serial: preConnectInfo.serial,
            hidden: false
        )

        try await dataHandler.makePrimaryDevice(id: device)
    }

    private func forceAddDevice() async {
        connectTask?.cancel()

        let trimmedIPAddress = ipAddress.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedIPAddress.isEmpty else {
            await MainActor.run {
                withAnimation {
                    let error = AddDeviceError.invalidIPAddress
                    globalError = error.errorDescription
                    connectionStatus = .failure(error)
                }
            }
            return
        }

        do {
            let dataHandler = RoamDataHandler.shared
            let deviceId = try await dataHandler.addDevice(
                location: "http://\(trimmedIPAddress):8060/",
                friendlyDeviceName: "Device \(trimmedIPAddress)",
                udn: UUID().uuidString,
                serial: UUID().uuidString,
                hidden: false
            )

            try await dataHandler.makePrimaryDevice(id: deviceId)

            await MainActor.run {
                withAnimation {
                    globalError = nil
                    connectionStatus = .success
                }
            }
        } catch let error as AddDeviceError {
            await MainActor.run {
                withAnimation {
                    globalError = error.errorDescription
                    connectionStatus = .failure(error)
                }
            }
        } catch let error as DataHandlerError {
            await MainActor.run {
                withAnimation {
                    globalError = error.errorDescription
                    connectionStatus = .failure(.saveDeviceError(error))
                }
            }
        } catch let error as LocalizedError {
            await MainActor.run {
                withAnimation {
                    globalError = error.errorDescription
                    connectionStatus = .failure(.saveDeviceError(error))
                }
            }
        } catch {
            let deviceError = AddDeviceError.unknown(error.localizedDescription)
            await MainActor.run {
                withAnimation {
                    globalError = deviceError.errorDescription
                    connectionStatus = .failure(deviceError)
                }
            }
        }
    }

    func submit() {
        globalError = nil
        ipAddressError = nil

        guard !ipAddress.isEmpty else {
            withAnimation {
                let error = AddDeviceError.invalidIPAddress
                ipAddressError = error.errorDescription
                connectionStatus = .failure(error)
            }
            return
        }

        connectTask?.cancel()
        connectTask = Task {
            await tryConnect()
        }
    }
}

enum AddDeviceError: Error {
    case invalidIPAddress
    case deviceNotFound
    case networkError
    case saveDeviceError(LocalizedError)
    case unknown(String)
}

extension AddDeviceError: LocalizedError {
    var errorDescription: String? {
        switch self {
        case .invalidIPAddress:
            return String(localized: "Invalid IP address format", comment: "Error for invalid IP address format")
        case .deviceNotFound:
            return String(localized: "Device not found at the specified IP address", comment: "Error when device not found")
        case .networkError:
            return String(localized: "No WiFi network connection", comment: "Network error with message")
        case .saveDeviceError(let error):
            return error.errorDescription ?? String(localized: "Failed to save device", comment: "Error when saving device fails")
        case .unknown(let message):
            return String(localized: "An unknown error occurred: \(message)", comment: "Unknown error with message")
        }
    }

    var recoverySuggestion: String? {
        switch self {
        case .invalidIPAddress:
            return String(localized: "Check the IP address you entered and try again", comment: "Recovery suggestion for invalid IP address")
        case .deviceNotFound:
            return String(
                localized: "Check the IP address you entered is correct, and ensure that your Apple device and the Roku device are connected to the same WiFi network",
                comment: "Recovery suggestion for device not found"
            )
        case .networkError:
            return String(localized: "Make sure you are connected to a WiFi network and try again", comment: "Recovery suggestion for network error")
        case .saveDeviceError(let error):
            return error.recoverySuggestion ?? String(localized: "Please try saving the device again", comment: "Recovery suggestion for save device error")
        case .unknown:
            return String(localized: "Try again later or contact support", comment: "Recovery suggestion for unknown error")
        }
    }
}
#Preview("Add Device") {
    Text("Hello world!")
        .sheet(isPresented: Binding(
            get: {true},
            set: { _ in }
        )) {
            AddDeviceFlow()
        }
        .preferredColorScheme(.dark)
}
