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
    private let centerSplitViewController = NSSplitViewController()
    private var videoViewController: VideoViewController!
    private var inspectorItem: NSSplitViewItem?
    private var debugPanelItem: NSSplitViewItem?

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
            self?.connection.machineAction(.menuButton)
        }

        restoreKeyboardState()
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
        NotificationCenter.default.addObserver(self, selector: #selector(splitViewDidResize(_:)),
                                               name: NSSplitView.didResizeSubviewsNotification,
                                               object: splitViewController.splitView)

        // Sidebar (left) — File Manager in Toolbox mode
        if connection.connectionMode == .toolbox {
            let fileManagerVC = FileManagerViewController(connection: connection)
            let sidebarItem = NSSplitViewItem(sidebarWithViewController: fileManagerVC)
            sidebarItem.minimumThickness = 300
            sidebarItem.isCollapsed = true
            splitViewController.addSplitViewItem(sidebarItem)
        }

        // Center area — vertical split: video (top) + debug panel (bottom, toggleable)
        centerSplitViewController.splitView.isVertical = false

        videoViewController = VideoViewController(connection: connection)
        let videoItem = NSSplitViewItem(viewController: videoViewController)
        videoItem.minimumThickness = 200
        centerSplitViewController.addSplitViewItem(videoItem)

        // Debug panel (bottom) — created but collapsed by default
        let debugPanel = DebugPanelViewController(connection: connection)
        debugPanel.view.setFrameSize(NSSize(width: debugPanel.view.frame.width, height: 335))
        let debugItem = NSSplitViewItem(viewController: debugPanel)
        debugItem.minimumThickness = 335
        debugItem.canCollapse = true
        debugItem.isCollapsed = true
        centerSplitViewController.addSplitViewItem(debugItem)
        debugPanelItem = debugItem

        let centerItem = NSSplitViewItem(viewController: centerSplitViewController)
        centerItem.minimumThickness = 384
        splitViewController.addSplitViewItem(centerItem)

        // Inspector (right) — persistent, starts collapsed
        let inspectorContainer = InspectorContainerViewController(connection: connection)
        let inspItem = NSSplitViewItem(inspectorWithViewController: inspectorContainer)
        inspItem.minimumThickness = 350
        inspItem.maximumThickness = 700
        inspItem.canCollapse = true
        inspItem.isCollapsed = true
        inspItem.automaticallyAdjustsSafeAreaInsets = true
        splitViewController.addSplitViewItem(inspItem)
        inspectorItem = inspItem
    }

    // MARK: - Toolbar Setup

    private func setupToolbar() {
        let toolbar = NSToolbar(identifier: "DeviceToolbar")
        toolbar.displayMode = .iconOnly
        toolbar.delegate = self
        window?.toolbar = toolbar
    }

    // MARK: - NSToolbarDelegate

    func toolbarDefaultItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
        var items: [NSToolbarItem.Identifier] = []

        if connection.connectionMode == .toolbox {
            items.append(contentsOf: [
                .toggleSidebar,
                .sidebarTrackingSeparator,
                .flexibleSpace,
                .pauseResume, .resetMachine, .rebootMachine, .powerOff,
                .flexibleSpace,
                .newScratchpad, .runFile,
                .flexibleSpace,
                .keyboard,
                .flexibleSpace,
                .takeScreenshot, .toggleRecording,
                .flexibleSpace,
                .toggleDebugPanel,
            ])
        }

        if connection.connectionMode != .toolbox {
            items.append(contentsOf: [
                .takeScreenshot, .toggleRecording,
            ])
        }

        items.append(contentsOf: [
            .inspectorTrackingSeparator,
            .flexibleSpace,
            .toggleInspector,
        ])

        return items
    }

    func toolbarAllowedItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
        [
            .toggleSidebar, .sidebarTrackingSeparator,
            .newScratchpad, .runFile, .keyboard,
            .flexibleSpace,
            .pauseResume, .resetMachine, .rebootMachine, .powerOff,
            .toggleDebugPanel, .takeScreenshot, .toggleRecording,
            .inspectorTrackingSeparator, .toggleInspector,
        ]
    }

    func toolbar(_ toolbar: NSToolbar, itemForItemIdentifier itemIdentifier: NSToolbarItem.Identifier, willBeInsertedIntoToolbar flag: Bool) -> NSToolbarItem? {
        switch itemIdentifier {
        case .inspectorTrackingSeparator:
            let dividerIndex = splitViewController.splitViewItems.count - 2
            return NSTrackingSeparatorToolbarItem(identifier: itemIdentifier, splitView: splitViewController.splitView, dividerIndex: max(0, dividerIndex))
        case .newScratchpad:
            return makeToolbarItem(itemIdentifier, label: "New Scratchpad", icon: "square.and.pencil", action: #selector(newScratchpadTapped))
        case .runFile:
            return makeToolbarItem(itemIdentifier, label: "Run File", icon: "document.badge.arrow.up.fill", action: #selector(runFileTapped))
        case .keyboard:
            let isOn = connection.keyboardForwarder?.isEnabled == true
            return makeToolbarItem(itemIdentifier, label: "Send Keyboard", icon: isOn ? "keyboard.fill" : "keyboard", action: #selector(toggleKeyboard))
        case .resetMachine:
            return makeToolbarItem(itemIdentifier, label: "Reset", icon: "arrow.counterclockwise", action: #selector(resetTapped))
        case .rebootMachine:
            return makeToolbarItem(itemIdentifier, label: "Reboot", icon: "arrow.trianglehead.2.clockwise", action: #selector(rebootTapped))
        case .powerOff:
            return makeToolbarItem(itemIdentifier, label: "Power Off", icon: "power", action: #selector(powerOffTapped))
        case .pauseResume:
            if connection.isPaused {
                return makeToolbarItem(itemIdentifier, label: "Resume", icon: "play", action: #selector(resumeMachine))
            } else {
                return makeToolbarItem(itemIdentifier, label: "Pause", icon: "pause", action: #selector(pauseMachine))
            }
        case .toggleDebugPanel:
            let isVisible = debugPanelItem?.isCollapsed == false
            return makeToolbarItem(itemIdentifier, label: "Debug", icon: isVisible ? "apple.terminal.fill" : "apple.terminal", action: #selector(toggleDebugPanel))
        case .toggleInspector:
            let isVisible = inspectorItem?.isCollapsed == false
            return makeToolbarItem(itemIdentifier, label: "Inspector", icon: isVisible ? "sidebar.trailing" : "sidebar.trailing", action: #selector(toggleInspector))
        case .takeScreenshot:
            return makeToolbarItem(itemIdentifier, label: "Screenshot", icon: "camera.fill", action: #selector(takeScreenshot))
        case .toggleRecording:
            if connection.isRecording {
                return makeToolbarItem(itemIdentifier, label: "Stop Recording", icon: "stop.circle.fill", action: #selector(toggleRecording))
            } else {
                return makeToolbarItem(itemIdentifier, label: "Record", icon: "inset.filled.rectangle.badge.record", action: #selector(toggleRecording))
            }
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

    @objc private func newScratchpadTapped() {
        (NSApp.delegate as? AppDelegate)?.newBASICScratchpad()
    }

    @objc private func runFileTapped() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = ["sid", "mod", "prg", "crt"].compactMap { UTType(filenameExtension: $0) }
        panel.allowsMultipleSelection = false
        if panel.runModal() == .OK, let url = panel.url,
           let data = try? Data(contentsOf: url) {
            let ext = url.pathExtension.lowercased()
            let type: RunnerType = switch ext {
            case "sid": .sid
            case "mod": .mod
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
            saveKeyboardState(enabled: false)
        } else if UserDefaults.standard.bool(forKey: "c64_keyboard_info_shown") {
            forwarder.isEnabled = true
            videoViewController.setKeyboardStripVisible(true)
            saveKeyboardState(enabled: true)
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
                saveKeyboardState(enabled: true)
            }
        }
        refreshToolbarItem(.keyboard)
    }

    private var keyboardStateKey: String? {
        guard let client = connection.apiClient else { return nil }
        return "keyboard_enabled-\(client.baseURL)"
    }

    private func saveKeyboardState(enabled: Bool) {
        guard let key = keyboardStateKey else { return }
        UserDefaults.standard.set(enabled, forKey: key)
    }

    private func restoreKeyboardState() {
        guard let key = keyboardStateKey,
              UserDefaults.standard.bool(forKey: "c64_keyboard_info_shown"),
              UserDefaults.standard.bool(forKey: key),
              let forwarder = connection.keyboardForwarder else { return }
        forwarder.isEnabled = true
        videoViewController.setKeyboardStripVisible(true)
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

    @objc private func pauseMachine() {
        connection.machineAction(.pause) { [weak self] in
            self?.refreshToolbarItem(.pauseResume)
        }
    }

    @objc private func resumeMachine() {
        connection.machineAction(.resume) { [weak self] in
            self?.refreshToolbarItem(.pauseResume)
        }
    }

    // MARK: - Inspector Toggle

    @objc private func toggleInspector() {
        guard let inspectorItem else { return }
        inspectorItem.animator().isCollapsed.toggle()
    }

    // MARK: - Debug Panel Toggle

    @objc private func toggleDebugPanel() {
        guard let debugPanelItem else { return }
        debugPanelItem.animator().isCollapsed.toggle()

        // Set initial height when opening
        refreshToolbarItem(.toggleDebugPanel)
    }

    // MARK: - Helpers


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
        refreshToolbarItem(.toggleRecording)
    }

    // MARK: - Split View Resize Tracking

    @objc private func splitViewDidResize(_ notification: Notification) {
        guard let inspectorItem else { return }
        let width = inspectorItem.viewController.view.frame.width
        if width > 0 {
            UserDefaults.standard.set(Double(width), forKey: "c64_inspector_width")
        }
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

    func window(_ window: NSWindow, willUseFullScreenPresentationOptions proposedOptions: NSApplication.PresentationOptions = []) -> NSApplication.PresentationOptions {
        return proposedOptions.union([.autoHideToolbar, .autoHideMenuBar, .autoHideDock])
    }
}


// MARK: - Toolbar Item Identifiers

extension NSToolbarItem.Identifier {
    static let runFile = NSToolbarItem.Identifier("runFile")
    static let keyboard = NSToolbarItem.Identifier("keyboard")
    static let resetMachine = NSToolbarItem.Identifier("resetMachine")
    static let rebootMachine = NSToolbarItem.Identifier("rebootMachine")
    static let powerOff = NSToolbarItem.Identifier("powerOff")
    static let pauseResume = NSToolbarItem.Identifier("pauseResume")
    static let toggleDebugPanel = NSToolbarItem.Identifier("toggleDebugPanel")
    static let toggleInspector = NSToolbarItem.Identifier("toggleInspector")
    static let inspectorTrackingSeparator = NSToolbarItem.Identifier("inspectorTrackingSeparator")
    static let takeScreenshot = NSToolbarItem.Identifier("takeScreenshot")
    static let toggleRecording = NSToolbarItem.Identifier("toggleRecording")
    static let newScratchpad = NSToolbarItem.Identifier("newScratchpad")
}
