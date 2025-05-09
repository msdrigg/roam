import Foundation
import SwiftUI

struct FallibleImage: View {
    let fallback: String
    let filePath: URL?

    init(from fileURL: URL?, fallback: String)  {
        self.fallback = fallback
        self.filePath = fileURL
    }

    @ViewBuilder
    var body: some View {
        if let filePath {
            CachedAsyncImage(path: filePath) { phase in
                switch phase {
                case .loading:
                    //  Image(systemName: fallback)
                    //      .resizable().aspectRatio(contentMode: .fit)
                    //      .clipShape(RoundedRectangle(cornerRadius: 0))
                    Image(systemName: "rays")
                        .labelStyle(.iconOnly)
                        .symbolEffect(.variableColor)
                        .enableResize()
                case .empty, .failure:
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
