// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.

import AppKit

/// Container for the right inspector panel. Holds a segmented control
/// at the top for switching between System / Display & Audio,
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

        actionBar.isHidden = true
        actionBarSeparator.isHidden = true
    }

}
