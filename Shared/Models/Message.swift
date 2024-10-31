import Foundation
import SwiftData

public typealias Message = SchemaV2.Message

@available(*, unavailable)
extension Message: Sendable {}

#if !WIDGET
extension Message {
    convenience init(_ message: MessageModelResponse) {
        self.init(id: message.id, message: message.message, author: message.author)
    }
}
#endif
