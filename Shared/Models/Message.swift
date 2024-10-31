import Foundation
import SwiftData

public typealias Message = SchemaV2.Message

extension Message {
    internal static func fetchAllRequest() -> FetchDescriptor<Message> {
        var fd = FetchDescriptor(
            predicate: #Predicate<Message> { _ in
                true
            }
        )
        fd.relationshipKeyPathsForPrefetching = []

        return fd
    }
}

@available(*, unavailable)
extension Message: Sendable {}

#if !WIDGET
extension Message {
    convenience init(_ message: MessageModelResponse) {
        self.init(id: message.id, message: message.message, author: message.author)
    }
}
#endif
