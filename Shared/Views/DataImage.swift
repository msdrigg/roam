import Foundation
import SwiftUI

// swiftlint:disable:next identifier_name
func DataImage(from data: Data?, fallback: String) -> some View {
    if let data {
        #if os(macOS)
            if let nsImage = NSImage(data: data) {
                Image(nsImage: nsImage)
                    .resizable().aspectRatio(contentMode: .fit)
                    .clipShape(RoundedRectangle(cornerRadius: 4))
            } else {
                Image(systemName: fallback)
                    .resizable().aspectRatio(contentMode: .fit)
                    .clipShape(RoundedRectangle(cornerRadius: 0))
            }
        #else
            if let uiImage = UIImage(data: data) {
                Image(uiImage: uiImage)
                    .resizable().aspectRatio(contentMode: .fit)
                    .clipShape(RoundedRectangle(cornerRadius: 4))
            } else {
                Image(systemName: fallback)
                    .resizable().aspectRatio(contentMode: .fit)
                    .clipShape(RoundedRectangle(cornerRadius: 0))
            }
        #endif
    } else {
        Image(systemName: fallback)
            .resizable().aspectRatio(contentMode: .fit)
            .clipShape(RoundedRectangle(cornerRadius: 0))
    }
}
