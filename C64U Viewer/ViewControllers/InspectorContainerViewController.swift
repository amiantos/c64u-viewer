// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.

import AppKit
internal import UniformTypeIdentifiers

/// Container for the right inspector panel. Holds a segmented control
/// at the top for switching between BASIC / System / Display & Audio,
/// an optional action bar for tool-specific buttons, and the active
/// panel's view controller below.
final class InspectorContainerViewController: NSViewController {
    let connection: C64Connection
    var onPanelChanged: ((InspectorPanel) -> Void)?
    private(set) var activePanel: InspectorPanel = .system

    private var segmentedControl: NSSegmentedControl!
    private var actionBar: NSStackView!
    private var actionBarSeparator: NSBox!
    private var contentContainer: NSView!
    private var currentChild: NSViewController?

    init(connection: C64Connection) {
        self.connection = connection
        super.init(nibName: nil, bundle: nil)
        self.title = "Inspector"
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    override func loadView() {
        let container = FlippedBackgroundView()
        container.backgroundColor = .controlBackgroundColor

        // Segmented control for panel switching
        segmentedControl = NSSegmentedControl(labels: InspectorPanel.allCases.map(\.label), trackingMode: .selectOne, target: self, action: #selector(segmentChanged(_:)))
        segmentedControl.selectedSegment = InspectorPanel.allCases.firstIndex(of: activePanel) ?? 0
        segmentedControl.segmentStyle = .automatic
        segmentedControl.translatesAutoresizingMaskIntoConstraints = false

        // Action bar for tool-specific buttons (empty when not needed)
        actionBar = NSStackView()
        actionBar.orientation = .horizontal
        actionBar.spacing = 4
        actionBar.translatesAutoresizingMaskIntoConstraints = false
        actionBar.edgeInsets = NSEdgeInsets(top: 2, left: 8, bottom: 2, right: 8)
        actionBar.setContentHuggingPriority(.required, for: .vertical)

        actionBarSeparator = NSBox()
        actionBarSeparator.boxType = .separator
        actionBarSeparator.translatesAutoresizingMaskIntoConstraints = false

        // Content area for the active panel
        contentContainer = NSView()
        contentContainer.translatesAutoresizingMaskIntoConstraints = false

        container.addSubview(segmentedControl)
        container.addSubview(actionBar)
        container.addSubview(actionBarSeparator)
        container.addSubview(contentContainer)

        NSLayoutConstraint.activate([
            segmentedControl.topAnchor.constraint(equalTo: container.safeAreaLayoutGuide.topAnchor, constant: 8),
            segmentedControl.centerXAnchor.constraint(equalTo: container.centerXAnchor),

            actionBar.topAnchor.constraint(equalTo: segmentedControl.bottomAnchor, constant: 4),
            actionBar.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            actionBar.trailingAnchor.constraint(equalTo: container.trailingAnchor),

            actionBarSeparator.topAnchor.constraint(equalTo: actionBar.bottomAnchor, constant: 2),
            actionBarSeparator.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            actionBarSeparator.trailingAnchor.constraint(equalTo: container.trailingAnchor),

            contentContainer.topAnchor.constraint(equalTo: actionBarSeparator.bottomAnchor),
            contentContainer.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            contentContainer.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            contentContainer.bottomAnchor.constraint(equalTo: container.bottomAnchor),
        ])

        self.view = container

        // Viewer mode: remove segmented control, only show Display & Audio
        if connection.connectionMode == .viewer {
            segmentedControl.removeFromSuperview()
            actionBar.topAnchor.constraint(equalTo: container.safeAreaLayoutGuide.topAnchor, constant: 4).isActive = true
            activePanel = .displayAndAudio
        }

        showPanel(activePanel)
    }

    // MARK: - Panel Switching

    @objc private func segmentChanged(_ sender: NSSegmentedControl) {
        let panels = InspectorPanel.allCases
        guard sender.selectedSegment >= 0, sender.selectedSegment < panels.count else { return }
        let panel = panels[sender.selectedSegment]
        showPanel(panel)
    }

    private func showPanel(_ panel: InspectorPanel) {
        // Remove current child
        if let child = currentChild {
            child.view.removeFromSuperview()
            child.removeFromParent()
            currentChild = nil
        }

        activePanel = panel

        // Create new child view controller
        let child: NSViewController
        switch panel {
        case .basicScratchpad:
            child = BASICScratchpadViewController(connection: connection)
        case .system:
            child = SystemViewController(connection: connection)
        case .displayAndAudio:
            child = DisplayAudioViewController(connection: connection)
        }

        addChild(child)
        child.view.autoresizingMask = [.width, .height]
        child.view.frame = contentContainer.bounds
        contentContainer.addSubview(child.view)

        currentChild = child

        // Update action bar
        updateActionBar(for: panel)

        onPanelChanged?(panel)
    }

    // MARK: - Action Bar

    private func updateActionBar(for panel: InspectorPanel) {
        // Remove existing action bar items
        for view in actionBar.arrangedSubviews {
            actionBar.removeArrangedSubview(view)
            view.removeFromSuperview()
        }

        switch panel {
        case .basicScratchpad:
            guard let basicVC = currentChild as? BASICScratchpadViewController else { break }

            let titleLabel = NSTextField(labelWithString: basicVC.title ?? "BASIC Scratchpad")
            titleLabel.font = .systemFont(ofSize: 11, weight: .medium)
            titleLabel.textColor = .secondaryLabelColor
            titleLabel.lineBreakMode = .byTruncatingMiddle
            titleLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)

            let codesButton = NSButton(image: NSImage(systemSymbolName: "character.bubble", accessibilityDescription: "Special Codes")!, target: basicVC, action: #selector(BASICScratchpadViewController.toggleSpecialCodes))
            codesButton.bezelStyle = .toolbar
            codesButton.controlSize = .small

            let fileButton = createBasicFileMenu(basicVC: basicVC)

            let runButton = NSButton(image: NSImage(systemSymbolName: "play.fill", accessibilityDescription: "Run")!, target: basicVC, action: #selector(BASICScratchpadViewController.uploadAndRun))
            runButton.bezelStyle = .toolbar
            runButton.controlSize = .small

            actionBar.addArrangedSubview(titleLabel)
            actionBar.addArrangedSubview(NSView()) // spacer
            actionBar.addArrangedSubview(codesButton)
            actionBar.addArrangedSubview(fileButton)
            actionBar.addArrangedSubview(runButton)

            // Update title when it changes
            basicVC.onTitleChanged = { [weak titleLabel] newTitle in
                titleLabel?.stringValue = newTitle
            }

        case .system:
            guard let systemVC = currentChild as? SystemViewController else { break }

            let titleLabel = NSTextField(labelWithString: "System")
            titleLabel.font = .systemFont(ofSize: 11, weight: .medium)
            titleLabel.textColor = .secondaryLabelColor
            titleLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)

            let refreshButton = NSButton(image: NSImage(systemSymbolName: "arrow.clockwise", accessibilityDescription: "Refresh")!, target: systemVC, action: #selector(SystemViewController.refreshAll))
            refreshButton.bezelStyle = .toolbar
            refreshButton.controlSize = .small
            refreshButton.toolTip = "Refresh all device data"

            let saveButton = NSButton(image: NSImage(systemSymbolName: "square.and.arrow.down", accessibilityDescription: "Save to Flash")!, target: systemVC, action: #selector(SystemViewController.saveToFlash))
            saveButton.bezelStyle = .toolbar
            saveButton.controlSize = .small
            saveButton.toolTip = "Save configuration to flash"

            let resetButton = NSButton(image: NSImage(systemSymbolName: "arrow.uturn.backward", accessibilityDescription: "Reset to Default")!, target: systemVC, action: #selector(SystemViewController.resetToDefault))
            resetButton.bezelStyle = .toolbar
            resetButton.controlSize = .small
            resetButton.toolTip = "Reset configuration to defaults"

            actionBar.addArrangedSubview(titleLabel)
            actionBar.addArrangedSubview(NSView()) // spacer
            actionBar.addArrangedSubview(refreshButton)
            actionBar.addArrangedSubview(saveButton)
            actionBar.addArrangedSubview(resetButton)

        case .displayAndAudio:
            actionBar.isHidden = true
            actionBarSeparator.isHidden = true
            return
        }

        actionBar.isHidden = false
        actionBarSeparator.isHidden = false
    }

    private func createBasicFileMenu(basicVC: BASICScratchpadViewController) -> NSButton {
        let button = NSButton(image: NSImage(systemSymbolName: "doc", accessibilityDescription: "File")!, target: nil, action: nil)
        button.bezelStyle = .toolbar
        button.controlSize = .small

        let menu = NSMenu()
        menu.addItem(withTitle: "New", action: #selector(BASICScratchpadViewController.newFile), keyEquivalent: "").target = basicVC
        menu.addItem(withTitle: "Open…", action: #selector(BASICScratchpadViewController.openFile), keyEquivalent: "").target = basicVC
        menu.addItem(.separator())
        menu.addItem(withTitle: "Save", action: #selector(BASICScratchpadViewController.saveFile), keyEquivalent: "").target = basicVC
        menu.addItem(withTitle: "Save As…", action: #selector(BASICScratchpadViewController.saveFileAs), keyEquivalent: "").target = basicVC
        menu.addItem(.separator())

        let samplesItem = NSMenuItem(title: "Samples", action: nil, keyEquivalent: "")
        let samplesMenu = NSMenu()
        for sample in BASICSamples.all {
            let item = NSMenuItem(title: sample.name, action: #selector(BASICScratchpadViewController.loadSampleFromMenu(_:)), keyEquivalent: "")
            item.target = basicVC
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

    @objc private func showFileMenu(_ sender: NSButton) {
        guard let menu = sender.menu else { return }
        menu.popUp(positioning: nil, at: NSPoint(x: 0, y: sender.bounds.height), in: sender)
    }
}
