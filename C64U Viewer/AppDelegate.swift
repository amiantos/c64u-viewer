// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.

import AppKit

final class AppDelegate: NSObject, NSApplicationDelegate, DeviceWindowControllerDelegate {
    private var openDeviceWindowController: OpenDeviceWindowController?
    private(set) var deviceWindowControllers: [DeviceWindowController] = []
    private var scratchpadWindowControllers: [BASICScratchpadWindowController] = []

    func applicationDidFinishLaunching(_ notification: Notification) {
        setupMainMenu()
        NSApp.activate(ignoringOtherApps: true)
        showOpenDeviceWindow()
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ application: NSApplication) -> Bool {
        false
    }

    // MARK: - Main Menu

    private func setupMainMenu() {
        let mainMenu = NSMenu()

        // App menu
        let appMenuItem = NSMenuItem()
        let appMenu = NSMenu()
        appMenu.addItem(withTitle: "About C64 Ultimate Toolbox", action: #selector(NSApplication.orderFrontStandardAboutPanel(_:)), keyEquivalent: "")
        appMenu.addItem(.separator())
        appMenu.addItem(withTitle: "Quit C64 Ultimate Toolbox", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        appMenuItem.submenu = appMenu
        mainMenu.addItem(appMenuItem)

        // File menu
        let fileMenuItem = NSMenuItem()
        let fileMenu = NSMenu(title: "File")
        fileMenu.addItem(withTitle: "Open Device…", action: #selector(showOpenDeviceWindow), keyEquivalent: "o")
        fileMenu.addItem(withTitle: "New BASIC Scratchpad", action: #selector(newBASICScratchpad), keyEquivalent: "n")
        fileMenu.addItem(.separator())

        // BASIC Scratchpad file operations (auto-disable when no scratchpad is key)
        fileMenu.addItem(withTitle: "Open File…", action: #selector(BASICScratchpadViewController.openFile), keyEquivalent: "o")
        fileMenu.items.last?.keyEquivalentModifierMask = [.command, .shift]
        fileMenu.addItem(.separator())
        fileMenu.addItem(withTitle: "Save", action: #selector(BASICScratchpadViewController.saveFile), keyEquivalent: "s")
        fileMenu.addItem(withTitle: "Save As…", action: #selector(BASICScratchpadViewController.saveFileAs), keyEquivalent: "s")
        fileMenu.items.last?.keyEquivalentModifierMask = [.command, .shift]
        fileMenu.addItem(.separator())

        let samplesItem = NSMenuItem(title: "New File From Template", action: nil, keyEquivalent: "")
        let samplesMenu = NSMenu()
        for sample in BASICSamples.all {
            let item = NSMenuItem(title: sample.name, action: #selector(BASICScratchpadViewController.loadSampleFromMenu(_:)), keyEquivalent: "")
            item.representedObject = sample
            samplesMenu.addItem(item)
        }
        samplesItem.submenu = samplesMenu
        fileMenu.addItem(samplesItem)
        fileMenu.addItem(.separator())

        fileMenu.addItem(withTitle: "Close Window", action: #selector(NSWindow.performClose(_:)), keyEquivalent: "w")
        fileMenuItem.submenu = fileMenu
        mainMenu.addItem(fileMenuItem)

        // Stream menu
        let streamMenuItem = NSMenuItem()
        let streamMenu = NSMenu(title: "Stream")
        streamMenu.addItem(withTitle: "Disconnect", action: #selector(DeviceWindowController.disconnectDevice), keyEquivalent: "d")
        streamMenu.addItem(.separator())
        streamMenu.addItem(withTitle: "Volume Up", action: #selector(DeviceWindowController.volumeUp), keyEquivalent: String(Character(UnicodeScalar(NSUpArrowFunctionKey)!)))
        streamMenu.items.last?.keyEquivalentModifierMask = .command
        streamMenu.addItem(withTitle: "Volume Down", action: #selector(DeviceWindowController.volumeDown), keyEquivalent: String(Character(UnicodeScalar(NSDownArrowFunctionKey)!)))
        streamMenu.items.last?.keyEquivalentModifierMask = .command
        streamMenu.addItem(withTitle: "Mute", action: #selector(DeviceWindowController.toggleMute), keyEquivalent: "m")
        streamMenu.items.last?.keyEquivalentModifierMask = [.command, .shift]
        streamMenuItem.submenu = streamMenu
        mainMenu.addItem(streamMenuItem)

        // Capture menu
        let captureMenuItem = NSMenuItem()
        let captureMenu = NSMenu(title: "Capture")
        captureMenu.addItem(withTitle: "Take Screenshot", action: #selector(DeviceWindowController.takeScreenshot), keyEquivalent: "s")
        captureMenu.items.last?.keyEquivalentModifierMask = [.command, .shift]
        captureMenu.addItem(withTitle: "Start/Stop Recording", action: #selector(DeviceWindowController.toggleRecording), keyEquivalent: "r")
        captureMenu.items.last?.keyEquivalentModifierMask = [.command, .shift]
        captureMenuItem.submenu = captureMenu
        mainMenu.addItem(captureMenuItem)

        // Preset menu (dynamic — populated by the key window's DeviceWindowController)
        let presetMenuItem = NSMenuItem()
        let presetMenu = NSMenu(title: "Preset")
        presetMenu.delegate = self
        presetMenuItem.submenu = presetMenu
        mainMenu.addItem(presetMenuItem)

        // Window menu
        let windowMenuItem = NSMenuItem()
        let windowMenu = NSMenu(title: "Window")
        windowMenu.addItem(withTitle: "Minimize", action: #selector(NSWindow.performMiniaturize(_:)), keyEquivalent: "m")
        windowMenu.addItem(withTitle: "Zoom", action: #selector(NSWindow.performZoom(_:)), keyEquivalent: "")
        windowMenuItem.submenu = windowMenu
        mainMenu.addItem(windowMenuItem)
        NSApp.windowsMenu = windowMenu

        NSApp.mainMenu = mainMenu
    }

    // MARK: - Open Device

    @objc func showOpenDeviceWindow(_ sender: Any? = nil) {
        if let existing = openDeviceWindowController {
            existing.window?.makeKeyAndOrderFront(nil)
            return
        }
        let controller = OpenDeviceWindowController()
        controller.delegate = self
        controller.showWindow(nil)
        openDeviceWindowController = controller
    }

    // MARK: - Device Windows

    func openDeviceWindow(connection: C64Connection) {
        let controller = DeviceWindowController(connection: connection)
        controller.delegate = self
        controller.showWindow(nil)
        deviceWindowControllers.append(controller)
        NotificationCenter.default.post(name: .deviceListDidChange, object: nil)
    }

    func deviceWindowDidClose(_ controller: DeviceWindowController) {
        deviceWindowControllers.removeAll { $0 === controller }
        NotificationCenter.default.post(name: .deviceListDidChange, object: nil)
    }

    // MARK: - BASIC Scratchpad Windows

    @objc func newBASICScratchpad() {
        let controller = BASICScratchpadWindowController()
        controller.showWindow(nil)
        scratchpadWindowControllers.append(controller)
    }

    func scratchpadWindowDidClose(_ controller: BASICScratchpadWindowController) {
        scratchpadWindowControllers.removeAll { $0 === controller }
    }

    // MARK: - Toolbox Connections

    func toolboxConnections() -> [(label: String, connection: C64Connection)] {
        deviceWindowControllers.compactMap { controller in
            let conn = controller.connection
            guard conn.connectionMode == .toolbox, conn.isConnected else { return nil }
            let label: String
            if let info = conn.deviceInfo {
                label = info.hostname
            } else if let baseURL = conn.apiClient?.baseURL {
                label = baseURL
            } else {
                label = "Unknown Device"
            }
            return (label: label, connection: conn)
        }
    }
}

// MARK: - OpenDeviceWindowController Delegate

extension AppDelegate: OpenDeviceWindowControllerDelegate {
    func openDeviceWindowController(_ controller: OpenDeviceWindowController, didConnectWith connection: C64Connection) {
        controller.window?.close()
        openDeviceWindowController = nil
        openDeviceWindow(connection: connection)
    }
}

// MARK: - Preset Menu (NSMenuDelegate)

extension AppDelegate: NSMenuDelegate {
    private var activeDeviceController: DeviceWindowController? {
        deviceWindowControllers.first { $0.window?.isKeyWindow == true }
    }

    func menuNeedsUpdate(_ menu: NSMenu) {
        guard menu.title == "Preset" else { return }
        menu.removeAllItems()

        guard let controller = activeDeviceController else {
            let item = NSMenuItem(title: "No Device Connected", action: nil, keyEquivalent: "")
            item.isEnabled = false
            menu.addItem(item)
            return
        }

        let connection = controller.connection
        let entries = connection.presetManager.allPresetEntries
        let selected = connection.presetManager.selectedIdentifier

        for entry in entries {
            let item = NSMenuItem(title: entry.name, action: #selector(presetMenuItemSelected(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = PresetMenuEntry(id: entry.id, controller: controller)
            if entry.id == selected {
                item.state = .on
            }
            menu.addItem(item)
        }
    }

    @objc private func presetMenuItemSelected(_ sender: NSMenuItem) {
        guard let entry = sender.representedObject as? PresetMenuEntry else { return }
        entry.controller.connection.selectPreset(entry.id)
    }
}

private class PresetMenuEntry: NSObject {
    let id: PresetIdentifier
    let controller: DeviceWindowController

    init(id: PresetIdentifier, controller: DeviceWindowController) {
        self.id = id
        self.controller = controller
    }
}
