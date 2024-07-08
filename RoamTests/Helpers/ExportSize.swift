//
//  ExportSize.swift
//  Blacksmith
//
//  Created by Florian Schweizer on 03.01.22.
//

import SwiftUI

public enum ExportSize {
    case iPhone65Inches
    case iPhone55Inches

    case iPadPro129Inches

    case mac

    case visionPro
    case appleTV
    case appleWatch

    case custom(CGSize, Double)

    public var size: CGSize {
        switch self {
        case .iPhone65Inches:
            return CGSize(width: 1242, height: 2688)
        case .iPhone55Inches:
            return CGSize(width: 1242, height: 2208)
        case .iPadPro129Inches:
            return CGSize(width: 2048, height: 2732)
        case .mac:
            return CGSize(width: 2880, height: 1800)
        case .appleWatch:
            return CGSize(width: 410, height: 502)
        case .appleTV:
            return CGSize(width: 3840, height: 2160)
        case .visionPro:
            return CGSize(width: 3840, height: 2160)
        case .custom(let size, _):
            return size
        }
    }

    public var cornerRadius: Double {
        switch self {
        case .iPhone65Inches:
            return 20
        case .iPhone55Inches:
            return 24
        case .iPadPro129Inches:
            return 40
        case .mac:
            return 8
        case .appleWatch:
            return 18
        case .appleTV:
            return 24
        case .visionPro:
            return 24
        case .custom(_, let radius):
            return radius
        }
    }
}
