// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.

import AppKit

protocol OpenDeviceWindowControllerDelegate: AnyObject {
    func openDeviceWindowController(_ controller: OpenDeviceWindowController, didConnectWith connection: C64Connection)
}

final class OpenDeviceWindowController: NSWindowController, NSWindowDelegate {
    weak var delegate: OpenDeviceWindowControllerDelegate?

    private let recentConnections = RecentConnections()

    // Toolbox fields
    private let ipField = NSTextField()
    private let connectToolboxButton = NSButton(title: "Connect", target: nil, action: nil)
    private let toolboxErrorLabel = NSTextField(wrappingLabelWithString: "")

    // Discovery
    private let scanner = DeviceScanner()
    private var discoveredDevices: [DiscoveredDevice] = []
    private var discoveredDevicesStack: NSStackView!
    private var scanningIndicator: NSProgressIndicator!
    private var scanTimer: Timer?
    private var hasCompletedFirstScan = false

    // Viewer fields
    private let videoPortField = NSTextField()
    private let audioPortField = NSTextField()
    private let listenButton = NSButton(title: "Listen", target: nil, action: nil)

    // Tab switching
    private var segmentedControl: PillSegmentedControl!
    private var tabContainer: NSView!
    private var toolboxView: NSView!
    private var viewerView: NSView!

    init() {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 420, height: 420),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        window.title = "Open Device"
        window.center()
        window.isReleasedWhenClosed = false

        super.init(window: window)
        window.delegate = self
        setupUI()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    // MARK: - UI Setup

    private func setupUI() {
        guard let contentView = window?.contentView else { return }

        segmentedControl = PillSegmentedControl(labels: ["Toolbox", "Viewer"])
        segmentedControl.target = self
        segmentedControl.action = #selector(tabChanged(_:))

        tabContainer = NSView()
        tabContainer.translatesAutoresizingMaskIntoConstraints = false

        toolboxView = makeToolboxView()
        viewerView = makeViewerView()

        contentView.addSubview(segmentedControl)
        contentView.addSubview(tabContainer)

        NSLayoutConstraint.activate([
            segmentedControl.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 12),
            segmentedControl.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 12),
            segmentedControl.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -12),

            tabContainer.topAnchor.constraint(equalTo: segmentedControl.bottomAnchor, constant: 12),
            tabContainer.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 12),
            tabContainer.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -12),
            tabContainer.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -12),
        ])

        showTab(0)
    }

    @objc private func tabChanged(_ sender: PillSegmentedControl) {
        showTab(sender.selectedSegment)
    }

    private func showTab(_ index: Int) {
        toolboxView.removeFromSuperview()
        viewerView.removeFromSuperview()

        let activeView = index == 0 ? toolboxView! : viewerView!
        activeView.translatesAutoresizingMaskIntoConstraints = false
        tabContainer.addSubview(activeView)
        NSLayoutConstraint.activate([
            activeView.topAnchor.constraint(equalTo: tabContainer.topAnchor),
            activeView.leadingAnchor.constraint(equalTo: tabContainer.leadingAnchor),
            activeView.trailingAnchor.constraint(equalTo: tabContainer.trailingAnchor),
            activeView.bottomAnchor.constraint(equalTo: tabContainer.bottomAnchor),
        ])

        if index == 0 {
            startAutoScan()
        } else {
            stopAutoScan()
        }
    }

    private func makeToolboxView() -> NSView {
        let container = NSView()

        // Help text
        let helpText = NSTextField(wrappingLabelWithString: "To use Toolbox mode, your Ultimate device needs to be connected to Ethernet, and you need to enable FTP File Service and Web Remote Control Service in the Network Services menu.")
        helpText.font = .systemFont(ofSize: 11)
        helpText.textColor = .secondaryLabelColor
        helpText.translatesAutoresizingMaskIntoConstraints = false

        // Discovered devices header
        let discoveredLabel = NSTextField(labelWithString: "Discovered Devices:")
        discoveredLabel.font = .systemFont(ofSize: 11, weight: .semibold)

        scanningIndicator = NSProgressIndicator()
        scanningIndicator.style = .spinning
        scanningIndicator.controlSize = .mini
        scanningIndicator.isHidden = true

        let headerRow = NSStackView(views: [discoveredLabel, scanningIndicator])
        headerRow.orientation = .horizontal
        headerRow.spacing = 6
        headerRow.translatesAutoresizingMaskIntoConstraints = false

        // Discovered devices container
        discoveredDevicesStack = NSStackView()
        discoveredDevicesStack.orientation = .vertical
        discoveredDevicesStack.alignment = .leading
        discoveredDevicesStack.spacing = 4
        discoveredDevicesStack.translatesAutoresizingMaskIntoConstraints = false

        let scanningLabel = NSTextField(labelWithString: "Scanning...")
        scanningLabel.font = .systemFont(ofSize: 11)
        scanningLabel.textColor = .secondaryLabelColor
        discoveredDevicesStack.addArrangedSubview(scanningLabel)

        // Manual connect section
        let manualLabel = NSTextField(labelWithString: "Manual Connect:")
        manualLabel.font = .systemFont(ofSize: 11, weight: .semibold)
        manualLabel.translatesAutoresizingMaskIntoConstraints = false

        ipField.placeholderString = "192.168.1.24"
        ipField.translatesAutoresizingMaskIntoConstraints = false

        // Pre-fill from most recent session
        if let lastSession = recentConnections.toolboxSessions.first {
            ipField.stringValue = lastSession.ipAddress
        }

        toolboxErrorLabel.translatesAutoresizingMaskIntoConstraints = false
        toolboxErrorLabel.textColor = .systemRed
        toolboxErrorLabel.isHidden = true

        connectToolboxButton.translatesAutoresizingMaskIntoConstraints = false
        connectToolboxButton.bezelStyle = .rounded
        connectToolboxButton.keyEquivalent = "\r"
        connectToolboxButton.target = self
        connectToolboxButton.action = #selector(connectToolbox)

        let manualRow = NSStackView(views: [ipField, connectToolboxButton])
        manualRow.orientation = .horizontal
        manualRow.spacing = 8
        manualRow.translatesAutoresizingMaskIntoConstraints = false

        let views: [NSView] = [
            headerRow,
            discoveredDevicesStack,
            manualLabel,
            manualRow,
            toolboxErrorLabel,
            helpText,
        ]

        let stack = NSStackView(views: views)
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 8
        stack.translatesAutoresizingMaskIntoConstraints = false

        // Add extra spacing before the manual connect section
        stack.setCustomSpacing(16, after: discoveredDevicesStack)
        // Add extra spacing before the help text
        stack.setCustomSpacing(24, after: manualRow)
        stack.setCustomSpacing(24, after: toolboxErrorLabel)

        container.addSubview(stack)

        let trailing = stack.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -16)
        trailing.priority = .defaultHigh
        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: container.topAnchor, constant: 16),
            stack.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 16),
            trailing,
            helpText.widthAnchor.constraint(equalTo: stack.widthAnchor),
            manualRow.widthAnchor.constraint(equalTo: stack.widthAnchor),
        ])

        return container
    }

    private func makeViewerView() -> NSView {
        let container = NSView()

        let videoLabel = NSTextField(labelWithString: "Video Port:")
        videoPortField.placeholderString = "11000"
        videoPortField.stringValue = "11000"
        videoPortField.translatesAutoresizingMaskIntoConstraints = false
        videoLabel.translatesAutoresizingMaskIntoConstraints = false

        let audioLabel = NSTextField(labelWithString: "Audio Port:")
        audioPortField.placeholderString = "11001"
        audioPortField.stringValue = "11001"
        audioPortField.translatesAutoresizingMaskIntoConstraints = false
        audioLabel.translatesAutoresizingMaskIntoConstraints = false

        listenButton.translatesAutoresizingMaskIntoConstraints = false
        listenButton.bezelStyle = .rounded
        listenButton.keyEquivalent = "\r"
        listenButton.target = self
        listenButton.action = #selector(startListening)

        var views: [NSView] = [
            videoLabel, videoPortField,
            audioLabel, audioPortField,
            listenButton,
        ]

        // Recent connections
        if !recentConnections.viewerSessions.isEmpty {
            let recentLabel = NSTextField(labelWithString: "Recent:")
            recentLabel.font = .systemFont(ofSize: 11, weight: .semibold)
            recentLabel.translatesAutoresizingMaskIntoConstraints = false
            views.append(recentLabel)

            for (index, session) in recentConnections.viewerSessions.enumerated() {
                let button = NSButton(title: "Video: \(session.videoPort)  Audio: \(session.audioPort)", target: self, action: #selector(connectRecentViewer(_:)))
                button.bezelStyle = .inline
                button.controlSize = .small
                button.tag = index
                button.translatesAutoresizingMaskIntoConstraints = false
                views.append(button)
            }
        }

        let stack = NSStackView(views: views)
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 8
        stack.translatesAutoresizingMaskIntoConstraints = false

        container.addSubview(stack)

        let trailing = stack.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -16)
        trailing.priority = .defaultHigh
        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: container.topAnchor, constant: 16),
            stack.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 16),
            trailing,
            videoPortField.widthAnchor.constraint(equalTo: stack.widthAnchor),
            audioPortField.widthAnchor.constraint(equalTo: stack.widthAnchor),
        ])

        return container
    }

    // MARK: - Auto-Scan

    private func startAutoScan() {
        guard scanTimer == nil else { return }
        performScan()
        scanTimer = Timer.scheduledTimer(withTimeInterval: 5.0, repeats: true) { [weak self] _ in
            self?.performScan()
        }
    }

    private func stopAutoScan() {
        scanTimer?.invalidate()
        scanTimer = nil
        scanner.stop()
    }

    private func performScan() {
        scanningIndicator.isHidden = false
        scanningIndicator.startAnimation(nil)

        scanner.scanAll { [weak self] devices in
            guard let self else { return }
            self.discoveredDevices = devices
            self.hasCompletedFirstScan = true
            self.rebuildDiscoveredDevicesUI()
        }
    }

    private func rebuildDiscoveredDevicesUI() {
        for view in discoveredDevicesStack.arrangedSubviews {
            discoveredDevicesStack.removeArrangedSubview(view)
            view.removeFromSuperview()
        }

        if discoveredDevices.isEmpty {
            let label = NSTextField(labelWithString: hasCompletedFirstScan ? "No devices found" : "Scanning...")
            label.font = .systemFont(ofSize: 11)
            label.textColor = .secondaryLabelColor
            discoveredDevicesStack.addArrangedSubview(label)
        } else {
            for device in discoveredDevices {
                let button = NSButton(
                    title: "\(device.info.product) — \(device.info.hostname) (\(device.ipAddress))",
                    target: self,
                    action: #selector(connectDiscoveredDevice(_:))
                )
                button.bezelStyle = .inline
                button.controlSize = .small
                button.identifier = NSUserInterfaceItemIdentifier(device.ipAddress)
                button.translatesAutoresizingMaskIntoConstraints = false
                discoveredDevicesStack.addArrangedSubview(button)
            }
        }

        // Keep indicator spinning to show scanning is ongoing
        scanningIndicator.isHidden = scanTimer == nil
    }

    // MARK: - Actions

    @objc private func connectToolbox() {
        let ip = ipField.stringValue.trimmingCharacters(in: .whitespaces)
        guard !ip.isEmpty else { return }

        toolboxErrorLabel.isHidden = true
        connectToolboxButton.isEnabled = false

        attemptConnection(ip: ip, password: nil, savePassword: false)
    }

    private func attemptConnection(ip: String, password: String?, savePassword: Bool) {
        let connection = C64Connection()
        connection.connectToolbox(ip: ip, password: password, savePassword: savePassword) { [weak self] success in
            guard let self else { return }
            if success {
                self.stopAutoScan()
                self.delegate?.openDeviceWindowController(self, didConnectWith: connection)
            } else if connection.connectionError == "Incorrect password" {
                self.showPasswordModal(for: ip)
            } else {
                self.toolboxErrorLabel.stringValue = connection.connectionError ?? "Connection failed"
                self.toolboxErrorLabel.isHidden = false
            }
            self.connectToolboxButton.isEnabled = true
        }
    }

    private func showPasswordModal(for ip: String) {
        guard let window = self.window else { return }

        let alert = NSAlert()
        alert.messageText = "Password Required"
        alert.informativeText = "The device at \(ip) requires a password."
        alert.alertStyle = .informational
        alert.addButton(withTitle: "Connect")
        alert.addButton(withTitle: "Cancel")

        let accessoryView = NSView(frame: NSRect(x: 0, y: 0, width: 260, height: 54))

        let passwordField = NSSecureTextField(frame: NSRect(x: 0, y: 28, width: 260, height: 22))
        passwordField.placeholderString = "Password"
        accessoryView.addSubview(passwordField)

        let saveCheckbox = NSButton(checkboxWithTitle: "Save Password", target: nil, action: nil)
        saveCheckbox.frame = NSRect(x: 0, y: 0, width: 260, height: 22)
        accessoryView.addSubview(saveCheckbox)

        alert.accessoryView = accessoryView

        alert.beginSheetModal(for: window) { [weak self] response in
            guard response == .alertFirstButtonReturn else { return }
            let password = passwordField.stringValue
            let save = saveCheckbox.state == .on
            guard !password.isEmpty else { return }
            self?.connectToolboxButton.isEnabled = false
            self?.attemptConnection(ip: ip, password: password, savePassword: save)
        }

        DispatchQueue.main.async {
            passwordField.becomeFirstResponder()
        }
    }

    @objc private func connectDiscoveredDevice(_ sender: NSButton) {
        guard let ip = sender.identifier?.rawValue else { return }
        ipField.stringValue = ip
        connectToolbox()
    }

    @objc private func startListening() {
        let videoPort = UInt16(videoPortField.stringValue) ?? 11000
        let audioPort = UInt16(audioPortField.stringValue) ?? 11001

        let connection = C64Connection()
        connection.listen(videoPort: videoPort, audioPort: audioPort)
        delegate?.openDeviceWindowController(self, didConnectWith: connection)
    }

    @objc private func connectRecentViewer(_ sender: NSButton) {
        let index = sender.tag
        guard index >= 0, index < recentConnections.viewerSessions.count else { return }
        let session = recentConnections.viewerSessions[index]

        videoPortField.stringValue = "\(session.videoPort)"
        audioPortField.stringValue = "\(session.audioPort)"
        startListening()
    }

    // MARK: - NSWindowDelegate

    func windowWillClose(_ notification: Notification) {
        stopAutoScan()
    }
}
