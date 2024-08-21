import SwiftUI

struct UUIDUpdaterKey: EnvironmentKey {
    // We can do this because UUIDUpdater is nil
    static let defaultValue: UUIDUpdater? = nil
}

extension EnvironmentValues {
    var uuidUpdater: UUIDUpdater? {
        get { self[UUIDUpdaterKey.self] }
        set { self[UUIDUpdaterKey.self] = newValue }
    }
}

@MainActor
class UUIDUpdater: ObservableObject {
    @Published var uuid: UUID = UUID()

    func update() {
        uuid = UUID()
    }
}
