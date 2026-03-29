// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.

import AppKit
import MetalKit
internal import UniformTypeIdentifiers

protocol DeviceWindowControllerDelegate: AnyObject {
    func deviceWindowDidClose(_ controller: DeviceWindowController)
}

final class DeviceWindowController: NSWindowController, NSToolbarDelegate {
    weak var delegate: DeviceWindowControllerDelegate?
    let connection: C64Connection

    private let splitViewController = NSSplitViewController()
    private var videoViewController: VideoViewController!
    private var inspectorItem: NSSplitViewItem?

    init(connection: C64Connection) {
        self.connection = connection

        let defaultSize = NSRect(x: 0, y: 0, width: 1200, height: 750)
        let window = DeviceWindow(
            contentRect: defaultSize,
            styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        window.minSize = NSSize(width: 700, height: 450)
        window.isReleasedWhenClosed = false
        window.titlebarAppearsTransparent = false
        window.toolbarStyle = .unified

        // Set window title
        if let info = connection.deviceInfo {
            window.title = "\(info.product) — \(info.hostname)"
        } else if connection.connectionMode == .toolbox {
            window.title = "C64 Ultimate Toolbox"
        } else {
            window.title = "C64 Ultimate Viewer"
        }

        super.init(window: window)

        setupSplitView()
        setupToolbar()

        window.contentViewController = splitViewController
        window.delegate = self

        // Frame autosave — must use NSWindowController's method, not NSWindow's
        let autosaveKey: String
        if let client = connection.apiClient {
            autosaveKey = "DeviceWindow-\(client.baseURL)"
        } else {
            autosaveKey = "DeviceWindow-Viewer-\(connection.videoPort)-\(connection.audioPort)"
        }

        if !window.setFrameUsingName(autosaveKey) {
            window.setContentSize(NSSize(width: 1200, height: 750))
            window.center()
        }

        self.windowFrameAutosaveName = autosaveKey

        videoViewController.onMenuButton = { [weak self] in
            self?.menuTapped()
        }
    }

    // MARK: - Keyboard Forwarding

    func handleKeyDown(with event: NSEvent) -> Bool {
        guard let forwarder = connection.keyboardForwarder, forwarder.isEnabled else {
            return false
        }

        switch Int(event.keyCode) {
        case 36: forwarder.sendKey(0x0D); return true // Return
        case 51: forwarder.sendKey(0x14); return true // Delete
        case 53: forwarder.sendKey(0x03); return true // Escape → RUN/STOP
        case 126: forwarder.sendKey(0x91); return true // Up
        case 125: forwarder.sendKey(0x11); return true // Down
        case 123: forwarder.sendKey(0x9D); return true // Left
        case 124: forwarder.sendKey(0x1D); return true // Right
        case 115: // Home
            if event.modifierFlags.contains(.shift) {
                forwarder.sendKey(0x93) // CLR
            } else {
                forwarder.sendKey(0x13) // HOME
            }
            return true
        default: break
        }

        if let chars = event.characters, !chars.isEmpty {
            forwarder.handleKeyPress(chars)
            return true
        }

        return false
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    // MARK: - Split View Setup

    private func setupSplitView() {
        // Sidebar (left) — only in Toolbox mode
        if connection.connectionMode == .toolbox {
            let sidebarVC = SidebarViewController(connection: connection)
            sidebarVC.delegate = self
            let sidebarItem = NSSplitViewItem(sidebarWithViewController: sidebarVC)
            sidebarItem.minimumThickness = 180
            // Set holding priority high so it doesn't auto-collapse on resize
            sidebarItem.holdingPriority = .defaultHigh
            splitViewController.addSplitViewItem(sidebarItem)
        }

        // Video (center) — always present
        videoViewController = VideoViewController(connection: connection)
        let videoItem = NSSplitViewItem(viewController: videoViewController)
        videoItem.minimumThickness = 384
        splitViewController.addSplitViewItem(videoItem)
    }

    // MARK: - Toolbar Setup

    private func setupToolbar() {
        guard connection.connectionMode == .toolbox else { return }

        let toolbar = NSToolbar(identifier: "DeviceToolbar")
        toolbar.displayMode = .iconOnly
        toolbar.delegate = self
        window?.toolbar = toolbar
    }

    // MARK: - NSToolbarDelegate

    func toolbarDefaultItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
        var items: [NSToolbarItem.Identifier] = [
            .toggleSidebar,
            .sidebarTrackingSeparator,
            .startStopStreams, .runFile, .keyboard,
            .flexibleSpace,
            .resetMachine, .rebootMachine, .powerOff, .menuButton,
        ]

        // Add inspector tracking separator when any inspector is open
        if inspectorItem != nil {
            items.append(.inspectorTrackingSeparator)

            // Close button first (far left of inspector area)
            items.append(.closeInspector)

            // Tool-specific items pushed right
            items.append(.flexibleSpace)
            switch connection.selectedSidebarItem {
            case .basicScratchpad:
                items.append(contentsOf: [.basicSpecialCodes, .basicFileMenu, .basicRun])
            default:
                break
            }
        }

        return items
    }

    func toolbarAllowedItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
        [
            .toggleSidebar, .sidebarTrackingSeparator,
            .startStopStreams, .runFile, .keyboard,
            .flexibleSpace,
            .resetMachine, .rebootMachine, .powerOff, .menuButton,
            .inspectorTrackingSeparator,
            .basicSpecialCodes, .basicFileMenu, .basicRun, .closeInspector,
        ]
    }

    func toolbar(_ toolbar: NSToolbar, itemForItemIdentifier itemIdentifier: NSToolbarItem.Identifier, willBeInsertedIntoToolbar flag: Bool) -> NSToolbarItem? {
        switch itemIdentifier {
        case .inspectorTrackingSeparator:
            let dividerIndex = splitViewController.splitViewItems.count - 2
            return NSTrackingSeparatorToolbarItem(identifier: itemIdentifier, splitView: splitViewController.splitView, dividerIndex: max(0, dividerIndex))

        case .startStopStreams:
            if connection.streamsActive {
                return makeToolbarItem(itemIdentifier, label: "Stop Streams", icon: "stop.circle.fill", action: #selector(stopStreams))
            } else {
                return makeToolbarItem(itemIdentifier, label: "Start Streams", icon: "play.circle.fill", action: #selector(startStreams))
            }
        case .runFile:
            return makeToolbarItem(itemIdentifier, label: "Run File", icon: "doc.fill.badge.plus", action: #selector(runFileTapped))
        case .keyboard:
            let isOn = connection.keyboardForwarder?.isEnabled == true
            return makeToolbarItem(itemIdentifier, label: "Keyboard", icon: isOn ? "keyboard.fill" : "keyboard", action: #selector(toggleKeyboard))
        case .resetMachine:
            return makeToolbarItem(itemIdentifier, label: "Reset", icon: "arrow.counterclockwise", action: #selector(resetTapped))
        case .rebootMachine:
            return makeToolbarItem(itemIdentifier, label: "Reboot", icon: "arrow.trianglehead.2.clockwise", action: #selector(rebootTapped))
        case .powerOff:
            return makeToolbarItem(itemIdentifier, label: "Power Off", icon: "power", action: #selector(powerOffTapped))
        case .menuButton:
            return makeToolbarItem(itemIdentifier, label: "Menu", icon: "line.3.horizontal", action: #selector(menuTapped))
        case .basicSpecialCodes:
            let isOn = basicScratchpadVC?.isSpecialCodesVisible == true
            return makeToolbarItem(itemIdentifier, label: "Special Codes", icon: isOn ? "character.bubble.fill" : "character.bubble", action: #selector(basicToggleSpecialCodes))
        case .basicFileMenu:
            let item = NSMenuToolbarItem(itemIdentifier: itemIdentifier)
            item.label = "File"
            item.toolTip = "File"
            if let image = NSImage(systemSymbolName: "doc", accessibilityDescription: "File") {
                item.image = image
            }
            item.showsIndicator = true

            let menu = NSMenu()
            let samplesItem = NSMenuItem(title: "Samples", action: nil, keyEquivalent: "")
            let samplesMenu = NSMenu()
            for sample in BASICSamples.all {
                let menuItem = NSMenuItem(title: sample.name, action: #selector(basicLoadSample(_:)), keyEquivalent: "")
                menuItem.target = self
                menuItem.representedObject = sample
                samplesMenu.addItem(menuItem)
            }
            samplesItem.submenu = samplesMenu
            menu.addItem(samplesItem)
            menu.addItem(.separator())
            let openItem = NSMenuItem(title: "Open…", action: #selector(basicOpenFile), keyEquivalent: "")
            openItem.target = self
            menu.addItem(openItem)
            let saveItem = NSMenuItem(title: "Save As…", action: #selector(basicSaveFile), keyEquivalent: "")
            saveItem.target = self
            menu.addItem(saveItem)
            item.menu = menu
            return item
        case .basicRun:
            return makeToolbarItem(itemIdentifier, label: "Run", icon: "play.fill", action: #selector(basicUploadAndRun))
        case .closeInspector:
            return makeToolbarItem(itemIdentifier, label: "Hide Inspector", icon: "sidebar.trailing", action: #selector(closeInspector))
        default:
            return nil
        }
    }

    private func makeToolbarItem(_ identifier: NSToolbarItem.Identifier, label: String, icon: String, action: Selector) -> NSToolbarItem {
        let item = NSToolbarItem(itemIdentifier: identifier)
        item.label = label
        item.toolTip = label
        item.target = self
        item.action = action
        item.isBordered = true
        if let image = NSImage(systemSymbolName: icon, accessibilityDescription: label) {
            item.image = image
        }
        return item
    }

    func refreshToolbarItem(_ identifier: NSToolbarItem.Identifier) {
        guard let toolbar = window?.toolbar,
              let index = toolbar.items.firstIndex(where: { $0.itemIdentifier == identifier }) else { return }
        toolbar.removeItem(at: index)
        toolbar.insertItem(withItemIdentifier: identifier, at: index)
    }

    // MARK: - Toolbar Actions

    @objc private func startStreams() {
        connection.startStreams()
        refreshToolbarItem(.startStopStreams)
    }

    @objc private func stopStreams() {
        connection.stopStreams()
        refreshToolbarItem(.startStopStreams)
    }

    @objc private func runFileTapped() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = ["sid", "prg", "crt"].compactMap { UTType(filenameExtension: $0) }
        panel.allowsMultipleSelection = false
        if panel.runModal() == .OK, let url = panel.url,
           let data = try? Data(contentsOf: url) {
            let ext = url.pathExtension.lowercased()
            let type: RunnerType = switch ext {
            case "sid": .sid
            case "crt": .crt
            default: .prg
            }
            connection.runFile(type: type, data: data)
        }
    }

    @objc private func toggleKeyboard() {
        guard let forwarder = connection.keyboardForwarder else { return }
        if forwarder.isEnabled {
            forwarder.isEnabled = false
            videoViewController.setKeyboardStripVisible(false)
        } else if UserDefaults.standard.bool(forKey: "c64_keyboard_info_shown") {
            forwarder.isEnabled = true
            videoViewController.setKeyboardStripVisible(true)
        } else {
            let alert = NSAlert()
            alert.messageText = "Keyboard Forwarding"
            alert.informativeText = "Keyboard input is forwarded to the C64 via the KERNAL keyboard buffer. This works with BASIC and programs that read input through the KERNAL, but does not work in the Ultimate menu or with most games that read the keyboard hardware directly."
            alert.addButton(withTitle: "Enable")
            alert.addButton(withTitle: "Cancel")
            if alert.runModal() == .alertFirstButtonReturn {
                UserDefaults.standard.set(true, forKey: "c64_keyboard_info_shown")
                forwarder.isEnabled = true
                videoViewController.setKeyboardStripVisible(true)
            }
        }
        refreshToolbarItem(.keyboard)
    }


    @objc private func resetTapped() {
        confirmAction("Reset Machine?", "This will reset the C64.") {
            self.connection.machineAction(.reset)
        }
    }

    @objc private func rebootTapped() {
        confirmAction("Reboot Machine?", "This will reboot the C64 Ultimate.") {
            self.connection.machineAction(.reboot)
        }
    }

    @objc private func powerOffTapped() {
        confirmAction("Power Off Machine?", "This will power off the C64 Ultimate.") {
            self.connection.machineAction(.powerOff)
        }
    }

    @objc private func menuTapped() {
        connection.machineAction(.menuButton)
    }

    // MARK: - BASIC Inspector Toolbar Actions

    private var basicScratchpadVC: BASICScratchpadViewController? {
        inspectorItem?.viewController as? BASICScratchpadViewController
    }

    @objc private func basicToggleSpecialCodes() {
        basicScratchpadVC?.toggleSpecialCodes()
        refreshToolbarItem(.basicSpecialCodes)
    }

    @objc private func basicShowFileMenu(_ sender: Any?) {
        // The file menu is handled through individual menu items
        basicScratchpadVC?.showFileMenu(from: sender)
    }

    @objc private func basicLoadSample(_ sender: NSMenuItem) {
        guard let sample = sender.representedObject as? BASICSample else { return }
        basicScratchpadVC?.loadSample(sample)
    }

    @objc private func basicOpenFile() {
        basicScratchpadVC?.openFile()
    }

    @objc private func basicSaveFile() {
        basicScratchpadVC?.saveFile()
    }

    @objc private func basicUploadAndRun() {
        basicScratchpadVC?.uploadAndRun()
    }

    @objc private func closeInspector() {
        closeCurrentInspector()
        sidebarVC?.deselectAll()
    }

    private var sidebarVC: SidebarViewController? {
        splitViewController.splitViewItems.first?.viewController as? SidebarViewController
    }

    // MARK: - Helpers

    private func rebuildToolbar() {
        guard let toolbar = window?.toolbar else { return }
        // Remove all items and re-add from default identifiers
        while toolbar.items.count > 0 {
            toolbar.removeItem(at: 0)
        }
        for identifier in toolbarDefaultItemIdentifiers(toolbar) {
            toolbar.insertItem(withItemIdentifier: identifier, at: toolbar.items.count)
        }
    }

    // MARK: - Menu Actions

    @objc func disconnectDevice() {
        window?.close()
    }

    @objc func volumeUp() {
        connection.volume = min(1.0, connection.volume + 0.1)
        connection.isMuted = false
    }

    @objc func volumeDown() {
        connection.volume = max(0.0, connection.volume - 0.1)
        connection.isMuted = false
    }

    @objc func toggleMute() {
        connection.isMuted.toggle()
        connection.audioPlayer.volume = connection.isMuted ? 0.0 : connection.volume
    }

    @objc func takeScreenshot() {
        connection.takeScreenshot()
    }

    @objc func toggleRecording() {
        connection.toggleRecording()
    }

    // MARK: - Helpers

    private func confirmAction(_ title: String, _ message: String, action: @escaping () -> Void) {
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = message
        alert.alertStyle = .warning
        alert.addButton(withTitle: "OK")
        alert.addButton(withTitle: "Cancel")
        guard let window else { return }
        alert.beginSheetModal(for: window) { response in
            if response == .alertFirstButtonReturn {
                action()
            }
        }
    }
}

// MARK: - NSWindowDelegate

extension DeviceWindowController: NSWindowDelegate {
    func windowWillClose(_ notification: Notification) {
        connection.disconnect()
        delegate?.deviceWindowDidClose(self)
    }
}

// MARK: - SidebarViewControllerDelegate

extension DeviceWindowController: SidebarViewControllerDelegate {
    func closeCurrentInspector() {
        connection.selectedSidebarItem = nil
        if let existing = inspectorItem {
            splitViewController.removeSplitViewItem(existing)
            inspectorItem = nil
        }
        rebuildToolbar()
    }

    func sidebarDidSelectItem(_ item: SidebarItem) {
        connection.selectedSidebarItem = item

        // Remove existing inspector if any
        if let existing = inspectorItem {
            splitViewController.removeSplitViewItem(existing)
            inspectorItem = nil
        }

        // Add inspector for items that need one
        if item.hasInspector && item.isImplemented {
            let viewController: NSViewController
            switch item {
            case .crtSettings:
                viewController = CRTSettingsViewController(connection: connection)
            case .audioSettings:
                viewController = AudioSettingsViewController(connection: connection)
            case .basicScratchpad:
                viewController = BASICScratchpadViewController(connection: connection)
            default:
                return // not yet implemented or no inspector
            }

            let splitItem = NSSplitViewItem(inspectorWithViewController: viewController)
            splitItem.minimumThickness = 280
            splitItem.maximumThickness = 500
            splitItem.canCollapse = true
            splitItem.automaticallyAdjustsSafeAreaInsets = true
            splitViewController.addSplitViewItem(splitItem)
            inspectorItem = splitItem
        }

        rebuildToolbar()
    }
}

// MARK: - Toolbar Item Identifiers

extension NSToolbarItem.Identifier {
    static let startStopStreams = NSToolbarItem.Identifier("startStopStreams")
    static let runFile = NSToolbarItem.Identifier("runFile")
    static let keyboard = NSToolbarItem.Identifier("keyboard")
    static let resetMachine = NSToolbarItem.Identifier("resetMachine")
    static let rebootMachine = NSToolbarItem.Identifier("rebootMachine")
    static let powerOff = NSToolbarItem.Identifier("powerOff")
    static let menuButton = NSToolbarItem.Identifier("menuButton")
    static let inspectorTrackingSeparator = NSToolbarItem.Identifier("inspectorTrackingSeparator")
    static let basicSpecialCodes = NSToolbarItem.Identifier("basicSpecialCodes")
    static let basicFileMenu = NSToolbarItem.Identifier("basicFileMenu")
    static let basicRun = NSToolbarItem.Identifier("basicRun")
    static let closeInspector = NSToolbarItem.Identifier("closeInspector")
}
