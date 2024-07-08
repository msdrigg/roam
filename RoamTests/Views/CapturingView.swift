//
//  CapturingView.swift
//  Blacksmith
//
//  Created by Florian Schweizer on 04.01.22.
//

import Foundation

@MainActor
public protocol CapturingView {
    var exportSize: ExportSize { get }
}
