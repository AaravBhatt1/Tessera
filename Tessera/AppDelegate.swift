//
//  AppDelegate.swift
//  Tessera
//
//  Created by Aarav Bhatt on 14/06/2026.
//

import AppKit
import Carbon.HIToolbox

class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    private var statusItem: NSStatusItem?
    private var hotKeyRef: EventHotKeyRef?
    private var focusedWindowItem: NSMenuItem?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)

        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        item.button?.image = NSImage(systemSymbolName: "square.grid.2x2", accessibilityDescription: "Tessera")

        let focusedItem = NSMenuItem(title: "No focused window", action: nil, keyEquivalent: "")
        focusedItem.isEnabled = false
        focusedWindowItem = focusedItem

        let declutterItem = NSMenuItem(title: "Declutter", action: #selector(declutter), keyEquivalent: " ")
        declutterItem.keyEquivalentModifierMask = [.command, .shift]
        declutterItem.target = self

        let menu = NSMenu()
        menu.delegate = self
        menu.addItem(focusedItem)
        menu.addItem(NSMenuItem.separator())
        menu.addItem(declutterItem)
        item.menu = menu

        statusItem = item

        registerDeclutterHotKey()
    }

    func menuWillOpen(_ menu: NSMenu) {
        guard let window : AXUIElement = WindowManager.getCurrentFocusedWindow() else {
            focusedWindowItem?.title = "No focused window"
            return
        }
        let app : String = WindowManager.getWindowApp(for: window) ?? "Unknown app"
        let title : String = WindowManager.getWindowDesc(for: window) ?? "Untitled"
        focusedWindowItem?.title = "\(app) — \(title)"
    }

    private func registerDeclutterHotKey() {
        var eventType = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: OSType(kEventHotKeyPressed))

        let handler: @convention(c) (EventHandlerCallRef?, EventRef?, UnsafeMutableRawPointer?) -> OSStatus = { _, _, userData in
            guard let userData else { return noErr }
            Unmanaged<AppDelegate>.fromOpaque(userData).takeUnretainedValue().declutter()
            return noErr
        }
        InstallEventHandler(GetApplicationEventTarget(), handler, 1, &eventType, Unmanaged.passUnretained(self).toOpaque(), nil)

        // Arbitrary signature for Carbon
        let hotKeyID = EventHotKeyID(signature: 0x54737341, id: 1)
        // Command shift space shortcut
        RegisterEventHotKey(UInt32(kVK_Space), UInt32(cmdKey | shiftKey), hotKeyID, GetApplicationEventTarget(), 0, &hotKeyRef)
    }

    @objc private func declutter() {
        // Deferred a tick so no warning for race condition (with closing window)
        DispatchQueue.main.async {
            Task {
                await WindowManager.optimizeLayout()
            }
        }
    }
}
