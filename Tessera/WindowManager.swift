//
//  WindowManager.swift
//  Tessera
//
//  Created by Aarav Bhatt on 14/06/2026.
//

import Foundation
import ApplicationServices
import AppKit
import Z3

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

    // AX has top-left origin and NSScreen has bottom-left origin
    private static func axToScreen(_ point: CGPoint) -> CGPoint? {
        guard let primary = NSScreen.screens.first else { return nil }
        return CGPoint(x: point.x, y: primary.frame.maxY - point.y)
    }

    private static func screenToAX(_ point: CGPoint) -> CGPoint? {
        return axToScreen(point)
    }

    // Returns the width and height of the screen the given window sits on.
    static func getScreenSize(for window: AXUIElement) -> (Int, Int)? {
        guard let (x, y) = getWindowPosition(for: window),
              let screenPoint = axToScreen(CGPoint(x: CGFloat(x), y: CGFloat(y))),
              let screen = NSScreen.screens.first(where: { $0.frame.contains(screenPoint) }) else {
            return nil
        }
        let frame : CGRect = screen.frame
        return (Int(frame.width), Int(frame.height))
    }

    // Returns the top-left (x, y) of the screen the given window sits on, in AX coordinates.
    static func getScreenPosition(for window: AXUIElement) -> (Int, Int)? {
        guard let (x, y) = getWindowPosition(for: window),
              let screenPoint = axToScreen(CGPoint(x: CGFloat(x), y: CGFloat(y))),
              let screen = NSScreen.screens.first(where: { $0.frame.contains(screenPoint) }),
              let topLeft = screenToAX(CGPoint(x: screen.frame.minX, y: screen.frame.maxY)) else {
            return nil
        }
        return (Int(topLeft.x), Int(topLeft.y))
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

    // Resizes the window up to the full screen size to find the largest size the app will allow, then optionally restores the original size
    static func getMaximumWindowSize(for window: AXUIElement, restoreOriginalSize: Bool = true) -> (Int, Int)? {
        guard let originalSize : (Int, Int) = getWindowSize(for: window) else {
            return nil
        }
        
        guard let (screenWidth, screenHeight) : (Int, Int) = getScreenSize() else {
            return nil
        }

        guard setWindowSize(for: window, to: (screenWidth, screenHeight)) else {
            return nil
        }

        let maximumSize : (Int, Int)? = getWindowSize(for: window)

        if restoreOriginalSize {
            _ = setWindowSize(for: window, to: originalSize)
        }

        return maximumSize
    }

    // Update layout
    static func optimizeLayout() async -> Bool {

        // Constrain the layout to the monitor of the currently focused window and ignore winows not on this workspace
        guard let focused = getCurrentFocusedWindow(),
              let (screenW, screenH) = getScreenSize(for: focused),
              let (screenX, screenY) = getScreenPosition(for: focused) else { return false }
        let elements : [AXUIElement] = getAllWindows().filter { element in
            guard let (ex, ey) = getScreenPosition(for: element) else { return false }
            return ex == screenX && ey == screenY
        }
        let layoutSolver : LayoutSolver = LayoutSolver()

        ConfigFileLoader.shared.reload()
        let rules : [Rule] =  ConfigFileLoader.shared.rules

        // Every dynamic tag we need to pin per window: those the user has assigned
        var knownDynamicTags : Set<String> = TagStore.shared.allKnownTags
        for rule in rules {
            knownDynamicTags.formUnion(rule.getDynamicTagNames())
        }

        var windows : [LayoutWindow] = []
        for element in elements {
            let app : String = getWindowApp(for: element) ?? "Unknown"
            let title : String = getWindowDesc(for: element) ?? ""
            let w : LayoutWindow = layoutSolver.addWindow(element: element, app: app, title: title)

            // Locked windows are pinned to their current geometry; the usual size /
            // screen-bound envelope is skipped so the pin can't be over-constrained.
            if LockStore.shared.isLocked(element),
               let (curX, curY) = getWindowPosition(for: element),
               let (curW, curH) = getWindowSize(for: element) {
                layoutSolver.addHardConstraint(w.x == layoutSolver.makeConstant(curX))
                layoutSolver.addHardConstraint(w.y == layoutSolver.makeConstant(curY))
                layoutSolver.addHardConstraint(w.width == layoutSolver.makeConstant(curW))
                layoutSolver.addHardConstraint(w.height == layoutSolver.makeConstant(curH))
            } else {
                // Adds minimum and maximum size and position (hard) constraints
                let (minWidth, minHeight) : (Int, Int) = getMinimumWindowSize(for: element) ?? (100, 100)
                layoutSolver.addConstraint(.minimumWidth(window: w, wMin: minWidth))
                layoutSolver.addConstraint(.minimumHeight(window: w, hMin: minHeight))
                let (maxWidth, maxHeight) : (Int, Int) = getMaximumWindowSize(for: element) ?? (screenW, screenH)
                layoutSolver.addConstraint(.maximumWidth(window: w, wMax: maxWidth))
                layoutSolver.addConstraint(.maximumHeight(window: w, hMax: maxHeight))
                layoutSolver.addConstraint(.minimumX(window: w, xMin: screenX))
                layoutSolver.addConstraint(.minimumY(window: w, yMin: screenY))
                layoutSolver.addConstraint(.maximumX(window: w, xMax: screenX + screenW))
                layoutSolver.addConstraint(.maximumY(window: w, yMax: screenY + screenH - 20))
            }

            // Pin every known dynamic tag: true if the user assigned it, false otherwise.
            let windowDynamicTags = TagStore.shared.tags(for: element)
            for tag in knownDynamicTags {
                layoutSolver.setDynamicTagHard(window: w, tag: tag, value: windowDynamicTags.contains(tag))
            }
            windows.append(w)
        }

        let screenSizeFor: (LayoutWindow) -> (Int, Int) = { _ in (screenW, screenH) }
        for rule in rules {
            rule.apply(windows: windows, solver: layoutSolver, screenSizeFor: screenSizeFor)
        }

        guard let layout : Layout = await layoutSolver.solve() else { return false }

        for (window, geometry) in layout.windows {
            guard setWindowSize(for: window.element, to: (geometry.width, geometry.height)) else { return false }
            guard setWindowPosition(for: window.element, to: (geometry.x, geometry.y)) else { return false }
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
