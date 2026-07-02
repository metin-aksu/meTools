import Cocoa
import ServiceManagement
import SwiftUI

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem?
    private var settingsWindow: NSWindow?
    let controller = EventTapController()
    private var pollTimer: Timer?

    func applicationDidFinishLaunching(_ notification: Notification) {
        MTSettings.registerDefaults()
        setupStatusItem()

        // The event tap needs Accessibility permission. Prompt on first launch
        // if any keyboard feature is on.
        if MTSettings.anyKeyboardFeatureEnabled, !AXIsProcessTrusted() {
            let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
            _ = AXIsProcessTrustedWithOptions(options)
        }

        // Poll: the moment permission is granted, start the tap — no relaunch
        // needed. Also keeps the status line and tap health up to date.
        pollTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            self?.tick()
        }
        tick()
        refreshLoginItemState()

        // Menu-bar-only app (LSUIElement): bring the settings window forward on
        // a manual launch, since accessory apps don't activate by themselves.
        showSettingsWindow()
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        // Keep running for the event tap; the settings window can be reopened
        // from the menu bar icon.
        false
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        // Launching the app again (Finder/Launchpad) brings the window back.
        showSettingsWindow()
        return true
    }

    private func tick() {
        if MTSettings.anyKeyboardFeatureEnabled {
            if AXIsProcessTrusted(), !controller.isRunning {
                controller.start()
            }
        } else if controller.isRunning {
            controller.stop()
        }
        refreshStatus()
    }

    // MARK: - Status item

    private func setupStatusItem() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let button = item.button {
            button.image = NSImage(systemSymbolName: "wrench.and.screwdriver", accessibilityDescription: "meTools")
        }

        let menu = NSMenu()
        menu.addItem(withTitle: "meTools", action: nil, keyEquivalent: "")
        menu.addItem(.separator())
        let statusLine = NSMenuItem(title: NSLocalizedString("status.initial", comment: "Initial status line"),
                                    action: nil, keyEquivalent: "")
        statusLine.tag = 100
        menu.addItem(statusLine)
        menu.addItem(withTitle: NSLocalizedString("menu.openSettings", comment: "Open settings window"),
                     action: #selector(showSettingsWindow), keyEquivalent: ",")
        menu.addItem(withTitle: NSLocalizedString("menu.openAccessibility", comment: "Open Accessibility settings"),
                     action: #selector(openAccessibilitySettings), keyEquivalent: "")
        menu.addItem(.separator())
        let loginItem = NSMenuItem(title: NSLocalizedString("menu.launchAtLogin", comment: "Launch at login"),
                                   action: #selector(toggleLaunchAtLogin), keyEquivalent: "")
        loginItem.tag = 200
        menu.addItem(loginItem)
        menu.addItem(.separator())
        menu.addItem(withTitle: NSLocalizedString("menu.quit", comment: "Quit"),
                     action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        menu.items.forEach { if $0.action != #selector(NSApplication.terminate(_:)) { $0.target = self } }
        item.menu = menu
        statusItem = item
    }

    private func refreshStatus() {
        guard let line = statusItem?.menu?.item(withTag: 100) else { return }
        if !MTSettings.anyKeyboardFeatureEnabled {
            line.title = NSLocalizedString("status.keyboardOff", comment: "No keyboard feature enabled")
        } else if !AXIsProcessTrusted() {
            line.title = NSLocalizedString("status.waiting", comment: "Waiting for permission")
        } else if controller.isRunning {
            line.title = NSLocalizedString("status.active", comment: "Active")
        } else {
            line.title = NSLocalizedString("status.starting", comment: "Permission granted, starting")
        }
    }

    private func refreshLoginItemState() {
        guard let item = statusItem?.menu?.item(withTag: 200) else { return }
        item.state = (SMAppService.mainApp.status == .enabled) ? .on : .off
    }

    // MARK: - Actions

    @objc private func showSettingsWindow() {
        if settingsWindow == nil {
            let window = NSWindow(contentViewController: NSHostingController(rootView: ContentView()))
            window.title = "meTools"
            window.styleMask = [.titled, .closable, .miniaturizable]
            window.isReleasedWhenClosed = false
            window.center()
            settingsWindow = window
        }
        NSApp.activate(ignoringOtherApps: true)
        settingsWindow?.makeKeyAndOrderFront(nil)
    }

    @objc private func toggleLaunchAtLogin() {
        do {
            if SMAppService.mainApp.status == .enabled {
                try SMAppService.mainApp.unregister()
            } else {
                try SMAppService.mainApp.register()
            }
        } catch {
            NSLog("meTools: giriş öğesi değiştirilemedi: \(error.localizedDescription)")
        }
        refreshLoginItemState()
    }

    @objc private func openAccessibilitySettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
            NSWorkspace.shared.open(url)
        }
    }
}
