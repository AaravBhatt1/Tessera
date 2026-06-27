//
//  WindowManager.swift
//  Tessera
//
//  Created by Aarav Bhatt on 14/06/2026.
//

import Foundation
import ApplicationServices
import AppKit

class WindowManager {
    
    // This function returns a list of pairs of windows on the screen and their associated application ID
    static func getAllWindows() -> [AXUIElement] {
        var output : [AXUIElement] = []
        let runningApps : [NSRunningApplication] = NSWorkspace.shared.runningApplications
        
        for app in runningApps {
            // Makes sure the apps are visible
            guard app.activationPolicy == .regular else {
                continue
            }
            
            let appElement : AXUIElement = AXUIElementCreateApplication(app.processIdentifier)
            var windowsListRef : CFTypeRef?
            let windowResult : AXError = AXUIElementCopyAttributeValue(appElement, kAXWindowsAttribute as CFString, &windowsListRef)
            
            guard windowResult == .success, let appWindows = windowsListRef as? [AXUIElement], let _ = app.bundleIdentifier else {
                continue
            }
            
            for window in appWindows {
                
                // Skips non-existant windows
                if getWindowDesc(for: window) == nil {
                    continue
                }
                
                var isMinimized : CFTypeRef?
                let axResult : AXError = AXUIElementCopyAttributeValue(window, kAXMinimizedAttribute as CFString, &isMinimized)
                if axResult == .success, isMinimized as? Bool == true {
                    continue
                }
                
                output.append(window)
            }
        }
        
        return output
    }
    
    // Returns the app name of the window
    static func getWindowApp(for window: AXUIElement) -> String? {
        var pid : pid_t = 0
        let pidResult = AXUIElementGetPid(window, &pid)
        guard pidResult == .success else {
            return nil
        }
        guard let app : NSRunningApplication = NSRunningApplication(processIdentifier: pid) else {
            return nil
        }
        return app.bundleIdentifier?.components(separatedBy: ".").last
    }

    // Returns the title of the window
    static func getWindowDesc(for window: AXUIElement) -> String? {
        var titleRef : CFTypeRef?
        let titleResult : AXError = AXUIElementCopyAttributeValue(window, kAXTitleAttribute as CFString, &titleRef)
        guard titleResult == .success, let title = titleRef as? String else {
            return nil
        }
        return title
    }
    
    // TODO: Do I need this?
    // Returns the x and y coordinates of a window
    static func getWindowPosition(for window: AXUIElement) -> (Int, Int)? {
        var positionRef : CFTypeRef?
        let axResult : AXError = AXUIElementCopyAttributeValue(window, kAXPositionAttribute as CFString, &positionRef)
        guard axResult == .success else {
            return nil
        }
        
        var position = CGPoint.zero
        let positionResult : Bool = AXValueGetValue(positionRef as! AXValue, .cgPoint, &position)
        guard positionResult else {
            return nil
        }
        
        return (Int(position.x), Int(position.y))
    }
    
    
    // Returns the width and height of a window
    static func getWindowSize(for window: AXUIElement) -> (Int, Int)? {
        var sizeRef : CFTypeRef?
        let axResult : AXError = AXUIElementCopyAttributeValue(window, kAXSizeAttribute as CFString, &sizeRef)
        guard axResult == .success else {
            return nil
        }
        
        var size = CGSize.zero
        let sizeResult : Bool = AXValueGetValue(sizeRef as! AXValue, .cgSize, &size)
        guard sizeResult else {
            return nil
        }
        
        return (Int(size.width), Int(size.height))
    }
    
    // Returns the width and height of the main screen
    static func getScreenSize() -> (Int, Int)? {
        guard let screen : NSScreen = NSScreen.main else {
            return nil
        }
        let frame : CGRect = screen.frame
        return (Int(frame.width), Int(frame.height))
    }

    // Sets the window position to an x and y co-ordinate
    static func setWindowPosition(for window: AXUIElement, to position: (Int, Int)) -> Bool {
        // Check if window is the same application
        var pid : pid_t = 0
        AXUIElementGetPid(window, &pid)
        let myPid : pid_t = getpid()
        guard pid != myPid else {
            // TODO: Potentially support modifying my own window
            return false
        }

        
        var cgPoint : CGPoint = CGPoint(x: CGFloat(position.0), y: CGFloat(position.1))
        guard let axPosition = AXValueCreate(.cgPoint, &cgPoint) else {
            return false
        }
        
        let positionResult : AXError = AXUIElementSetAttributeValue(window, kAXPositionAttribute as CFString, axPosition)
        guard positionResult == .success else {
            return false
        }
        return true
    }
    
    // Sets the window size to a width and height
    static func setWindowSize(for window: AXUIElement, to size: (Int, Int)) -> Bool {
        // Check if window is the same application
        var pid : pid_t = 0
        AXUIElementGetPid(window, &pid)
        let myPid : pid_t = getpid()
        guard pid != myPid else {
            // TODO: Potentially support modifying my own window
            return false
        }
        
        
        var cgSize : CGSize = CGSize(width: CGFloat(size.0), height: CGFloat(size.1))
        guard let axSize = AXValueCreate(.cgSize, &cgSize) else {
            return false
        }
        
        let sizeResult : AXError = AXUIElementSetAttributeValue(window, kAXSizeAttribute as CFString, axSize)
        guard sizeResult == .success else {
            return false
        }
        
        return true
    }
    
    // Resizes the window down to find the smallest size the app will allow, then optionally restores the original size
    static func getMinimumWindowSize(for window: AXUIElement, restoreOriginalSize: Bool = true) -> (Int, Int)? {
        guard let originalSize : (Int, Int) = getWindowSize(for: window) else {
            return nil
        }

        guard setWindowSize(for: window, to: (200, 200)) else {
            return nil
        }

        let minimumSize : (Int, Int)? = getWindowSize(for: window)

        if restoreOriginalSize {
            _ = setWindowSize(for: window, to: originalSize)
        }

        return minimumSize
    }

    // Update layout
    static func optimizeLayout() async -> Bool {
        let elements : [AXUIElement] = getAllWindows()
        guard let (xMax, yMax) = getScreenSize() else { return false }
        let layoutSolver : LayoutSolver = LayoutSolver()

        var windows : [LayoutWindow] = []
        for element in elements {
            let app : String = getWindowApp(for: element) ?? "Unknown"
            let title : String = getWindowDesc(for: element) ?? ""
            let w : LayoutWindow = await layoutSolver.addWindow(element: element, app: app, title: title)
            let (minWidth, minHeight) : (Int, Int) = getMinimumWindowSize(for: element) ?? (100, 100)
            await layoutSolver.addConstraint(.minimumWidth(window: w, wMin: minWidth))
            await layoutSolver.addConstraint(.minimumHeight(window: w, hMin: minHeight))
            await layoutSolver.addConstraint(.minimumX(window: w, xMin: 0))
            await layoutSolver.addConstraint(.minimumY(window: w, yMin: 0))
            await layoutSolver.addConstraint(.maximumX(window: w, xMax: xMax))
            await layoutSolver.addConstraint(.maximumY(window: w, yMax: yMax - 20))
            windows.append(w)
        }

        // TODO: Add option for floating windows (exclude from this)
        for (n1, w1) in windows.enumerated() {
            for (n2, w2) in windows.enumerated() {
                if n1 < n2 {
                    await layoutSolver.addConstraint(.noOverlap(window1: w1, window2: w2))
                }
            }
        }

        // Example constraints
        // Typst IDE is to the left of Typst Preview
        for w1 in windows {
            guard w1.app.lowercased() == "ghostty", w1.title.lowercased().contains("nvim") else { continue }
            for w2 in windows {
                guard w2.app.lowercased() == "safari", w2.title.lowercased().contains("typst") else { continue }
                await layoutSolver.addConstraint(.leftOfPref(window1: w1, window2: w2))
                await layoutSolver.addConstraint(.minimumWidthPref(window: w1, wMin: 900, weight: 40))
                await layoutSolver.addConstraint(.minimumHeightPref(window: w1, hMin: 1000, weight: 40))
                await layoutSolver.addConstraint(.minimumWidthPref(window: w2, wMin: 600, weight: 30))
                await layoutSolver.addConstraint(.minimumHeightPref(window: w2, hMin: 700, weight: 30))
            }
        }

        // Netflix/YouTube window is big and landscape
        for w in windows {
            guard w.app.lowercased() == "safari" else { continue }
            let t = w.title.lowercased()
            if t.contains("netflix") || t.contains("youtube") {
                await layoutSolver.addConstraint(.minimumWidthPref(window: w, wMin: 1000, weight: 80))
                await layoutSolver.addConstraint(.minimumHeightPref(window: w, hMin: 1000, weight: 80))
                await layoutSolver.addConstraint(.landscapePref(window: w, weight: 80))
            }
        }

        // Terminal window has a reasonable size
        for w in windows {
            guard w.app.lowercased() == "ghostty" else { continue }
            await layoutSolver.addConstraint(.minimumWidthPref(window: w, wMin: 300, weight: 80))
            await layoutSolver.addConstraint(.minimumHeightPref(window: w, hMin: 400, weight: 80))
        }

        // Focused window is bigger
        //if let focusedWindow : AXUIElement = getCurrentFocusedWindow(),
        //   let w : LayoutWindow = windows.first(where: { CFEqual($0.element, focusedWindow) }) {
        //    await layoutSolver.addConstraint(.minimumWidthPref(window: w, wMin: xMax * 2 / 3, weight: 4))
        //    await layoutSolver.addConstraint(.minimumHeightPref(window: w, hMin: yMax * 2 / 3, weight: 4))
        //}

        guard let layout : Layout = await layoutSolver.solve() else { return false }

        // Apply layout twice to reduce the chance that changes don't properly take place
        for _ in 0..<2 {
            for (window, geometry) in layout.windows {
                guard setWindowSize(for: window.element, to: (geometry.width, geometry.height)) else { return false }
                guard setWindowPosition(for: window.element, to: (geometry.x, geometry.y)) else { return false }
            }
        }

        return true
    }
    
    // Returns the current focused window
    static func getCurrentFocusedWindow() -> AXUIElement? {
        let currentApplication : NSRunningApplication? = NSWorkspace.shared.frontmostApplication
        if currentApplication == nil {
            return nil
        }
        let appElement : AXUIElement = AXUIElementCreateApplication(currentApplication!.processIdentifier)
        var windowRef : CFTypeRef?
        let result : AXError = AXUIElementCopyAttributeValue(appElement, kAXFocusedWindowAttribute as CFString, &windowRef)
        guard result == .success else {
            return nil
        }
        
        let window : AXUIElement = windowRef as! AXUIElement
        return window
    }
}
