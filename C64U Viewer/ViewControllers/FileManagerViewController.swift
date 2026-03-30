// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.

import AppKit
internal import UniformTypeIdentifiers

final class FileManagerViewController: NSViewController, NSTableViewDataSource, NSTableViewDelegate, NSMenuDelegate {
    let connection: C64Connection
    private var ftpClient: FTPClient?
    private let tableView = NSTableView()
    private var pathControl: NSPathControl!
    private var statusLabel: NSTextField!
    private var progressIndicator: NSProgressIndicator!

    private var currentPath = "/"
    private var entries: [FTPFileEntry] = []
    private var isAtRoot: Bool { currentPath == "/" }

    init(connection: C64Connection) {
        self.connection = connection
        super.init(nibName: nil, bundle: nil)
        self.title = "File Manager"
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    override func loadView() {
        let container = BackgroundView()
        container.backgroundColor = .controlBackgroundColor

        // Path bar at top
        pathControl = NSPathControl()
        pathControl.pathStyle = .standard
        pathControl.isEditable = false
        pathControl.backgroundColor = .clear
        pathControl.translatesAutoresizingMaskIntoConstraints = false
        pathControl.target = self
        pathControl.action = #selector(pathClicked(_:))

        // Table view for file listing
        let scrollView = NSScrollView()
        scrollView.hasVerticalScroller = true
        scrollView.autohidesScrollers = true
        scrollView.translatesAutoresizingMaskIntoConstraints = false

        let nameColumn = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("name"))
        nameColumn.title = "Name"
        nameColumn.resizingMask = .autoresizingMask
        tableView.addTableColumn(nameColumn)

        let sizeColumn = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("size"))
        sizeColumn.title = "Size"
        sizeColumn.width = 70
        sizeColumn.minWidth = 60
        sizeColumn.maxWidth = 100
        sizeColumn.resizingMask = []
        tableView.addTableColumn(sizeColumn)

        tableView.columnAutoresizingStyle = .firstColumnOnlyAutoresizingStyle
        tableView.dataSource = self
        tableView.delegate = self
        tableView.rowSizeStyle = .default
        tableView.allowsMultipleSelection = true
        tableView.doubleAction = #selector(doubleClickedRow)
        tableView.target = self

        // Keyboard shortcuts
        NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self, self.view.window?.firstResponder === self.tableView else { return event }
            switch event.keyCode {
            case 51: // Delete/Backspace
                self.deleteSelected()
                return nil
            case 36: // Return/Enter — open folder or run file
                self.doubleClickedRow()
                return nil
            default:
                return event
            }
        }

        // Register for drag and drop from Finder
        tableView.registerForDraggedTypes([.fileURL])
        tableView.setDraggingSourceOperationMask(.copy, forLocal: false)

        scrollView.documentView = tableView

        // Status bar
        statusLabel = NSTextField(labelWithString: "Connecting...")
        statusLabel.font = .systemFont(ofSize: 11)
        statusLabel.textColor = .secondaryLabelColor
        statusLabel.translatesAutoresizingMaskIntoConstraints = false

        progressIndicator = NSProgressIndicator()
        progressIndicator.style = .bar
        progressIndicator.isIndeterminate = false
        progressIndicator.isHidden = true
        progressIndicator.translatesAutoresizingMaskIntoConstraints = false

        let statusBar = NSStackView(views: [statusLabel, progressIndicator])
        statusBar.orientation = .horizontal
        statusBar.spacing = 8
        statusBar.edgeInsets = NSEdgeInsets(top: 4, left: 8, bottom: 4, right: 8)
        statusBar.translatesAutoresizingMaskIntoConstraints = false

        container.addSubview(pathControl)
        container.addSubview(scrollView)
        container.addSubview(statusBar)

        NSLayoutConstraint.activate([
            pathControl.topAnchor.constraint(equalTo: container.safeAreaLayoutGuide.topAnchor, constant: 4),
            pathControl.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 8),
            pathControl.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -8),
            pathControl.heightAnchor.constraint(equalToConstant: 24),

            scrollView.topAnchor.constraint(equalTo: pathControl.bottomAnchor, constant: 4),
            scrollView.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            scrollView.bottomAnchor.constraint(equalTo: statusBar.topAnchor),

            statusBar.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            statusBar.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            statusBar.bottomAnchor.constraint(equalTo: container.bottomAnchor),
            statusBar.heightAnchor.constraint(equalToConstant: 28),

            progressIndicator.widthAnchor.constraint(greaterThanOrEqualToConstant: 100),
        ])

        // Dynamic context menu
        let menu = NSMenu()
        menu.delegate = self
        tableView.menu = menu

        self.view = container

        connectAndLoad()
    }

    // MARK: - FTP Connection

    private func connectAndLoad() {
        guard let client = connection.apiClient else {
            statusLabel.stringValue = "Not connected to device"
            return
        }

        let host = String(client.baseURL.dropFirst("http://".count))
        ftpClient = FTPClient(host: host)

        Task {
            do {
                try await ftpClient?.connect()
                statusLabel.stringValue = "Connected"
                await navigateTo(connection.fileManagerCurrentPath)
            } catch {
                statusLabel.stringValue = "FTP error: \(error.localizedDescription)"
            }
        }
    }

    // MARK: - Navigation

    private func navigateTo(_ path: String) async {
        guard let client = ftpClient else {
            print("[FileManager] No FTP client")
            return
        }
        statusLabel.stringValue = "Loading..."
        print("[FileManager] Navigating to: \(path)")

        do {
            let listing = try await client.listDirectory(path)
            print("[FileManager] Got \(listing.count) entries")
            currentPath = path
            connection.fileManagerCurrentPath = path
            entries = listing
            tableView.reloadData()
            updatePathControl()
            statusLabel.stringValue = "\(entries.count) item\(entries.count == 1 ? "" : "s")"
        } catch {
            print("[FileManager] Error: \(error)")
            statusLabel.stringValue = "Error: \(error.localizedDescription)"
        }
    }

    private func updatePathControl() {
        let components = currentPath.split(separator: "/")
        var pathItems: [NSPathControlItem] = []

        let rootItem = NSPathControlItem()
        rootItem.title = "/"
        rootItem.image = NSImage(systemSymbolName: "externaldrive.fill", accessibilityDescription: nil)
        pathItems.append(rootItem)

        var accumulated = ""
        for component in components {
            accumulated += "/\(component)"
            let item = NSPathControlItem()
            item.title = String(component)
            item.image = NSImage(systemSymbolName: "folder.fill", accessibilityDescription: nil)
            pathItems.append(item)
        }

        pathControl.pathItems = pathItems
    }

    @objc private func pathClicked(_ sender: NSPathControl) {
        guard let clickedItem = sender.clickedPathItem else { return }
        let index = sender.pathItems.firstIndex(where: { $0 === clickedItem }) ?? 0

        if index == 0 {
            Task { await navigateTo("/") }
        } else {
            let components = currentPath.split(separator: "/")
            let targetPath = "/" + components.prefix(index).joined(separator: "/")
            Task { await navigateTo(targetPath) }
        }
    }

    @objc private func doubleClickedRow() {
        let row = tableView.clickedRow
        guard row >= 0 else { return }

        // ".." row — go up
        if !isAtRoot && row == 0 {
            let parentPath = (currentPath as NSString).deletingLastPathComponent
            Task { await navigateTo(parentPath.isEmpty ? "/" : parentPath) }
            return
        }

        let offset = isAtRoot ? 0 : 1
        let index = row - offset
        guard index >= 0, index < entries.count else { return }
        let entry = entries[index]

        if entry.isDirectory {
            Task { await navigateTo(entry.path) }
            return
        }

        // Double-click runs the default action for the file type
        let ext = entry.name.lowercased().components(separatedBy: ".").last ?? ""
        let diskExtensions = ["d64", "d71", "d81", "g64", "g71"]
        let textExtensions = ["txt", "nfo", "diz", "me", "doc", "readme", "1st"]

        if textExtensions.contains(ext) || entry.name.lowercased().hasPrefix("readme") {
            viewTextFile()
        } else if diskExtensions.contains(ext) {
            runDisk()
        } else if ext == "prg" {
            runPRG()
        } else if ext == "sid" {
            playSID()
        } else if ext == "mod" {
            playMOD()
        } else if ext == "crt" {
            runCRT()
        }
    }

    @objc func refreshDirectory() {
        // Reconnect if needed, then reload
        Task {
            if ftpClient == nil {
                connectAndLoad()
            } else {
                await navigateTo(currentPath)
            }
        }
    }

    // MARK: - NSTableViewDataSource

    func numberOfRows(in tableView: NSTableView) -> Int {
        // Add ".." entry if not at root
        return entries.count + (isAtRoot ? 0 : 1)
    }

    // MARK: - NSTableViewDelegate

    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        // ".." entry for going up
        let isParentRow = !isAtRoot && row == 0
        let entry: FTPFileEntry? = isParentRow ? nil : entries[row - (isAtRoot ? 0 : 1)]

        if tableColumn?.identifier.rawValue == "name" {
            let cellID = NSUserInterfaceItemIdentifier("NameCell")
            let cell: NSTableCellView
            if let existing = tableView.makeView(withIdentifier: cellID, owner: nil) as? NSTableCellView {
                cell = existing
            } else {
                cell = NSTableCellView()
                cell.identifier = cellID

                let imageView = NSImageView()
                imageView.translatesAutoresizingMaskIntoConstraints = false
                cell.addSubview(imageView)
                cell.imageView = imageView

                let textField = NSTextField(labelWithString: "")
                textField.translatesAutoresizingMaskIntoConstraints = false
                textField.lineBreakMode = .byTruncatingTail
                cell.addSubview(textField)
                cell.textField = textField

                NSLayoutConstraint.activate([
                    imageView.leadingAnchor.constraint(equalTo: cell.leadingAnchor),
                    imageView.centerYAnchor.constraint(equalTo: cell.centerYAnchor),
                    imageView.widthAnchor.constraint(equalToConstant: 16),
                    imageView.heightAnchor.constraint(equalToConstant: 16),
                    textField.leadingAnchor.constraint(equalTo: imageView.trailingAnchor, constant: 4),
                    textField.trailingAnchor.constraint(equalTo: cell.trailingAnchor),
                    textField.centerYAnchor.constraint(equalTo: cell.centerYAnchor),
                ])
            }

            if isParentRow {
                cell.textField?.stringValue = ".."
                cell.imageView?.image = NSImage(systemSymbolName: "arrowshape.turn.up.left.fill", accessibilityDescription: "Parent directory")
                cell.imageView?.contentTintColor = .secondaryLabelColor
            } else if let entry {
                cell.textField?.stringValue = entry.name
                cell.imageView?.image = NSImage(systemSymbolName: entry.isDirectory ? "folder.fill" : "doc", accessibilityDescription: nil)
                cell.imageView?.contentTintColor = entry.isDirectory ? .systemBlue : .secondaryLabelColor
            }
            return cell
        }

        if tableColumn?.identifier.rawValue == "size" {
            let cellID = NSUserInterfaceItemIdentifier("SizeCell")
            let cell: NSTableCellView
            if let existing = tableView.makeView(withIdentifier: cellID, owner: nil) as? NSTableCellView {
                cell = existing
            } else {
                cell = NSTableCellView()
                cell.identifier = cellID
                let textField = NSTextField(labelWithString: "")
                textField.translatesAutoresizingMaskIntoConstraints = false
                textField.alignment = .right
                textField.font = .monospacedDigitSystemFont(ofSize: 11, weight: .regular)
                textField.textColor = .secondaryLabelColor
                cell.addSubview(textField)
                cell.textField = textField
                NSLayoutConstraint.activate([
                    textField.leadingAnchor.constraint(equalTo: cell.leadingAnchor),
                    textField.trailingAnchor.constraint(equalTo: cell.trailingAnchor, constant: -4),
                    textField.centerYAnchor.constraint(equalTo: cell.centerYAnchor),
                ])
            }

            if isParentRow {
                cell.textField?.stringValue = ""
            } else if let entry {
                cell.textField?.stringValue = entry.isDirectory ? "" : formatFileSize(entry.size)
            }
            return cell
        }

        return nil
    }

    // MARK: - Drag and Drop

    func tableView(_ tableView: NSTableView, validateDrop info: NSDraggingInfo, proposedRow row: Int, proposedDropOperation dropOperation: NSTableView.DropOperation) -> NSDragOperation {
        if info.draggingPasteboard.canReadObject(forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true]) {
            return .copy
        }
        return []
    }

    func tableView(_ tableView: NSTableView, acceptDrop info: NSDraggingInfo, row: Int, dropOperation: NSTableView.DropOperation) -> Bool {
        guard let urls = info.draggingPasteboard.readObjects(forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true]) as? [URL] else {
            return false
        }
        uploadURLs(urls, to: currentPath)
        return true
    }

    // MARK: - Dynamic Context Menu

    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()

        // Select the row under the cursor
        let point = tableView.convert(NSEvent.mouseLocation, from: nil)
        // Convert from screen coordinates
        let localPoint = tableView.convert(tableView.window?.convertPoint(fromScreen: NSEvent.mouseLocation) ?? .zero, from: nil)
        let clickedRow = tableView.row(at: localPoint)
        if clickedRow >= 0 {
            tableView.selectRowIndexes(IndexSet(integer: clickedRow), byExtendingSelection: false)
        }

        let entry = selectedEntry()
        let ext = entry?.name.lowercased().components(separatedBy: ".").last ?? ""
        let diskExtensions = ["d64", "d71", "d81", "g64", "g71"]

        // File-type specific actions
        if let entry, !entry.isDirectory {
            let textExtensions = ["txt", "nfo", "diz", "me", "doc", "readme", "1st"]

            if textExtensions.contains(ext) || entry.name.lowercased().hasPrefix("readme") {
                menu.addItem(withTitle: "View", action: #selector(viewTextFile), keyEquivalent: "").target = self
                menu.addItem(.separator())
            } else if diskExtensions.contains(ext) {
                menu.addItem(withTitle: "Run Disk", action: #selector(runDisk), keyEquivalent: "").target = self
                menu.addItem(withTitle: "Mount on Drive A", action: #selector(mountDriveA), keyEquivalent: "").target = self
                menu.addItem(withTitle: "Mount on Drive B", action: #selector(mountDriveB), keyEquivalent: "").target = self
                menu.addItem(.separator())
            } else if ext == "prg" {
                menu.addItem(withTitle: "Run", action: #selector(runPRG), keyEquivalent: "").target = self
                menu.addItem(withTitle: "Load", action: #selector(loadPRG), keyEquivalent: "").target = self
                menu.addItem(.separator())
            } else if ext == "sid" {
                menu.addItem(withTitle: "Play", action: #selector(playSID), keyEquivalent: "").target = self
                menu.addItem(.separator())
            } else if ext == "mod" {
                menu.addItem(withTitle: "Play", action: #selector(playMOD), keyEquivalent: "").target = self
                menu.addItem(.separator())
            } else if ext == "crt" {
                menu.addItem(withTitle: "Run", action: #selector(runCRT), keyEquivalent: "").target = self
                menu.addItem(.separator())
            }

            menu.addItem(withTitle: "Download", action: #selector(downloadSelected), keyEquivalent: "").target = self
        }

        // Common actions
        menu.addItem(withTitle: "New Folder", action: #selector(createNewFolder), keyEquivalent: "").target = self
        if entry != nil {
            menu.addItem(.separator())
            menu.addItem(withTitle: "Copy Path", action: #selector(copyPath), keyEquivalent: "").target = self
            menu.addItem(withTitle: "Move To…", action: #selector(moveSelected), keyEquivalent: "").target = self
            menu.addItem(withTitle: "Rename", action: #selector(renameSelected), keyEquivalent: "").target = self
            menu.addItem(withTitle: "Delete", action: #selector(deleteSelected), keyEquivalent: "").target = self
        }
    }

    // MARK: - Run/Mount Actions

    @objc private func runDisk() {
        guard let entry = selectedEntry(), let client = connection.apiClient else { return }
        statusLabel.stringValue = "Mounting and running \(entry.name)..."
        Task {
            do {
                try await client.mountDisk(drive: "a", imagePath: entry.path)

                // Use two keyboard buffer writes:
                // 1) LOAD"*",8,1 + RETURN (split into two parts since buffer is 10 bytes max)
                //    First: LOAD"*",8 + RETURN (10 bytes) — this starts the load
                let loadBytes: [UInt8] = [
                    0x4C, 0x4F, 0x41, 0x44,  // LOAD
                    0x22, 0x2A, 0x22, 0x2C,  // "*",
                    0x38,                    // 8
                    0x0D,                    // RETURN
                ]
                try await client.writeMem(address: 0x0277, data: Data(loadBytes))
                try await client.writeMem(address: 0x00C6, data: Data([UInt8(loadBytes.count)]))

                // 2) Wait for LOAD to complete, then send RUN + RETURN
                try await Task.sleep(for: .seconds(3))
                let runBytes: [UInt8] = [0x52, 0x55, 0x4E, 0x0D]  // RUN + RETURN
                try await client.writeMem(address: 0x0277, data: Data(runBytes))
                try await client.writeMem(address: 0x00C6, data: Data([UInt8(runBytes.count)]))

                statusLabel.stringValue = "Loading \(entry.name)"
            } catch {
                statusLabel.stringValue = "Error: \(error.localizedDescription)"
            }
        }
    }

    @objc private func mountDriveA() {
        guard let entry = selectedEntry(), let client = connection.apiClient else { return }
        Task {
            do {
                try await client.mountDisk(drive: "a", imagePath: entry.path)
                statusLabel.stringValue = "Mounted \(entry.name) on Drive A"
            } catch {
                statusLabel.stringValue = "Error: \(error.localizedDescription)"
            }
        }
    }

    @objc private func mountDriveB() {
        guard let entry = selectedEntry(), let client = connection.apiClient else { return }
        Task {
            do {
                try await client.mountDisk(drive: "b", imagePath: entry.path)
                statusLabel.stringValue = "Mounted \(entry.name) on Drive B"
            } catch {
                statusLabel.stringValue = "Error: \(error.localizedDescription)"
            }
        }
    }

    @objc private func runPRG() {
        guard let entry = selectedEntry(), let client = connection.apiClient else { return }
        Task {
            do {
                try await client.runPRGByPath(entry.path)
                statusLabel.stringValue = "Running \(entry.name)"
            } catch {
                statusLabel.stringValue = "Error: \(error.localizedDescription)"
            }
        }
    }

    @objc private func loadPRG() {
        guard let entry = selectedEntry(), let client = connection.apiClient else { return }
        Task {
            do {
                try await client.loadPRGByPath(entry.path)
                statusLabel.stringValue = "Loaded \(entry.name)"
            } catch {
                statusLabel.stringValue = "Error: \(error.localizedDescription)"
            }
        }
    }

    @objc private func playSID() {
        guard let entry = selectedEntry(), let client = connection.apiClient else { return }
        Task {
            do {
                try await client.playSIDByPath(entry.path)
                statusLabel.stringValue = "Playing \(entry.name)"
            } catch {
                statusLabel.stringValue = "Error: \(error.localizedDescription)"
            }
        }
    }

    @objc private func playMOD() {
        guard let entry = selectedEntry(), let client = connection.apiClient else { return }
        Task {
            do {
                try await client.playMODByPath(entry.path)
                statusLabel.stringValue = "Playing \(entry.name)"
            } catch {
                statusLabel.stringValue = "Error: \(error.localizedDescription)"
            }
        }
    }

    @objc private func runCRT() {
        guard let entry = selectedEntry(), let client = connection.apiClient else { return }
        Task {
            do {
                try await client.runCRTByPath(entry.path)
                statusLabel.stringValue = "Running \(entry.name)"
            } catch {
                statusLabel.stringValue = "Error: \(error.localizedDescription)"
            }
        }
    }

    // MARK: - Text File Viewer

    @objc private func viewTextFile() {
        guard let entry = selectedEntry(), let client = ftpClient else { return }
        statusLabel.stringValue = "Downloading \(entry.name)..."

        Task {
            do {
                // Download to temp file
                let tempURL = FileManager.default.temporaryDirectory.appendingPathComponent(entry.name)
                try await client.downloadFile(remotePath: entry.path, localURL: tempURL)

                // Read content — try UTF-8, fall back to Latin-1
                let content: String
                if let utf8 = try? String(contentsOf: tempURL, encoding: .utf8) {
                    content = utf8
                } else if let latin1 = try? String(contentsOf: tempURL, encoding: .isoLatin1) {
                    content = latin1
                } else {
                    content = "(Unable to read file)"
                }

                try? FileManager.default.removeItem(at: tempURL)

                // Show in a new window
                let window = NSWindow(
                    contentRect: NSRect(x: 0, y: 0, width: 600, height: 500),
                    styleMask: [.titled, .closable, .resizable, .miniaturizable],
                    backing: .buffered,
                    defer: false
                )
                window.title = entry.name
                window.center()
                window.isReleasedWhenClosed = false

                let scrollView = NSTextView.scrollableTextView()
                let textView = scrollView.documentView as! NSTextView
                textView.isEditable = false
                textView.font = .monospacedSystemFont(ofSize: 12, weight: .regular)
                textView.textContainerInset = NSSize(width: 10, height: 10)
                textView.string = content

                window.contentView = scrollView
                window.makeKeyAndOrderFront(nil)

                statusLabel.stringValue = "Viewing \(entry.name)"
            } catch {
                statusLabel.stringValue = "Error: \(error.localizedDescription)"
            }
        }
    }

    // MARK: - Upload

    @objc func uploadFiles() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = true
        if panel.runModal() == .OK {
            uploadURLs(panel.urls, to: currentPath)
        }
    }

    private func uploadURLs(_ urls: [URL], to targetPath: String) {
        progressIndicator.isHidden = false
        progressIndicator.doubleValue = 0

        Task {
            do {
                var totalFiles = 0
                var completedFiles = 0

                for url in urls {
                    var isDir: ObjCBool = false
                    FileManager.default.fileExists(atPath: url.path, isDirectory: &isDir)
                    if isDir.boolValue {
                        let enumerator = FileManager.default.enumerator(at: url, includingPropertiesForKeys: [.isDirectoryKey])
                        while let _ = enumerator?.nextObject() { totalFiles += 1 }
                    } else {
                        totalFiles += 1
                    }
                }

                if totalFiles == 0 { totalFiles = 1 }

                for url in urls {
                    var isDir: ObjCBool = false
                    FileManager.default.fileExists(atPath: url.path, isDirectory: &isDir)

                    if isDir.boolValue {
                        let remoteDirPath = targetPath.hasSuffix("/") ? targetPath + url.lastPathComponent : targetPath + "/" + url.lastPathComponent
                        try await ftpClient?.uploadDirectory(localURL: url, remotePath: remoteDirPath) { current, total, name in
                            completedFiles += 1
                            self.statusLabel.stringValue = "Uploading: \(name) (\(completedFiles)/\(totalFiles))"
                            self.progressIndicator.doubleValue = Double(completedFiles) / Double(totalFiles) * 100
                        }
                    } else {
                        let remotePath = targetPath.hasSuffix("/") ? targetPath + url.lastPathComponent : targetPath + "/" + url.lastPathComponent
                        statusLabel.stringValue = "Uploading: \(url.lastPathComponent)"
                        try await ftpClient?.uploadFile(localURL: url, remotePath: remotePath)
                        completedFiles += 1
                        progressIndicator.doubleValue = Double(completedFiles) / Double(totalFiles) * 100
                    }
                }

                statusLabel.stringValue = "Upload complete"
                progressIndicator.isHidden = true
                await navigateTo(currentPath)
            } catch {
                statusLabel.stringValue = "Upload error: \(error.localizedDescription)"
                progressIndicator.isHidden = true
            }
        }
    }

    // MARK: - Context Menu Actions

    @objc private func downloadSelected() {
        guard let entry = selectedEntry(), !entry.isDirectory else { return }

        let panel = NSSavePanel()
        panel.nameFieldStringValue = entry.name
        if panel.runModal() == .OK, let url = panel.url {
            statusLabel.stringValue = "Downloading \(entry.name)..."
            Task {
                do {
                    try await ftpClient?.downloadFile(remotePath: entry.path, localURL: url)
                    statusLabel.stringValue = "Download complete"
                } catch {
                    statusLabel.stringValue = "Download error: \(error.localizedDescription)"
                }
            }
        }
    }

    @objc func createNewFolder() {
        let alert = NSAlert()
        alert.messageText = "New Folder"
        alert.addButton(withTitle: "Create")
        alert.addButton(withTitle: "Cancel")
        let nameField = NSTextField(frame: NSRect(x: 0, y: 0, width: 200, height: 24))
        nameField.placeholderString = "Folder Name"
        alert.accessoryView = nameField
        guard let window = view.window else { return }
        alert.beginSheetModal(for: window) { [weak self] response in
            guard let self, response == .alertFirstButtonReturn else { return }
            let name = nameField.stringValue.trimmingCharacters(in: .whitespaces)
            guard !name.isEmpty else { return }

            let fullPath = self.currentPath.hasSuffix("/") ? self.currentPath + name : self.currentPath + "/" + name
            Task {
                do {
                    try await self.ftpClient?.createDirectory(fullPath)
                    await self.navigateTo(self.currentPath)
                } catch {
                    self.statusLabel.stringValue = "Error: \(error.localizedDescription)"
                }
            }
        }
    }

    @objc private func copyPath() {
        guard let entry = selectedEntry() else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(entry.path, forType: .string)
        statusLabel.stringValue = "Copied: \(entry.path)"
    }

    @objc private func moveSelected() {
        let entriesToMove = selectedEntries()
        guard !entriesToMove.isEmpty else { return }

        let alert = NSAlert()
        alert.messageText = "Move \(entriesToMove.count == 1 ? entriesToMove[0].name : "\(entriesToMove.count) items")"
        alert.informativeText = "Enter the destination directory path:"
        alert.addButton(withTitle: "Move")
        alert.addButton(withTitle: "Cancel")
        let pathField = NSTextField(frame: NSRect(x: 0, y: 0, width: 300, height: 24))
        // Pre-fill with clipboard if it looks like a device path, otherwise current path
        let clipboard = NSPasteboard.general.string(forType: .string) ?? ""
        pathField.stringValue = clipboard.hasPrefix("/") ? clipboard : currentPath
        pathField.placeholderString = "/path/to/destination"
        alert.accessoryView = pathField
        guard let window = view.window else { return }
        alert.beginSheetModal(for: window) { [weak self] response in
            guard let self, response == .alertFirstButtonReturn else { return }
            let destPath = pathField.stringValue.trimmingCharacters(in: .whitespaces)
            guard !destPath.isEmpty else { return }

            Task {
                for entry in entriesToMove {
                    let newPath = destPath.hasSuffix("/") ? destPath + entry.name : destPath + "/" + entry.name
                    do {
                        try await self.ftpClient?.rename(from: entry.path, to: newPath)
                    } catch {
                        self.statusLabel.stringValue = "Error moving \(entry.name): \(error.localizedDescription)"
                    }
                }
                await self.navigateTo(self.currentPath)
            }
        }
    }

    @objc private func renameSelected() {
        guard let entry = selectedEntry() else { return }

        let alert = NSAlert()
        alert.messageText = "Rename"
        alert.addButton(withTitle: "Rename")
        alert.addButton(withTitle: "Cancel")
        let nameField = NSTextField(frame: NSRect(x: 0, y: 0, width: 200, height: 24))
        nameField.stringValue = entry.name
        alert.accessoryView = nameField
        guard let window = view.window else { return }
        alert.beginSheetModal(for: window) { [weak self] response in
            guard let self, response == .alertFirstButtonReturn else { return }
            let newName = nameField.stringValue.trimmingCharacters(in: .whitespaces)
            guard !newName.isEmpty, newName != entry.name else { return }

            let parentPath = (entry.path as NSString).deletingLastPathComponent
            let newPath = (parentPath as NSString).appendingPathComponent(newName)

            Task {
                do {
                    try await self.ftpClient?.rename(from: entry.path, to: newPath)
                    await self.navigateTo(self.currentPath)
                } catch {
                    self.statusLabel.stringValue = "Error: \(error.localizedDescription)"
                }
            }
        }
    }

    @objc func deleteSelected() {
        let selectedEntries = self.selectedEntries()
        guard !selectedEntries.isEmpty else { return }

        let alert = NSAlert()
        alert.messageText = "Delete \(selectedEntries.count == 1 ? selectedEntries[0].name : "\(selectedEntries.count) items")?"
        alert.alertStyle = .warning
        alert.addButton(withTitle: "Delete")
        alert.addButton(withTitle: "Cancel")
        guard let window = view.window else { return }
        alert.beginSheetModal(for: window) { [weak self] response in
            guard let self, response == .alertFirstButtonReturn else { return }
            Task {
                for entry in selectedEntries {
                    do {
                        if entry.isDirectory {
                            try await self.ftpClient?.deleteDirectory(entry.path)
                        } else {
                            try await self.ftpClient?.deleteFile(entry.path)
                        }
                    } catch {
                        self.statusLabel.stringValue = "Error deleting \(entry.name): \(error.localizedDescription)"
                    }
                }
                await self.navigateTo(self.currentPath)
            }
        }
    }

    // MARK: - Helpers

    private func selectedEntry() -> FTPFileEntry? {
        let row = tableView.selectedRow
        guard row >= 0 else { return nil }
        let offset = isAtRoot ? 0 : 1
        guard row >= offset, (row - offset) < entries.count else { return nil }
        return entries[row - offset]
    }

    private func selectedEntries() -> [FTPFileEntry] {
        let offset = isAtRoot ? 0 : 1
        return tableView.selectedRowIndexes.compactMap { row in
            guard row >= offset, (row - offset) < entries.count else { return nil }
            return entries[row - offset]
        }
    }

    private func formatFileSize(_ bytes: UInt64) -> String {
        if bytes < 1024 { return "\(bytes) B" }
        if bytes < 1024 * 1024 { return String(format: "%.1f KB", Double(bytes) / 1024) }
        if bytes < 1024 * 1024 * 1024 { return String(format: "%.1f MB", Double(bytes) / (1024 * 1024)) }
        return String(format: "%.1f GB", Double(bytes) / (1024 * 1024 * 1024))
    }
}
