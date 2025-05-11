import Foundation
import SwiftUI

struct FallibleImage: View {
    let fallback: String
    let filePath: URL?
    let maxSize: CGFloat

    init(from fileURL: URL?, fallback: String, maxSize: CGFloat)  {
        self.fallback = fallback
        self.filePath = fileURL
        self.maxSize = maxSize
    }

    @ViewBuilder
    var body: some View {
        if let filePath {
            CachedAsyncImage(path: filePath, maxSize: maxSize) { phase in
                switch phase {
                case .empty, .loading:
                    Image(systemName: "rays")
                        .labelStyle(.iconOnly)
                        .symbolEffect(.variableColor)
                        .enableResize()
                case .failure:
                    Image(systemName: fallback)
                        .resizable().aspectRatio(contentMode: .fit)
                        .clipShape(RoundedRectangle(cornerRadius: 0))
                case .success(let image):
                    image
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .clipShape(RoundedRectangle(cornerRadius: 4))
                }
            }
        } else {
            Image(systemName: fallback)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .clipShape(RoundedRectangle(cornerRadius: 0))
        }
    }
}
