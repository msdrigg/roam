import Foundation

struct RoamDataSnapshot: Sendable {
    var devicesByID: [String: Device] = [:]
    var visibleDeviceIDs: [String] = []
    var hiddenDeviceIDs: [String] = []
    var appsByDeviceID: [String: [AppLink]] = [:]
    var primaryDeviceID: String?
    var messagesByID: [String: Message] = [:]
    var revision: Int64 = 0

    var primaryDevice: Device? {
        guard let primaryDeviceID else { return nil }
        return devicesByID[primaryDeviceID]
    }

    var primaryApps: [AppLink]? {
        guard let primaryDeviceID else { return nil }
        return appsByDeviceID[primaryDeviceID] ?? []
    }

    var messages: [Message] {
        messagesByID.values.sorted { lhs, rhs in
            switch (lhs.timestamp, rhs.timestamp) {
            case let (left?, right?):
                if left == right {
                    return lhs.id < rhs.id
                }
                return left < right
            case (_?, nil):
                return true
            case (nil, _?):
                return false
            case (nil, nil):
                return lhs.id < rhs.id
            }
        }
    }

    var unreadMessageCount: Int {
        messagesByID.values.count { message in
            message.author == .support && !message.viewed && !message.hidden
        }
    }
}
