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
        
        // Print out an example token stream (to help visualize parser)
        let sampleRule : String = "select w1, w2 then set w1 isLeftOf w2"
        var lexer : ConfigLexer = ConfigLexer(input: sampleRule)
        var tokens : [Token] = []
        while let tok = lexer.nextToken() {
            tokens.append(tok)
        }
        print("Tokens for \"\(sampleRule)\":")
        for token in tokens {
            print("  \(token)")
        }

        let elements : [AXUIElement] = getAllWindows()
        guard let (xMax, yMax) = getScreenSize() else { return false }
        let layoutSolver : LayoutSolver = LayoutSolver()
        layoutSolver.makeConstant(15)   // padding
        layoutSolver.makeConstant(35)   // padding for y (accounts for menu bar height)
        layoutSolver.makeConstant(5)    // landscape/portrait ratio denominator
        layoutSolver.makeConstant(7)    // landscape/portrait ratio numerator
        layoutSolver.makeConstant(300)  // minimum terminal width
        layoutSolver.makeConstant(400)  // minimum terminal height
        layoutSolver.makeConstant(600)  // minimum preview width
        layoutSolver.makeConstant(700)  // minimum preview height
        layoutSolver.makeConstant(900)  // minimum editor width
        layoutSolver.makeConstant(1000) // minimum media/editor height

        var windows : [LayoutWindow] = []
        for element in elements {
            let app : String = getWindowApp(for: element) ?? "Unknown"
            let title : String = getWindowDesc(for: element) ?? ""
            let w : LayoutWindow = layoutSolver.addWindow(element: element, app: app, title: title)
            // Adds minimum and maximum size and position (hard) constraints
            let (minWidth, minHeight) : (Int, Int) = getMinimumWindowSize(for: element) ?? (100, 100)
            layoutSolver.addConstraint(.minimumWidth(window: w, wMin: minWidth))
            layoutSolver.addConstraint(.minimumHeight(window: w, hMin: minHeight))
            //let (maxWidth, maxHeight) : (Int, Int) = getMaximumWindowSize(for: element) ?? (xMax, yMax)
            //layoutSolver.addConstraint(.maximumWidth(window: w, wMax: maxWidth))
            //layoutSolver.addConstraint(.maximumHeight(window: w, hMax: maxHeight))
            layoutSolver.addConstraint(.minimumX(window: w, xMin: 0))
            layoutSolver.addConstraint(.minimumY(window: w, yMin: 0))
            layoutSolver.addConstraint(.maximumX(window: w, xMax: xMax))
            layoutSolver.addConstraint(.maximumY(window: w, yMax: yMax - 20))
            windows.append(w)
        }

        let netflixYoutubeCondition : ConditionExpr = .and(
           .appContains(window: "w", value: "safari"),
                .or(.titleContains(window: "w", value: "netflix"), .titleContains(window: "w", value: "youtube"))
        )

        let rules : [Rule] = [
            // Netflix/YouTube should be large and landscape
            Rule(variables: ["w"], condition: netflixYoutubeCondition, effect: .minimumSize(window: "w", wMin: 700, hMin: 500), weight: 200),
            Rule(variables: ["w"], condition: netflixYoutubeCondition, effect: .landscape(window: "w"), weight: 100),

            // XCode windows should have a reasonable size
            Rule(variables: ["w"], condition: .appContains(window: "w", value: "XCode"), effect: .minimumSize(window: "w", wMin: 500, hMin: 800), weight: 120),

            // Mail windows should have a reasonable size
            Rule(variables: ["w"], condition: .appContains(window: "w", value: "Mail"), effect: .minimumSize(window: "w", wMin: 300, hMin: 500), weight: 90),

            // Safari isn't too wide
            Rule(variables: ["w"], condition: .appContains(window: "w", value: "Safari"), effect: .minimumSize(window: "w", wMin: 700, hMin: 400), weight: 50),

            Rule(variables: ["w1", "w2"], condition: .appContains(window: "w1", value: "XCode"), effect: .leftOf(window1: "w1", window2: "w2"), weight: 10)
        ]
        
        // TODO: Potentially combine application of similar rules (though specifically ones with the same number of windows) - maybe via source to source translation
        for rule in rules {
            rule.apply(windows: windows, solver: layoutSolver)
        }

        guard let layout : Layout = await layoutSolver.solve() else { return false }
        

        // Apply layout twice to reduce the chance that changes don't properly take place
        for _ in 0..<2 {
            for (window, geometry) in layout.windows {
                guard setWindowSize(for: window.element, to: (geometry.width, geometry.height)) else { return false }
                guard setWindowPosition(for: window.element, to: (geometry.x, geometry.y)) else { return false }
            }
        }
        
        print("Done")

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
