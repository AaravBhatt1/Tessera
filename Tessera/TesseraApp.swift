//
//  TesseraApp.swift
//  Tessera
//
//  Created by Aarav Bhatt on 14/06/2026.
//

import SwiftUI

@main
struct TesseraApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var body: some Scene {
        Settings {
            EmptyView()
        }
    }
}
