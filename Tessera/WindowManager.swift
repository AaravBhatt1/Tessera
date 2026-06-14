//
//  WindowManager.swift
//  Tessera
//
//  Created by Aarav Bhatt on 14/06/2026.
//

import Foundation
import ApplicationServices
import AppKit

actor WindowManager {
    // This function returns a list of pairs of windows on the screen and their associated application ID
    func getAllWindows() -> [(String, AXUIElement)] {
        var output : [(String, AXUIElement)] = []
        let runningApps : [NSRunningApplication] = NSWorkspace.shared.runningApplications
        for app in runningApps {
            let appElement : AXUIElement = AXUIElementCreateApplication(app.processIdentifier)
            var windowsListRef : CFTypeRef?
            let result : AXError = AXUIElementCopyAttributeValue(appElement, kAXWindowsAttribute as CFString, &windowsListRef)
            if result == .success, let appWindows = windowsListRef as? [AXUIElement], let appID : String = app.bundleIdentifier {
                for window in appWindows {
                    output.append((appID, window))
                }
            }
        }
        return output
    }
}
