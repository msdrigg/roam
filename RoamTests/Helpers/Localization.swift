//
//  Localization.swift
//  
//
//  Created by Florian Schweizer on 05.01.22.
//

import Foundation

public struct Localization {
    public let locale: String
    public let title: String

    public init(locale: String, title: String) {
        self.locale = locale
        self.title = title
    }
}
