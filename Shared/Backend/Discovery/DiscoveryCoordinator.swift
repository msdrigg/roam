#if !os(macOS) && !os(watchOS)
import Foundation

/// Holds the long-lived discovery actors so they outlive any individual view.
/// On iOS / visionOS this is owned by `RoamAppDelegate` and the actual scan
/// tasks are attached at the top-level view (`RemoteRoot`).
@MainActor
final class DiscoveryCoordinator {
    let ssdpActor: DeviceDiscoveryActor
    let ipv4Actor: DeviceDiscoveryActor

    init() {
        self.ssdpActor = DeviceDiscoveryActor()
        self.ipv4Actor = DeviceDiscoveryActor()
    }
}
#endif
