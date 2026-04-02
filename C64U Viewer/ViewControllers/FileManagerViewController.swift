// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.

import AppKit
internal import UniformTypeIdentifiers

// MARK: - Tree Node Model

private class TreeNode {
    let entry: FTPFileEntry?
    let name: String
    let isDirectory: Bool
    var children: [TreeNode]?  // nil = not loaded, [] = loaded but empty
    var isLoading = false

    /// Root node
    init(rootName: String) {
        self.entry = nil
        self.name = rootName
        self.isDirectory = true
    }

    /// Node from FTP entry
    init(entry: FTPFileEntry) {
        self.entry = entry
        self.name = entry.name
        self.isDirectory = entry.isDirectory
    }

    var path: String {
        entry?.path ?? "/"
    }
}

/// Placeholder shown while a directory's children are being fetched
private class PlaceholderNode: TreeNode {
    init() {
        super.init(rootName: "Loading…")
        self.children = []
    }
}

// MARK: - FileManagerViewController

final class FileManagerViewController: NSViewController, NSOutlineViewDataSource, NSOutlineViewDelegate, NSMenuDelegate {
    let connection: C64Connection
    private var ftpClient: FTPClient?
    private let outlineView = NSOutlineView()
    private var statusLabel: NSTextField!
    private var progressIndicator: NSProgressIndicator!

    private let rootNode = TreeNode(rootName: "C64")

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

        // Outline view for tree-based file listing
        let scrollView = NSScrollView()
        scrollView.hasVerticalScroller = true
        scrollView.autohidesScrollers = true
        scrollView.drawsBackground = false
        scrollView.translatesAutoresizingMaskIntoConstraints = false

        let nameColumn = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("name"))
        nameColumn.title = "Name"
        nameColumn.resizingMask = .autoresizingMask
        outlineView.addTableColumn(nameColumn)
        outlineView.outlineTableColumn = nameColumn

        outlineView.headerView = nil
        outlineView.columnAutoresizingStyle = .firstColumnOnlyAutoresizingStyle
        outlineView.backgroundColor = .clear
        outlineView.dataSource = self
        outlineView.delegate = self
        outlineView.rowSizeStyle = .default
        outlineView.allowsMultipleSelection = true
        outlineView.doubleAction = #selector(doubleClickedRow)
        outlineView.target = self

        // Keyboard shortcuts
        NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self, self.view.window?.firstResponder === self.outlineView else { return event }
            switch event.keyCode {
            case 51: // Delete/Backspace
                self.deleteSelected()
                return nil
            case 36: // Return/Enter — rename (matches Finder behavior)
                if self.selectedEntry() != nil {
                    self.renameSelected()
                }
                return nil
            default:
                return event
            }
        }

        // Register for drag and drop from Finder
        outlineView.registerForDraggedTypes([.fileURL])
        outlineView.setDraggingSourceOperationMask(.copy, forLocal: false)

        scrollView.documentView = outlineView

        // Status bar
        statusLabel = NSTextField(labelWithString: "Connecting...")
        statusLabel.font = .systemFont(ofSize: 11)
        statusLabel.textColor = .secondaryLabelColor
        statusLabel.lineBreakMode = .byTruncatingMiddle
        statusLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        statusLabel.translatesAutoresizingMaskIntoConstraints = false

        progressIndicator = NSProgressIndicator()
        progressIndicator.style = .bar
        progressIndicator.isIndeterminate = false
        progressIndicator.isHidden = true
        progressIndicator.translatesAutoresizingMaskIntoConstraints = false

        let bottomSeparator = NSBox()
        bottomSeparator.boxType = .separator
        bottomSeparator.translatesAutoresizingMaskIntoConstraints = false

        let statusBar = NSStackView(views: [statusLabel, progressIndicator])
        statusBar.orientation = .horizontal
        statusBar.spacing = 8
        statusBar.edgeInsets = NSEdgeInsets(top: 4, left: 16, bottom: 4, right: 8)
        statusBar.translatesAutoresizingMaskIntoConstraints = false

        let sectionHeader = NSTextField(labelWithString: "File System")
        sectionHeader.font = .systemFont(ofSize: 11, weight: .bold)
        sectionHeader.textColor = .secondaryLabelColor
        sectionHeader.translatesAutoresizingMaskIntoConstraints = false

        container.addSubview(sectionHeader)
        container.addSubview(scrollView)
        container.addSubview(bottomSeparator)
        container.addSubview(statusBar)

        NSLayoutConstraint.activate([
            sectionHeader.topAnchor.constraint(equalTo: container.safeAreaLayoutGuide.topAnchor, constant: 4),
            sectionHeader.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 16),
            sectionHeader.trailingAnchor.constraint(lessThanOrEqualTo: container.trailingAnchor, constant: -8),

            scrollView.topAnchor.constraint(equalTo: sectionHeader.bottomAnchor, constant: 4),
            scrollView.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            scrollView.bottomAnchor.constraint(equalTo: bottomSeparator.topAnchor),

            bottomSeparator.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            bottomSeparator.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            bottomSeparator.bottomAnchor.constraint(equalTo: statusBar.topAnchor),

            statusBar.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            statusBar.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            statusBar.bottomAnchor.constraint(equalTo: container.bottomAnchor),
            statusBar.heightAnchor.constraint(equalToConstant: 24),

            progressIndicator.widthAnchor.constraint(greaterThanOrEqualToConstant: 80),
        ])

        // Dynamic context menu
        let menu = NSMenu()
        menu.delegate = self
        outlineView.menu = menu

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

                // Load root directory
                await loadChildren(of: rootNode)
                outlineView.reloadData()
                outlineView.expandItem(rootNode)

                // Restore previously expanded path
                await restoreExpandedPath(connection.fileManagerCurrentPath)
            } catch {
                statusLabel.stringValue = "FTP error: \(error.localizedDescription)"
            }
        }
    }

    // MARK: - Tree Loading

    private func loadChildren(of node: TreeNode) async {
        guard let client = ftpClient, node.isDirectory, !node.isLoading else { return }

        node.isLoading = true
        let path = node.path

        do {
            let listing = try await client.listDirectory(path)
            node.children = listing.map { TreeNode(entry: $0) }
            node.isLoading = false
        } catch {
            Log.error("Failed to load \(path): \(error)")
            node.children = nil  // leave as not-loaded so expanding retries
            node.isLoading = false
            statusLabel.stringValue = "\(node.name) is unavailable"
        }
    }

    private func restoreExpandedPath(_ path: String) async {
        guard path != "/" else { return }

        let components = path.split(separator: "/").map(String.init)
        var current = rootNode

        for component in components {
            // Ensure children are loaded
            if current.children == nil {
                await loadChildren(of: current)
                outlineView.reloadItem(current, reloadChildren: true)
            }

            guard let child = current.children?.first(where: { $0.name == component && $0.isDirectory }) else {
                break
            }

            outlineView.expandItem(child)
            current = child
        }

        connection.fileManagerCurrentPath = current.path
    }

    // MARK: - NSOutlineViewDataSource

    func outlineView(_ outlineView: NSOutlineView, numberOfChildrenOfItem item: Any?) -> Int {
        let node = item as? TreeNode ?? rootNode
        if node.isDirectory {
            if let children = node.children {
                return children.count
            }
            return 1  // placeholder "Loading…"
        }
        return 0
    }

    func outlineView(_ outlineView: NSOutlineView, child index: Int, ofItem item: Any?) -> Any {
        let node = item as? TreeNode ?? rootNode
        if let children = node.children {
            return children[index]
        }
        // Return placeholder
        return PlaceholderNode()
    }

    func outlineView(_ outlineView: NSOutlineView, isItemExpandable item: Any) -> Bool {
        let node = item as? TreeNode ?? rootNode
        return node.isDirectory && !(node is PlaceholderNode)
    }

    // MARK: - NSOutlineViewDelegate

    func outlineView(_ outlineView: NSOutlineView, viewFor tableColumn: NSTableColumn?, item: Any) -> NSView? {
        guard let node = item as? TreeNode else { return nil }

        let cellID = NSUserInterfaceItemIdentifier("NameCell")
        let sizeTag = 100
        let cell: NSTableCellView

        if let existing = outlineView.makeView(withIdentifier: cellID, owner: nil) as? NSTableCellView {
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
            textField.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
            cell.addSubview(textField)
            cell.textField = textField

            let sizeLabel = NSTextField(labelWithString: "")
            sizeLabel.translatesAutoresizingMaskIntoConstraints = false
            sizeLabel.alignment = .right
            sizeLabel.font = .monospacedDigitSystemFont(ofSize: 11, weight: .regular)
            sizeLabel.textColor = .secondaryLabelColor
            sizeLabel.tag = sizeTag
            sizeLabel.setContentCompressionResistancePriority(.required, for: .horizontal)
            sizeLabel.setContentHuggingPriority(.required, for: .horizontal)
            cell.addSubview(sizeLabel)

            NSLayoutConstraint.activate([
                imageView.leadingAnchor.constraint(equalTo: cell.leadingAnchor),
                imageView.centerYAnchor.constraint(equalTo: cell.centerYAnchor),
                imageView.widthAnchor.constraint(equalToConstant: 16),
                imageView.heightAnchor.constraint(equalToConstant: 16),
                textField.leadingAnchor.constraint(equalTo: imageView.trailingAnchor, constant: 4),
                textField.centerYAnchor.constraint(equalTo: cell.centerYAnchor),
                sizeLabel.leadingAnchor.constraint(greaterThanOrEqualTo: textField.trailingAnchor, constant: 4),
                sizeLabel.trailingAnchor.constraint(equalTo: cell.trailingAnchor, constant: -4),
                sizeLabel.centerYAnchor.constraint(equalTo: cell.centerYAnchor),
            ])
        }

        let sizeLabel = cell.viewWithTag(sizeTag) as? NSTextField

        if node is PlaceholderNode {
            cell.textField?.stringValue = "Loading…"
            cell.textField?.textColor = .secondaryLabelColor
            cell.textField?.toolTip = nil
            cell.imageView?.image = nil
            sizeLabel?.stringValue = ""
        } else if node.entry == nil {
            // Root node
            cell.textField?.stringValue = node.name
            cell.textField?.textColor = .labelColor
            cell.textField?.toolTip = nil
            cell.imageView?.image = NSImage(systemSymbolName: "desktopcomputer", accessibilityDescription: "C64")
            cell.imageView?.contentTintColor = .secondaryLabelColor
            sizeLabel?.stringValue = ""
        } else if node.isDirectory {
            cell.textField?.stringValue = node.name
            cell.textField?.textColor = .labelColor
            cell.textField?.toolTip = node.name
            cell.imageView?.image = NSImage(systemSymbolName: "folder.fill", accessibilityDescription: nil)
            cell.imageView?.contentTintColor = .systemBlue
            sizeLabel?.stringValue = ""
        } else {
            cell.textField?.stringValue = node.name
            cell.textField?.textColor = .labelColor
            cell.textField?.toolTip = node.name
            cell.imageView?.image = NSImage(systemSymbolName: "doc", accessibilityDescription: nil)
            cell.imageView?.contentTintColor = .secondaryLabelColor
            // Size shown only when selected — handled in outlineViewSelectionDidChange
            sizeLabel?.stringValue = ""
        }

        return cell
    }

    func outlineView(_ outlineView: NSOutlineView, shouldSelectItem item: Any) -> Bool {
        !(item is PlaceholderNode)
    }

    func outlineViewItemWillExpand(_ notification: Notification) {
        guard let node = notification.userInfo?["NSObject"] as? TreeNode else { return }
        guard node.children == nil, !node.isLoading else { return }

        Task {
            await loadChildren(of: node)

            if node.children != nil {
                outlineView.reloadItem(node, reloadChildren: true)
                let count = node.children?.count ?? 0
                statusLabel.stringValue = "\(count) item\(count == 1 ? "" : "s") in \(node.name)"
            } else {
                // Load failed — collapse so user can retry
                outlineView.collapseItem(node)
            }
        }
    }

    func outlineViewSelectionDidChange(_ notification: Notification) {
        let sizeTag = 100
        let selectedRows = outlineView.selectedRowIndexes

        // Update size labels: show for selected files, hide for others
        for row in 0..<outlineView.numberOfRows {
            guard let cellView = outlineView.view(atColumn: 0, row: row, makeIfNecessary: false) as? NSTableCellView,
                  let sizeLabel = cellView.viewWithTag(sizeTag) as? NSTextField,
                  let node = outlineView.item(atRow: row) as? TreeNode else { continue }

            if selectedRows.contains(row), !node.isDirectory, let entry = node.entry {
                sizeLabel.stringValue = formatFileSize(entry.size)
            } else {
                sizeLabel.stringValue = ""
            }
        }

        // Track the deepest expanded directory for path restoration
        guard let node = outlineView.item(atRow: outlineView.selectedRow) as? TreeNode else { return }
        if node.isDirectory {
            connection.fileManagerCurrentPath = node.path
        } else if let parent = outlineView.parent(forItem: node) as? TreeNode {
            connection.fileManagerCurrentPath = parent.path
        }
    }

    // MARK: - Double Click

    @objc private func doubleClickedRow() {
        let row = outlineView.clickedRow
        guard row >= 0 else { return }
        guard let node = outlineView.item(atRow: row) as? TreeNode else { return }

        // Toggle expand/collapse for directories
        if node.isDirectory {
            if outlineView.isItemExpanded(node) {
                outlineView.collapseItem(node)
            } else {
                outlineView.expandItem(node)
            }
            return
        }

        // Double-click runs the default action for the file type
        guard let entry = node.entry else { return }
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

    // MARK: - Refresh

    @objc func refreshDirectory() {
        Task {
            if ftpClient == nil {
                connectAndLoad()
            } else {
                // Reload the currently selected directory, or root
                let node = selectedDirectoryNode() ?? rootNode
                node.children = nil
                await loadChildren(of: node)
                outlineView.reloadItem(node, reloadChildren: true)
                outlineView.expandItem(node)
                let count = node.children?.count ?? 0
                statusLabel.stringValue = "\(count) item\(count == 1 ? "" : "s")"
            }
        }
    }

    // MARK: - Drag and Drop

    func outlineView(_ outlineView: NSOutlineView, validateDrop info: NSDraggingInfo, proposedItem item: Any?, proposedChildIndex index: Int) -> NSDragOperation {
        if info.draggingPasteboard.canReadObject(forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true]) {
            return .copy
        }
        return []
    }

    func outlineView(_ outlineView: NSOutlineView, acceptDrop info: NSDraggingInfo, item: Any?, childIndex index: Int) -> Bool {
        guard let urls = info.draggingPasteboard.readObjects(forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true]) as? [URL] else {
            return false
        }
        // Determine target directory from drop target
        let targetNode: TreeNode
        if let node = item as? TreeNode, node.isDirectory {
            targetNode = node
        } else if let node = item as? TreeNode, let parent = outlineView.parent(forItem: node) as? TreeNode {
            targetNode = parent
        } else {
            targetNode = rootNode
        }
        uploadURLs(urls, to: targetNode.path, reloadNode: targetNode)
        return true
    }

    // MARK: - Dynamic Context Menu

    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()

        // Select the row under the cursor
        let localPoint = outlineView.convert(outlineView.window?.convertPoint(fromScreen: NSEvent.mouseLocation) ?? .zero, from: nil)
        let clickedRow = outlineView.row(at: localPoint)
        if clickedRow >= 0 {
            outlineView.selectRowIndexes(IndexSet(integer: clickedRow), byExtendingSelection: false)
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
        Log.info("runDisk: '\(entry.name)' path='\(entry.path)'")
        statusLabel.stringValue = "Mounting and running \(entry.name)..."
        Task {
            do {
                try await client.mountDisk(drive: "a", imagePath: entry.path)
                NotificationCenter.default.post(name: .driveStatusDidChange, object: nil)

                let loadBytes: [UInt8] = [
                    0x4C, 0x4F, 0x41, 0x44,  // LOAD
                    0x22, 0x2A, 0x22, 0x2C,  // "*",
                    0x38,                    // 8
                    0x0D,                    // RETURN
                ]
                try await client.writeMem(address: 0x0277, data: Data(loadBytes))
                try await client.writeMem(address: 0x00C6, data: Data([UInt8(loadBytes.count)]))

                try await Task.sleep(for: .seconds(3))
                let runBytes: [UInt8] = [0x52, 0x55, 0x4E, 0x0D]  // RUN + RETURN
                try await client.writeMem(address: 0x0277, data: Data(runBytes))
                try await client.writeMem(address: 0x00C6, data: Data([UInt8(runBytes.count)]))

                statusLabel.stringValue = "Loading \(entry.name)"

            } catch {
                Log.error("runDisk failed: \(error.localizedDescription)")
                showError("Error", details: error.localizedDescription)
            }
        }
    }

    @objc private func mountDriveA() {
        guard let entry = selectedEntry(), let client = connection.apiClient else { return }
        Log.info("mountDriveA: '\(entry.name)' path='\(entry.path)'")
        Task {
            do {
                try await client.mountDisk(drive: "a", imagePath: entry.path)
                NotificationCenter.default.post(name: .driveStatusDidChange, object: nil)
                statusLabel.stringValue = "Mounted \(entry.name) on Drive A"

            } catch {
                Log.error("mountDriveA failed: \(error.localizedDescription)")
                showError("Error", details: error.localizedDescription)
            }
        }
    }

    @objc private func mountDriveB() {
        guard let entry = selectedEntry(), let client = connection.apiClient else { return }
        Log.info("mountDriveB: '\(entry.name)' path='\(entry.path)'")
        Task {
            do {
                try await client.mountDisk(drive: "b", imagePath: entry.path)
                NotificationCenter.default.post(name: .driveStatusDidChange, object: nil)
                statusLabel.stringValue = "Mounted \(entry.name) on Drive B"

            } catch {
                Log.error("mountDriveB failed: \(error.localizedDescription)")
                showError("Error", details: error.localizedDescription)
            }
        }
    }

    @objc private func runPRG() {
        guard let entry = selectedEntry(), let client = connection.apiClient else { return }
        Log.info("runPRG: '\(entry.name)' path='\(entry.path)'")
        Task {
            do {
                try await client.runPRGByPath(entry.path)
                statusLabel.stringValue = "Running \(entry.name)"
            } catch {
                Log.error("runPRG failed: \(error.localizedDescription)")
                showError("Error", details: error.localizedDescription)
            }
        }
    }

    @objc private func loadPRG() {
        guard let entry = selectedEntry(), let client = connection.apiClient else { return }
        Log.info("loadPRG: '\(entry.name)' path='\(entry.path)'")
        Task {
            do {
                try await client.loadPRGByPath(entry.path)
                statusLabel.stringValue = "Loaded \(entry.name)"
            } catch {
                Log.error("loadPRG failed: \(error.localizedDescription)")
                showError("Error", details: error.localizedDescription)
            }
        }
    }

    @objc private func playSID() {
        guard let entry = selectedEntry(), let client = connection.apiClient else { return }
        Log.info("playSID: '\(entry.name)' path='\(entry.path)'")
        Task {
            do {
                try await client.playSIDByPath(entry.path)
                statusLabel.stringValue = "Playing \(entry.name)"
            } catch {
                Log.error("playSID failed: \(error.localizedDescription)")
                showError("Error", details: error.localizedDescription)
            }
        }
    }

    @objc private func playMOD() {
        guard let entry = selectedEntry(), let client = connection.apiClient else { return }
        Log.info("playMOD: '\(entry.name)' path='\(entry.path)'")
        Task {
            do {
                try await client.playMODByPath(entry.path)
                statusLabel.stringValue = "Playing \(entry.name)"
            } catch {
                Log.error("playMOD failed: \(error.localizedDescription)")
                showError("Error", details: error.localizedDescription)
            }
        }
    }

    @objc private func runCRT() {
        guard let entry = selectedEntry(), let client = connection.apiClient else { return }
        Log.info("runCRT: '\(entry.name)' path='\(entry.path)'")
        Task {
            do {
                try await client.runCRTByPath(entry.path)
                statusLabel.stringValue = "Running \(entry.name)"
            } catch {
                Log.error("runCRT failed: \(error.localizedDescription)")
                showError("Error", details: error.localizedDescription)
            }
        }
    }

    // MARK: - Text File Viewer

    @objc private func viewTextFile() {
        guard let entry = selectedEntry(), let client = ftpClient else { return }
        statusLabel.stringValue = "Downloading \(entry.name)..."

        Task {
            do {
                let tempURL = FileManager.default.temporaryDirectory.appendingPathComponent(entry.name)
                try await client.downloadFile(remotePath: entry.path, localURL: tempURL)

                let content: String
                if let utf8 = try? String(contentsOf: tempURL, encoding: .utf8) {
                    content = utf8
                } else if let latin1 = try? String(contentsOf: tempURL, encoding: .isoLatin1) {
                    content = latin1
                } else {
                    content = "(Unable to read file)"
                }

                try? FileManager.default.removeItem(at: tempURL)

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
                showError("Error", details: error.localizedDescription)
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
            let targetNode = selectedDirectoryNode() ?? rootNode
            uploadURLs(panel.urls, to: targetNode.path, reloadNode: targetNode)
        }
    }

    private func uploadURLs(_ urls: [URL], to targetPath: String, reloadNode: TreeNode) {
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

                // Reload the target directory in the tree
                reloadNode.children = nil
                await loadChildren(of: reloadNode)
                outlineView.reloadItem(reloadNode, reloadChildren: true)
                outlineView.expandItem(reloadNode)
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

        let targetNode = selectedDirectoryNode() ?? rootNode

        alert.beginSheetModal(for: window) { [weak self] response in
            guard let self, response == .alertFirstButtonReturn else { return }
            let name = nameField.stringValue.trimmingCharacters(in: .whitespaces)
            guard !name.isEmpty else { return }

            let fullPath = targetNode.path.hasSuffix("/") ? targetNode.path + name : targetNode.path + "/" + name
            Task {
                do {
                    try await self.ftpClient?.createDirectory(fullPath)
                    // Reload parent
                    targetNode.children = nil
                    await self.loadChildren(of: targetNode)
                    self.outlineView.reloadItem(targetNode, reloadChildren: true)
                    self.outlineView.expandItem(targetNode)
                } catch {
                    self.showError("Error", details: error.localizedDescription)
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
        let clipboard = NSPasteboard.general.string(forType: .string) ?? ""
        let currentDir = selectedDirectoryNode()?.path ?? "/"
        pathField.stringValue = clipboard.hasPrefix("/") ? clipboard : currentDir
        pathField.placeholderString = "/path/to/destination"
        alert.accessoryView = pathField
        guard let window = view.window else { return }
        alert.beginSheetModal(for: window) { [weak self] response in
            guard let self, response == .alertFirstButtonReturn else { return }
            let destPath = pathField.stringValue.trimmingCharacters(in: .whitespaces)
            guard !destPath.isEmpty else { return }

            Task {
                var errors: [String] = []
                for entry in entriesToMove {
                    let newPath = destPath.hasSuffix("/") ? destPath + entry.name : destPath + "/" + entry.name
                    do {
                        try await self.ftpClient?.rename(from: entry.path, to: newPath)
                    } catch {
                        errors.append("\(entry.name): \(error.localizedDescription)")
                    }
                }
                if !errors.isEmpty {
                    self.showError("Move Failed", details: errors.joined(separator: "\n"))
                }
                // Reload the parent of the moved items
                self.reloadParentOfSelection()
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
                    self.reloadParentOfSelection()
                } catch {
                    self.showError("Error", details: error.localizedDescription)
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
                        self.showError("Delete Failed", details: "\(entry.name): \(error.localizedDescription)")
                    }
                }
                self.reloadParentOfSelection()
            }
        }
    }

    // MARK: - Helpers

    private func selectedNode() -> TreeNode? {
        let row = outlineView.selectedRow
        guard row >= 0 else { return nil }
        return outlineView.item(atRow: row) as? TreeNode
    }

    private func selectedEntry() -> FTPFileEntry? {
        selectedNode()?.entry
    }

    private func selectedEntries() -> [FTPFileEntry] {
        outlineView.selectedRowIndexes.compactMap { row in
            (outlineView.item(atRow: row) as? TreeNode)?.entry
        }
    }

    /// Returns the selected directory node, or the parent directory of the selected file
    private func selectedDirectoryNode() -> TreeNode? {
        guard let node = selectedNode() else { return nil }
        if node.isDirectory {
            return node
        }
        return outlineView.parent(forItem: node) as? TreeNode
    }

    private func reloadParentOfSelection() {
        Task {
            let parentNode: TreeNode
            if let node = selectedNode(), let parent = outlineView.parent(forItem: node) as? TreeNode {
                parentNode = parent
            } else {
                parentNode = rootNode
            }
            parentNode.children = nil
            await loadChildren(of: parentNode)
            outlineView.reloadItem(parentNode, reloadChildren: true)
            outlineView.expandItem(parentNode)
        }
    }

    private func showError(_ title: String, details: String) {
        guard let window = view.window else {
            print("[FileManager] Error: \(title) — \(details)")
            return
        }
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = details
        alert.alertStyle = .warning
        alert.addButton(withTitle: "OK")
        alert.beginSheetModal(for: window)
    }

    private func formatFileSize(_ bytes: UInt64) -> String {
        if bytes < 1024 { return "\(bytes) B" }
        if bytes < 1024 * 1024 { return String(format: "%.1f KB", Double(bytes) / 1024) }
        if bytes < 1024 * 1024 * 1024 { return String(format: "%.1f MB", Double(bytes) / (1024 * 1024)) }
        return String(format: "%.1f GB", Double(bytes) / (1024 * 1024 * 1024))
    }
}
