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
    // TODO: Move getting application ID to a seperate function
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
        return app.bundleIdentifier?.components(separatedBy: ".").last?.lowercased()
    }
    
    // Returns the title of the window
    static func getWindowDesc(for window: AXUIElement) -> String? {
        var titleRef : CFTypeRef?
        let titleResult : AXError = AXUIElementCopyAttributeValue(window, kAXTitleAttribute as CFString, &titleRef)
        guard titleResult == .success, let title = titleRef as? String else {
            return nil
        }
        return title.lowercased()
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
    
    
    // TODO: Do I need this?
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
        let windows : [AXUIElement] = getAllWindows()
        let windowDataList : [WindowData] = windows.map { WindowData(element: $0) }
        guard let (xMax, yMax) = getScreenSize() else {return false}
        let layoutSolver : LayoutSolver = LayoutSolver()
        
        for w in windowDataList {
            await layoutSolver.addWindow(window: w)
            let (minWidth, minHeight) : (Int, Int) = getMinimumWindowSize(for: w.element) ?? (100, 100)
            await layoutSolver.addConstraints(constraint: .minimumWidth(window: w, wMin: minWidth))
            await layoutSolver.addConstraints(constraint: .minimumHeight(window: w, hMin: minHeight))
            await layoutSolver.addConstraints(constraint: .minimumX(window: w, xMin: 0))
            await layoutSolver.addConstraints(constraint: .minimumY(window: w, yMin: 0))
            await layoutSolver.addConstraints(constraint: .maximumX(window: w, xMax: xMax))
            await layoutSolver.addConstraints(constraint: .maximumY(window: w, yMax: yMax - 20))
        }
        
        for (n1, w1) in windowDataList.enumerated() {
            for (n2, w2) in windowDataList.enumerated() {
                if (n1 < n2) {
                    await layoutSolver.addConstraints(constraint: .noOverlap(window1: w1, window2: w2))
                }
            }
        }
        
        // Example constraints
        for w1 in windowDataList {
            if getWindowApp(for: w1.element) != "ghostty" {continue}
            for w2 in windowDataList {
                if getWindowApp(for: w2.element) != "safari" {continue}
                guard let wDesc : String = getWindowDesc(for: w2.element) else {continue}
                if wDesc.contains("typst") {
                    await layoutSolver.addConstraints(constraint: .leftOfPref(window1: w1, window2: w2))
                    await layoutSolver.addConstraints(constraint: .minimumWidthPref(window: w1, wMin: 900))
                    await layoutSolver.addConstraints(constraint: .minimumHeightPref(window: w1, hMin: 900))
                }
            }
        }
        
        for w in windowDataList {
            if getWindowApp(for: w.element) != "safari" {continue}
            guard let wDesc : String = getWindowDesc(for: w.element) else {continue}
            if wDesc.contains("netflix") {
                await layoutSolver.addConstraints(constraint: .minimumWidthPref(window: w, wMin: 1300))
                await layoutSolver.addConstraints(constraint: .landscapePref(window: w))
            }

        }

        if let focusedWindow : AXUIElement = getCurrentFocusedWindow(),
           let w : WindowData = windowDataList.first(where: { $0 == WindowData(element: focusedWindow) }) {
            await layoutSolver.addConstraints(constraint: .minimumWidthPref(window: w, wMin: xMax * 2 / 3))
            await layoutSolver.addConstraints(constraint: .minimumHeightPref(window: w, hMin: yMax * 2 / 3))
        }

        let result : Bool = await layoutSolver.solve()
        return result
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
