// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.

import AppKit
internal import UniformTypeIdentifiers

final class BASICScratchpadViewController: NSViewController {
    let connection: C64Connection
    private let editorManager = BASICEditorTextViewManager()

    private var errorLabel: NSTextField!
    private var lineCountLabel: NSTextField!
    private(set) var specialCodesView: NSView?
    var isSpecialCodesVisible: Bool { specialCodesView != nil }
    private var specialCodesBottomConstraint: NSLayoutConstraint?
    private var statusBarToEditorConstraint: NSLayoutConstraint?
    private var statusBarToCodesConstraint: NSLayoutConstraint?
    private var isUploading = false

    init(connection: C64Connection) {
        self.connection = connection
        super.init(nibName: nil, bundle: nil)
        self.title = "BASIC Scratchpad"
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    override func loadView() {
        let container = NSView()

        // Editor
        let scrollView = editorManager.createScrollView()
        scrollView.translatesAutoresizingMaskIntoConstraints = false

        // Bottom bar: error/line count + action buttons
        lineCountLabel = NSTextField(labelWithString: "0 lines")
        lineCountLabel.font = .systemFont(ofSize: 11)
        lineCountLabel.textColor = .secondaryLabelColor
        lineCountLabel.translatesAutoresizingMaskIntoConstraints = false

        errorLabel = NSTextField(labelWithString: "")
        errorLabel.font = .systemFont(ofSize: 11)
        errorLabel.textColor = .systemRed
        errorLabel.isHidden = true
        errorLabel.translatesAutoresizingMaskIntoConstraints = false

        let statusBar = NSStackView(views: [errorLabel, lineCountLabel])
        statusBar.orientation = .horizontal
        statusBar.spacing = 6
        statusBar.edgeInsets = NSEdgeInsets(top: 4, left: 8, bottom: 4, right: 8)
        statusBar.translatesAutoresizingMaskIntoConstraints = false

        container.addSubview(scrollView)
        container.addSubview(statusBar)

        statusBarToEditorConstraint = scrollView.bottomAnchor.constraint(equalTo: statusBar.topAnchor)

        NSLayoutConstraint.activate([
            scrollView.topAnchor.constraint(equalTo: container.topAnchor),
            scrollView.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            statusBarToEditorConstraint!,

            statusBar.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            statusBar.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            statusBar.bottomAnchor.constraint(equalTo: container.bottomAnchor),
            statusBar.heightAnchor.constraint(equalToConstant: 24),
        ])

        self.view = container

        // Set initial text and wire up changes
        editorManager.setText(connection.basicScratchpadCode)
        editorManager.onTextChange = { [weak self] text in
            self?.connection.basicScratchpadCode = text
            self?.updateLineCount()
        }
        updateLineCount()
    }

    // MARK: - Line Count

    private func updateLineCount() {
        let count = connection.basicScratchpadCode
            .split(separator: "\n", omittingEmptySubsequences: true).count
        lineCountLabel.stringValue = "\(count) line\(count == 1 ? "" : "s")"
    }

    // MARK: - File Menu Button

    private func createFileMenuButton() -> NSButton {
        let button = NSButton(image: NSImage(systemSymbolName: "doc", accessibilityDescription: "File")!, target: nil, action: nil)
        button.bezelStyle = .toolbar
        button.toolTip = "File"

        let menu = NSMenu()

        let samplesItem = NSMenuItem(title: "Samples", action: nil, keyEquivalent: "")
        let samplesMenu = NSMenu()
        for sample in BASICSamples.all {
            let item = NSMenuItem(title: sample.name, action: #selector(loadSampleFromMenu(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = sample
            samplesMenu.addItem(item)
        }
        samplesItem.submenu = samplesMenu
        menu.addItem(samplesItem)

        menu.addItem(.separator())
        menu.addItem(withTitle: "Open…", action: #selector(openFile), keyEquivalent: "").target = self
        menu.addItem(withTitle: "Save As…", action: #selector(saveFile), keyEquivalent: "").target = self

        button.menu = menu
        button.action = #selector(showFileMenu(_:))
        button.target = self

        return button
    }

    // MARK: - Actions

    @objc private func showFileMenu(_ sender: NSButton) {
        guard let menu = sender.menu else { return }
        menu.popUp(positioning: nil, at: NSPoint(x: 0, y: sender.bounds.height), in: sender)
    }

    @objc private func loadSampleFromMenu(_ sender: NSMenuItem) {
        guard let sample = sender.representedObject as? BASICSample else { return }
        loadSample(sample)
    }

    func loadSample(_ sample: BASICSample) {
        connection.basicScratchpadCode = sample.code
        editorManager.setText(sample.code)
        errorLabel.isHidden = true
        updateLineCount()
    }

    @objc func toggleSpecialCodes() {
        if let existing = specialCodesView {
            existing.removeFromSuperview()
            specialCodesView = nil
            // Reconnect editor to status bar
            statusBarToCodesConstraint?.isActive = false
            statusBarToEditorConstraint?.isActive = true
        } else {
            let codesView = createSpecialCodesView()
            codesView.translatesAutoresizingMaskIntoConstraints = false
            view.addSubview(codesView)

            // Find the status bar and editor scroll view
            guard let statusBar = view.subviews.first(where: { $0 is NSStackView && $0 !== codesView }),
                  let scrollView = view.subviews.first(where: { $0 is NSScrollView }) else { return }

            // Disconnect editor from status bar, insert codes view between them
            statusBarToEditorConstraint?.isActive = false

            let codesToStatus = statusBar.topAnchor.constraint(equalTo: codesView.bottomAnchor)
            let editorToCodes = codesView.topAnchor.constraint(equalTo: scrollView.bottomAnchor)
            statusBarToCodesConstraint = codesToStatus

            NSLayoutConstraint.activate([
                editorToCodes,
                codesView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
                codesView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
                codesToStatus,
            ])

            specialCodesView = codesView
        }
    }

    private func createSpecialCodesView() -> NSView {
        let flowView = FlowLayoutView()
        flowView.wantsLayer = true
        flowView.layer?.backgroundColor = NSColor.black.withAlphaComponent(0.3).cgColor
        flowView.spacing = 4
        flowView.padding = NSEdgeInsets(top: 6, left: 6, bottom: 6, right: 6)

        for (code, _) in BASICTokenizer.specialCodes {
            let button = NSButton(title: code, target: self, action: #selector(insertSpecialCode(_:)))
            button.bezelStyle = .toolbar
            button.controlSize = .small
            button.font = .monospacedSystemFont(ofSize: 9, weight: .medium)
            button.contentTintColor = .systemPink
            button.identifier = NSUserInterfaceItemIdentifier(code)
            flowView.addArrangedSubview(button)
        }

        return flowView
    }

    @objc private func insertSpecialCode(_ sender: NSButton) {
        guard let code = sender.identifier?.rawValue,
              let textView = editorManager.textView else { return }

        let insertionPoint = textView.selectedRange().location
        textView.insertText(code, replacementRange: textView.selectedRange())

        // Update the connection's stored code
        connection.basicScratchpadCode = textView.string
        updateLineCount()
    }

    func showFileMenu(from sender: Any?) {
        // Find the toolbar item view and show the menu from it
        guard let toolbar = view.window?.toolbar else { return }
        for item in toolbar.items where item.itemIdentifier == .basicFileMenu {
            if let button = item.view as? NSButton ?? (item.view?.subviews.first as? NSButton) {
                showFileMenu(button)
                return
            }
        }
    }

    @objc func openFile() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [
            UTType(filenameExtension: "bas"),
            UTType.plainText,
        ].compactMap { $0 }
        panel.allowsMultipleSelection = false
        if panel.runModal() == .OK, let url = panel.url,
           let content = try? String(contentsOf: url, encoding: .utf8) {
            connection.basicScratchpadCode = content
            editorManager.setText(content)
            errorLabel.isHidden = true
            updateLineCount()
        }
    }

    @objc func saveFile() {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [UTType(filenameExtension: "bas") ?? .plainText]
        panel.nameFieldStringValue = "program.bas"
        if panel.runModal() == .OK, let url = panel.url {
            try? connection.basicScratchpadCode.write(to: url, atomically: true, encoding: .utf8)
        }
    }

    @objc func uploadAndRun() {
        guard let client = connection.apiClient else { return }
        guard !isUploading else { return }

        let code = connection.basicScratchpadCode
        errorLabel.isHidden = true
        isUploading = true

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
                errorLabel.stringValue = error.localizedDescription
                errorLabel.isHidden = false
            }
            isUploading = false
        }
    }
}

private final class FlippedView: NSView {
    override var isFlipped: Bool { true }
}

private final class FlowLayoutView: NSView {
    var spacing: CGFloat = 4
    var padding = NSEdgeInsets(top: 6, left: 6, bottom: 6, right: 6)
    private var arrangedSubviews: [NSView] = []

    override var isFlipped: Bool { true }

    func addArrangedSubview(_ view: NSView) {
        arrangedSubviews.append(view)
        addSubview(view)
    }

    override func layout() {
        super.layout()
        layoutSubviewsFlow()
    }

    private func layoutSubviewsFlow() {
        let availableWidth = bounds.width - padding.left - padding.right
        guard availableWidth > 0 else { return }

        var x = padding.left
        var y = padding.top
        var rowHeight: CGFloat = 0

        for subview in arrangedSubviews {
            let size = subview.fittingSize

            if x + size.width > bounds.width - padding.right && x > padding.left {
                // Wrap to next row
                x = padding.left
                y += rowHeight + spacing
                rowHeight = 0
            }

            subview.frame = CGRect(x: x, y: y, width: size.width, height: size.height)
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }

        let totalHeight = y + rowHeight + padding.bottom
        if abs(intrinsicHeight - totalHeight) > 1 {
            intrinsicHeight = totalHeight
            invalidateIntrinsicContentSize()
        }
    }

    private var intrinsicHeight: CGFloat = 0

    override var intrinsicContentSize: NSSize {
        NSSize(width: NSView.noIntrinsicMetric, height: intrinsicHeight)
    }
}
