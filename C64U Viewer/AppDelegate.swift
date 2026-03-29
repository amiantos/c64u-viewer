// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.

import AppKit

final class AppDelegate: NSObject, NSApplicationDelegate, DeviceWindowControllerDelegate {
    private var openDeviceWindowController: OpenDeviceWindowController?
    private var deviceWindowControllers: [DeviceWindowController] = []

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
        fileMenu.addItem(.separator())
        fileMenu.addItem(withTitle: "Close Window", action: #selector(NSWindow.performClose(_:)), keyEquivalent: "w")
        fileMenuItem.submenu = fileMenu
        mainMenu.addItem(fileMenuItem)

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
    }

    func deviceWindowDidClose(_ controller: DeviceWindowController) {
        deviceWindowControllers.removeAll { $0 === controller }
    }
}

// MARK: - OpenDeviceWindowController Delegate

extension AppDelegate: OpenDeviceWindowControllerDelegate {
    func openDeviceWindowController(_ controller: OpenDeviceWindowController, didConnectWith connection: C64Connection) {
        openDeviceWindow(connection: connection)
    }
}
