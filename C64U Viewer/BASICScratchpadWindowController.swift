// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.

import AppKit
internal import UniformTypeIdentifiers

final class BASICScratchpadWindowController: NSWindowController, NSWindowDelegate {
    let scratchpadDocument = BASICScratchpadDocument()
    private var scratchpadVC: BASICScratchpadViewController!
    private var devicePicker: NSPopUpButton!
    private var runButton: NSButton!
    private var isUploading = false

    init() {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 800, height: 600),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = "BASIC Scratchpad"
        window.minSize = NSSize(width: 400, height: 300)
        window.center()
        window.isReleasedWhenClosed = false

        super.init(window: window)
        window.delegate = self

        setupUI()
        refreshDevicePicker()

        window.setContentSize(NSSize(width: 800, height: 600))
        window.center()

        NotificationCenter.default.addObserver(self, selector: #selector(deviceListChanged), name: .deviceListDidChange, object: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    deinit {
        NotificationCenter.default.removeObserver(self)
    }

    // MARK: - UI Setup

    private func setupUI() {
        scratchpadVC = BASICScratchpadViewController(document: scratchpadDocument)
        window?.contentViewController = scratchpadVC

        scratchpadVC.onTitleChanged = { [weak self] _ in
            self?.updateWindowTitle()
        }

        setupToolbar()
        updateWindowTitle()
    }

    private func setupToolbar() {
        let toolbar = NSToolbar(identifier: "BASICScratchpadToolbar")
        toolbar.delegate = self
        toolbar.displayMode = .iconOnly
        window?.toolbar = toolbar
    }

    private func updateWindowTitle() {
        let filename = scratchpadDocument.displayName
        let dirty = scratchpadDocument.isDirty ? " *" : ""
        window?.title = "BASIC Scratchpad — \(filename)\(dirty)"
        window?.representedURL = scratchpadDocument.fileURL
    }

    // MARK: - Device Picker

    @objc private func deviceListChanged() {
        refreshDevicePicker()
    }

    private func refreshDevicePicker() {
        guard let picker = devicePicker else { return }

        let previousTag = picker.selectedTag()
        picker.removeAllItems()

        picker.addItem(withTitle: "No Target")
        picker.lastItem?.tag = -1

        let appDelegate = NSApp.delegate as? AppDelegate
        let connections = appDelegate?.toolboxConnections() ?? []

        for (index, entry) in connections.enumerated() {
            picker.addItem(withTitle: entry.label)
            picker.lastItem?.tag = index
            picker.lastItem?.representedObject = entry.connection
        }

        // Restore previous selection if still available
        if previousTag >= 0,
           let item = picker.menu?.item(withTag: previousTag),
           item.representedObject != nil {
            picker.select(item)
        } else {
            picker.selectItem(at: 0)
        }

        updateRunButton()
    }

    private func selectedConnection() -> C64Connection? {
        devicePicker?.selectedItem?.representedObject as? C64Connection
    }

    private func updateRunButton() {
        runButton?.isEnabled = selectedConnection() != nil && !isUploading
    }

    // MARK: - Actions

    @objc private func devicePickerChanged(_ sender: NSPopUpButton) {
        updateRunButton()
    }

    @objc private func uploadAndRun() {
        guard let connection = selectedConnection(),
              let client = connection.apiClient,
              connection.isConnected else {
            scratchpadVC.showError("Device not connected")
            refreshDevicePicker()
            return
        }
        guard !isUploading else { return }

        let code = scratchpadDocument.code
        scratchpadVC.clearError()
        isUploading = true
        updateRunButton()

        Task {
            do {
                let (data, endAddr) = try BASICTokenizer.tokenize(program: code)
                try await client.writeMem(address: 0x0801, data: data)

                let ptrData = Data([UInt8(endAddr & 0xFF), UInt8(endAddr >> 8)])
                try await client.writeMem(address: 0x002D, data: ptrData)

                // Auto-run: R, U, N, RETURN
                let runBytes: [UInt8] = [0x52, 0x55, 0x4E, 0x0D]
                try await client.writeMem(address: 0x0277, data: Data(runBytes))
                try await client.writeMem(address: 0x00C6, data: Data([UInt8(runBytes.count)]))
            } catch {
                scratchpadVC.showError(error.localizedDescription)
            }
            isUploading = false
            updateRunButton()
        }
    }

    @objc private func toggleSpecialCodes() {
        scratchpadVC.toggleSpecialCodes()
    }

    // MARK: - File Menu

    @objc private func showFileMenu(_ sender: NSButton) {
        guard let menu = sender.menu else { return }
        menu.popUp(positioning: nil, at: NSPoint(x: 0, y: sender.bounds.height), in: sender)
    }

    private func createFileMenuButton() -> NSButton {
        let button = NSButton(image: NSImage(systemSymbolName: "doc", accessibilityDescription: "File")!, target: nil, action: nil)
        button.bezelStyle = .toolbar

        let menu = NSMenu()
        menu.addItem(withTitle: "New", action: #selector(BASICScratchpadViewController.newFile), keyEquivalent: "").target = scratchpadVC
        menu.addItem(withTitle: "Open…", action: #selector(BASICScratchpadViewController.openFile), keyEquivalent: "").target = scratchpadVC
        menu.addItem(.separator())
        menu.addItem(withTitle: "Save", action: #selector(BASICScratchpadViewController.saveFile), keyEquivalent: "").target = scratchpadVC
        menu.addItem(withTitle: "Save As…", action: #selector(BASICScratchpadViewController.saveFileAs), keyEquivalent: "").target = scratchpadVC
        menu.addItem(.separator())

        let samplesItem = NSMenuItem(title: "Samples", action: nil, keyEquivalent: "")
        let samplesMenu = NSMenu()
        for sample in BASICSamples.all {
            let item = NSMenuItem(title: sample.name, action: #selector(BASICScratchpadViewController.loadSampleFromMenu(_:)), keyEquivalent: "")
            item.target = scratchpadVC
            item.representedObject = sample
            samplesMenu.addItem(item)
        }
        samplesItem.submenu = samplesMenu
        menu.addItem(samplesItem)

        button.menu = menu
        button.target = self
        button.action = #selector(showFileMenu(_:))

        return button
    }

    // MARK: - Window Delegate

    func windowShouldClose(_ sender: NSWindow) -> Bool {
        guard scratchpadDocument.isDirty else { return true }

        let alert = NSAlert()
        alert.messageText = "Save changes?"
        alert.informativeText = "Your changes will be lost if you don't save them."
        alert.addButton(withTitle: "Save")
        alert.addButton(withTitle: "Don't Save")
        alert.addButton(withTitle: "Cancel")

        alert.beginSheetModal(for: sender) { [weak self] response in
            guard let self else { return }
            switch response {
            case .alertFirstButtonReturn:
                self.scratchpadVC.saveFile()
                sender.close()
            case .alertSecondButtonReturn:
                sender.close()
            default:
                break
            }
        }
        return false
    }

    func windowWillClose(_ notification: Notification) {
        (NSApp.delegate as? AppDelegate)?.scratchpadWindowDidClose(self)
    }
}

// MARK: - Toolbar

extension BASICScratchpadWindowController: NSToolbarDelegate {
    private enum ToolbarItem: String, CaseIterable {
        case fileMenu
        case specialCodes
        case flexibleSpace
        case devicePicker
        case run
    }

    func toolbar(_ toolbar: NSToolbar, itemForItemIdentifier itemIdentifier: NSToolbarItem.Identifier, willBeInsertedIntoToolbar flag: Bool) -> NSToolbarItem? {
        let id = ToolbarItem(rawValue: itemIdentifier.rawValue)

        switch id {
        case .devicePicker:
            devicePicker = NSPopUpButton(frame: .zero, pullsDown: false)
            devicePicker.controlSize = .small
            devicePicker.target = self
            devicePicker.action = #selector(devicePickerChanged(_:))
            devicePicker.widthAnchor.constraint(greaterThanOrEqualToConstant: 140).isActive = true
            devicePicker.widthAnchor.constraint(lessThanOrEqualToConstant: 220).isActive = true
            refreshDevicePicker()
            let item = NSToolbarItem(itemIdentifier: itemIdentifier)
            item.view = devicePicker
            item.label = "Target Device"
            return item

        case .flexibleSpace:
            return nil

        case .specialCodes:
            let item = NSToolbarItem(itemIdentifier: itemIdentifier)
            let button = NSButton(image: NSImage(systemSymbolName: "character.bubble", accessibilityDescription: "Special Codes")!, target: self, action: #selector(toggleSpecialCodes))
            button.bezelStyle = .toolbar
            item.view = button
            item.label = "Special Codes"
            return item

        case .fileMenu:
            let item = NSToolbarItem(itemIdentifier: itemIdentifier)
            item.view = createFileMenuButton()
            item.label = "File"
            return item

        case .run:
            let item = NSToolbarItem(itemIdentifier: itemIdentifier)
            runButton = NSButton(image: NSImage(systemSymbolName: "play.fill", accessibilityDescription: "Run")!, target: self, action: #selector(uploadAndRun))
            runButton.bezelStyle = .toolbar
            updateRunButton()
            item.view = runButton
            item.label = "Run"
            return item

        case nil:
            return nil
        }
    }

    func toolbarDefaultItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
        [
            NSToolbarItem.Identifier(ToolbarItem.fileMenu.rawValue),
            NSToolbarItem.Identifier(ToolbarItem.specialCodes.rawValue),
            .flexibleSpace,
            NSToolbarItem.Identifier(ToolbarItem.devicePicker.rawValue),
            NSToolbarItem.Identifier(ToolbarItem.run.rawValue),
        ]
    }

    func toolbarAllowedItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
        toolbarDefaultItemIdentifiers(toolbar)
    }
}

// MARK: - Notification Name

extension Notification.Name {
    static let deviceListDidChange = Notification.Name("DeviceListDidChange")
}
