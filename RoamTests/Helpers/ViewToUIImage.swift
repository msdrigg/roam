//
//  ViewToUIImage.swift
//  Blacksmith
//
//  Created by Florian Schweizer on 04.01.22.
//

import SwiftUI
#if canImport(UIKit)
import UIKit

extension View {
    func takeScreenshot(origin: CGPoint, size: CGSize) -> UIImage {
        let window = UIWindow(frame: CGRect(origin: origin, size: size))

        let hosting = UIHostingController(rootView: self)

        hosting.view.frame = window.frame

        window.addSubview(hosting.view)
        window.makeKeyAndVisible()

        return hosting.view.renderedImage
    }
}

extension UIView {
    var renderedImage: UIImage {
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1

        let renderer = UIGraphicsImageRenderer(size: bounds.size, format: format)
        let pngData = renderer.pngData { _ in
            self.drawHierarchy(in: bounds, afterScreenUpdates: true)
        }

        return UIImage(data: pngData) ?? UIImage(systemName: "exclamationmark.triangle.fill")!
    }
}
#endif
