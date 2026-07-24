//
//  Log.swift
//  Tessera
//
//  Created by Aarav Bhatt on 24/07/2026.
//

import Foundation
import os

enum Log {
    private static let subsystem = Bundle.main.bundleIdentifier ?? "Tessera"

    static let discovery = Logger(subsystem: subsystem, category: "1-WindowDiscovery")
    static let solve = Logger(subsystem: subsystem, category: "2-LayoutSolve")
    static let placement = Logger(subsystem: subsystem, category: "3-WindowPlacement")

    static func newRunID() -> String {
        String(UUID().uuidString.prefix(8))
    }
}
