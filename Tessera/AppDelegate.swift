//
//  AppDelegate.swift
//  Tessera
//
//  Created by Aarav Bhatt on 14/06/2026.
//

import AppKit
import Carbon.HIToolbox
import ServiceManagement

// TODO: UI for errors/open config file?

class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    private var statusItem: NSStatusItem?
    private var hotKeyRef: EventHotKeyRef?
    private var focusedWindowItem: NSMenuItem?
    private var windowSizeItem: NSMenuItem?
    private var tagsMenuItem: NSMenuItem?
    private var tagsSubmenu: NSMenu?
    private var lockItem: NSMenuItem?
    private var launchAtLoginItem: NSMenuItem?
    private var focusedElementForTags: AXUIElement?
    private var idleIcon: NSImage?
    private var progressIndicator: NSProgressIndicator?
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

        let sizeItem = NSMenuItem(title: "Size: —", action: nil, keyEquivalent: "")
        sizeItem.isEnabled = false
        windowSizeItem = sizeItem

        let tagsItem = NSMenuItem(title: "Tags", action: nil, keyEquivalent: "")
        let tagsMenu = NSMenu(title: "Tags")
        tagsItem.submenu = tagsMenu
        tagsMenuItem = tagsItem
        tagsSubmenu = tagsMenu

        let lockItem = NSMenuItem(title: "Lock Position", action: #selector(toggleLock), keyEquivalent: "")
        lockItem.target = self
        self.lockItem = lockItem

        let declutterItem = NSMenuItem(title: "Declutter", action: #selector(declutter), keyEquivalent: " ")
        declutterItem.keyEquivalentModifierMask = [.command, .shift]
        declutterItem.target = self

        let reloadConfigItem = NSMenuItem(title: "Reload Config", action: #selector(reloadConfig), keyEquivalent: "")
        reloadConfigItem.target = self

        let launchAtLoginItem = NSMenuItem(title: "Open at Login", action: #selector(toggleLaunchAtLogin), keyEquivalent: "")
        launchAtLoginItem.target = self
        self.launchAtLoginItem = launchAtLoginItem

        let quitItem = NSMenuItem(title: "Quit Tessera", action: #selector(quit), keyEquivalent: "")
        quitItem.target = self

        let menu = NSMenu()
        menu.delegate = self
        menu.addItem(focusedItem)
        menu.addItem(sizeItem)
        menu.addItem(tagsItem)
        menu.addItem(lockItem)
        menu.addItem(NSMenuItem.separator())
        menu.addItem(declutterItem)
        menu.addItem(reloadConfigItem)
        menu.addItem(launchAtLoginItem)
        menu.addItem(NSMenuItem.separator())
        menu.addItem(quitItem)
        item.menu = menu

        statusItem = item

        registerDeclutterHotKey()
        enableLaunchAtLoginOnFirstRun()
    }

    func menuWillOpen(_ menu: NSMenu) {
        guard let window : AXUIElement = WindowManager.getCurrentFocusedWindow() else {
            focusedWindowItem?.title = "No focused window"
            windowSizeItem?.title = "Size: —"
            focusedElementForTags = nil
            rebuildTagsMenu()
            refreshLockItem()
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
        if let (w, h) = WindowManager.getWindowSize(for: window) {
            windowSizeItem?.title = "Size: \(w) × \(h)"
        } else {
            windowSizeItem?.title = "Size: —"
        }
        focusedElementForTags = window
        rebuildTagsMenu()
        refreshLockItem()
        refreshLaunchAtLoginItem()
    }

    private func refreshLaunchAtLoginItem() {
        guard let launchAtLoginItem = launchAtLoginItem else { return }
        launchAtLoginItem.state = (SMAppService.mainApp.status == .enabled) ? .on : .off
    }

    @objc private func toggleLaunchAtLogin() {
        let service = SMAppService.mainApp
        do {
            if service.status == .enabled {
                try service.unregister()
            } else {
                try service.register()
            }
        } catch {
            NSLog("Tessera: failed to toggle launch at login: \(error)")
        }
        refreshLaunchAtLoginItem()
    }

    // Register once on first launch so the app opens at login out of the box.
    // The user can still disable it via the menu.
    private func enableLaunchAtLoginOnFirstRun() {
        let key = "TesseraDidConfigureLaunchAtLogin"
        guard !UserDefaults.standard.bool(forKey: key) else { return }
        UserDefaults.standard.set(true, forKey: key)
        let service = SMAppService.mainApp
        if service.status != .enabled {
            try? service.register()
        }
    }

    private func refreshLockItem() {
        guard let lockItem = lockItem else { return }
        guard let focused = focusedElementForTags else {
            lockItem.title = "Lock Position"
            lockItem.image = NSImage(systemSymbolName: "lock.open", accessibilityDescription: "Unlocked")
            lockItem.isEnabled = false
            return
        }
        lockItem.isEnabled = true
        let isLocked = LockStore.shared.isLocked(focused)
        lockItem.title = isLocked ? "Unlock Position" : "Lock Position"
        lockItem.image = NSImage(
            systemSymbolName: isLocked ? "lock.fill" : "lock.open",
            accessibilityDescription: isLocked ? "Locked" : "Unlocked"
        )
    }

    @objc private func toggleLock() {
        guard let focused = focusedElementForTags else { return }
        LockStore.shared.toggle(focused)
        refreshLockItem()
    }

    private func rebuildTagsMenu() {
        guard let tagsMenu = tagsSubmenu else { return }
        tagsMenu.removeAllItems()

        guard let focused = focusedElementForTags else {
            let item = NSMenuItem(title: "No focused window", action: nil, keyEquivalent: "")
            item.isEnabled = false
            tagsMenu.addItem(item)
            return
        }

        // Dynamic tags come from the config rules (via hasDynamicTag) plus anything
        // the user has already assigned in-session.
        var availableTags: Set<String> = TagStore.shared.allKnownTags
        for rule in ConfigFileLoader.shared.rules {
            availableTags.formUnion(rule.getDynamicTagNames())
        }

        if availableTags.isEmpty {
            let item = NSMenuItem(title: "No dynamic tags in config", action: nil, keyEquivalent: "")
            item.isEnabled = false
            tagsMenu.addItem(item)
            return
        }

        let userTags = TagStore.shared.tags(for: focused)

        for tag in availableTags.sorted() {
            let item = NSMenuItem(title: tag, action: #selector(toggleTag(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = tag
            item.state = userTags.contains(tag) ? .on : .off
            tagsMenu.addItem(item)
        }
    }

    @objc private func toggleTag(_ sender: NSMenuItem) {
        guard let tag = sender.representedObject as? String,
              let focused = focusedElementForTags else { return }
        TagStore.shared.toggleTag(tag, on: focused)
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
        TagStore.shared.resetAll()
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
        startLoading()

        // Deferred a tick so no warning for race condition (with closing window)
        DispatchQueue.main.async {
            Task { @MainActor in
                let result = await WindowManager.optimizeLayout()
                self.stopLoading()
                self.isBusy = false
                self.showSolverErrorIfNeeded(result)
            }
        }
    }

    private func showSolverErrorIfNeeded(_ result: LayoutOutcome) {
        let alert = NSAlert()
        alert.alertStyle = .warning
        switch result {
        case .unsatisfiable:
            alert.messageText = "No layout satisfies your rules"
            alert.informativeText = "The constraint solver could not find a layout that meets every rule. Try removing or relaxing conflicting rules."
        case .success, .noActiveScreen, .applyFailed:
            return
        }
        NSApp.activate(ignoringOtherApps: true)
        alert.runModal()
    }

    private func startLoading() {
        guard let button = statusItem?.button else { return }

        let indicator = NSProgressIndicator()
        indicator.style = .spinning
        indicator.controlSize = .small
        indicator.isIndeterminate = true
        indicator.isDisplayedWhenStopped = false
        indicator.translatesAutoresizingMaskIntoConstraints = false
        button.addSubview(indicator)
        NSLayoutConstraint.activate([
            indicator.centerXAnchor.constraint(equalTo: button.centerXAnchor),
            indicator.centerYAnchor.constraint(equalTo: button.centerYAnchor),
        ])
        indicator.startAnimation(nil)

        button.image = nil
        progressIndicator = indicator
    }

    private func stopLoading() {
        progressIndicator?.stopAnimation(nil)
        progressIndicator?.removeFromSuperview()
        progressIndicator = nil
        statusItem?.button?.image = idleIcon
    }
}
