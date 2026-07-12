//
//  AppDelegate.swift
//  Tessera
//
//  Created by Aarav Bhatt on 14/06/2026.
//

import AppKit
import Carbon.HIToolbox
import QuartzCore

// TODO: UI for errors/open config file?
// TODO: UI for adding and removing tags dynamically (once tagging is implemented) - perhaps via dropdown
 
private let pulseAnimationKey = "tessera.pulse"

class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    private var statusItem: NSStatusItem?
    private var hotKeyRef: EventHotKeyRef?
    private var focusedWindowItem: NSMenuItem?
    private var idleIcon: NSImage?
    private var isBusy: Bool = false

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)

        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        let icon = NSImage(named: "MenuBarIcon")
        icon?.size = NSSize(width: 20, height: 20)
        idleIcon = icon
        item.button?.image = icon
        item.button?.wantsLayer = true

        let focusedItem = NSMenuItem(title: "No focused window", action: nil, keyEquivalent: "")
        focusedItem.isEnabled = false
        focusedWindowItem = focusedItem

        let declutterItem = NSMenuItem(title: "Declutter", action: #selector(declutter), keyEquivalent: " ")
        declutterItem.keyEquivalentModifierMask = [.command, .shift]
        declutterItem.target = self

        let reloadConfigItem = NSMenuItem(title: "Reload Config", action: #selector(reloadConfig), keyEquivalent: "")
        reloadConfigItem.target = self

        let quitItem = NSMenuItem(title: "Quit Tessera", action: #selector(quit), keyEquivalent: "")
        quitItem.target = self

        let menu = NSMenu()
        menu.delegate = self
        menu.addItem(focusedItem)
        menu.addItem(NSMenuItem.separator())
        menu.addItem(declutterItem)
        menu.addItem(reloadConfigItem)
        menu.addItem(NSMenuItem.separator())
        menu.addItem(quitItem)
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
        let full : String = "\(app) — \(title)"
        // Caps the maximum length to 50 (to fix issues with youtube videos)
        let maxLength = 50
        focusedWindowItem?.title = full.count > maxLength
            ? String(full.prefix(maxLength)) + "..."
            : full
    }

    private func registerDeclutterHotKey() {
        var eventType = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: OSType(kEventHotKeyPressed))

        let handler: @convention(c) (EventHandlerCallRef?, EventRef?, UnsafeMutableRawPointer?) -> OSStatus = { _, _, userData in
            guard let userData else { return noErr }
            Unmanaged<AppDelegate>.fromOpaque(userData).takeUnretainedValue().declutter()
            return noErr
        }
        InstallEventHandler(GetApplicationEventTarget(), handler, 1, &eventType, Unmanaged.passUnretained(self).toOpaque(), nil)

        let hotKeyID = EventHotKeyID(signature: 0x54737341, id: 1)
        // Command shift space shortcut
        RegisterEventHotKey(UInt32(kVK_Space), UInt32(cmdKey | shiftKey), hotKeyID, GetApplicationEventTarget(), 0, &hotKeyRef)
    }

    @objc private func reloadConfig() {
        let errors = ConfigFileLoader.shared.reload()
        let alert = NSAlert()
        if errors.isEmpty {
            alert.messageText = "Config reloaded"
            alert.informativeText = "Loaded \(ConfigFileLoader.shared.rules.count) rule(s)."
            alert.alertStyle = .informational
        } else {
            alert.messageText = "Config errors (\(errors.count))"
            alert.alertStyle = .warning
            alert.accessoryView = makeErrorAccessoryView(for: errors)
        }
        NSApp.activate(ignoringOtherApps: true)
        alert.runModal()
    }

    private func makeErrorAccessoryView(for errors: [ConfigError]) -> NSView {
        let body = NSMutableAttributedString()
        let bodyFont = NSFont.systemFont(ofSize: NSFont.systemFontSize)
        let monoFont = NSFont.monospacedSystemFont(ofSize: NSFont.systemFontSize, weight: .regular)

        for (i, err) in errors.enumerated() {
            if i > 0 { body.append(NSAttributedString(string: "\n\n")) }

            if let lineNum = err.lineNumber {
                body.append(NSAttributedString(
                    string: "Line \(lineNum)",
                    attributes: [.font: bodyFont, .foregroundColor: NSColor.secondaryLabelColor]
                ))
                body.append(NSAttributedString(string: "\n", attributes: [.font: bodyFont]))
            }

            if let source = err.sourceLine {
                body.append(NSAttributedString(
                    string: source,
                    attributes: [.font: monoFont, .foregroundColor: NSColor.labelColor]
                ))
                body.append(NSAttributedString(string: "\n", attributes: [.font: bodyFont]))
            }

            body.append(NSAttributedString(
                string: err.message,
                attributes: [.font: bodyFont, .foregroundColor: NSColor.systemRed]
            ))
        }

        let width: CGFloat = 460
        let height: CGFloat = min(320, max(60, CGFloat(errors.count) * 60))

        let textView = NSTextView(frame: NSRect(x: 0, y: 0, width: width, height: height))
        textView.isEditable = false
        textView.isSelectable = true
        textView.drawsBackground = false
        textView.textContainerInset = NSSize(width: 4, height: 4)
        textView.textStorage?.setAttributedString(body)

        let scrollView = NSScrollView(frame: NSRect(x: 0, y: 0, width: width, height: height))
        scrollView.hasVerticalScroller = true
        scrollView.borderType = .bezelBorder
        scrollView.documentView = textView
        return scrollView
    }

    @objc private func quit() {
        NSApp.terminate(nil)
    }

    @objc private func declutter() {
        guard !isBusy else { return }
        isBusy = true
        startPulse()

        // Deferred a tick so no warning for race condition (with closing window)
        DispatchQueue.main.async {
            Task { @MainActor in
                _ = await WindowManager.optimizeLayout()
                self.stopPulse()
                self.isBusy = false
            }
        }
    }

    private func startPulse() {
        guard let layer = statusItem?.button?.layer else { return }
        let pulse = CABasicAnimation(keyPath: "opacity")
        pulse.fromValue = 1.0
        pulse.toValue = 0.3
        pulse.duration = 0.7
        pulse.autoreverses = true
        pulse.repeatCount = .infinity
        pulse.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
        layer.add(pulse, forKey: pulseAnimationKey)
    }

    private func stopPulse() {
        guard let layer = statusItem?.button?.layer else { return }
        layer.removeAnimation(forKey: pulseAnimationKey)
        layer.opacity = 1.0
    }
}
