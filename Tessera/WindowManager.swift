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
    
    // Singleton instance
    static let shared = WindowManager()
    
    private init() {}
    
    // This function returns a list of pairs of windows on the screen and their associated application ID
    func getAllWindows() -> [(String, AXUIElement)] {
        var output : [(String, AXUIElement)] = []
        let runningApps : [NSRunningApplication] = NSWorkspace.shared.runningApplications
        
        for app in runningApps {
            // Makes sure the apps are visible
            guard app.activationPolicy == .regular else {
                continue
            }
            
            let appElement : AXUIElement = AXUIElementCreateApplication(app.processIdentifier)
            var windowsListRef : CFTypeRef?
            let windowResult : AXError = AXUIElementCopyAttributeValue(appElement, kAXWindowsAttribute as CFString, &windowsListRef)
            
            guard windowResult == .success, let appWindows = windowsListRef as? [AXUIElement], let appID : String = app.bundleIdentifier else {
                continue
            }
            
            for window in appWindows {
                
                
                
                // Skips non-existant windows
                if getWindowTitle(for: window) == nil {
                    continue
                }
                
                var isMinimized: CFTypeRef?
                let axResult = AXUIElementCopyAttributeValue(window, kAXMinimizedAttribute as CFString, &isMinimized)
                if axResult == .success, isMinimized as? Bool == true {
                    continue
                }
                
                output.append((appID, window))
            }
        }
        
        return output
    }
    
    // Returns the title of the window
    func getWindowTitle(for window: AXUIElement) -> String? {
        var titleRef : CFTypeRef?
        let titleResult : AXError = AXUIElementCopyAttributeValue(window, kAXTitleAttribute as CFString, &titleRef)
        guard titleResult == .success, let title = titleRef as? String else {
            return nil
        }
        return title
    }
    
    // Returns the x and y coordinates of a window
    func getWindowPosition(for window: AXUIElement) -> (Int, Int)? {
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
    func getWindowSize(for window: AXUIElement) -> (Int, Int)? {
        var sizeRef : CFTypeRef?
        let axResult : AXError = AXUIElementCopyAttributeValue(window, kAXSizeAttribute as CFString, &sizeRef)
        guard axResult == .success else {
            return nil
        }
        
        var size = CGSize.zero
        let sizeResult : Bool = AXValueGetValue(sizeRef as! AXValue, .cgPoint, &size)
        guard sizeResult else {
            return nil
        }
        
        return (Int(size.width), Int(size.height))
    }
    
    // Sets the window position to an x and y co-ordinate
    func setWindowPosition(for window: AXUIElement, to position: (Int, Int)) -> Bool {
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
    func setWindowSize(for window: AXUIElement, to size: (Int, Int)) -> Bool {
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
    
    // Returns the current focused window
    func getCurrentFocusedWindow() -> AXUIElement? {
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
        
        let window = windowRef as! AXUIElement
        return window
    }
}
