// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.

import AppKit

protocol OpenDeviceWindowControllerDelegate: AnyObject {
    func openDeviceWindowController(_ controller: OpenDeviceWindowController, didConnectWith connection: C64Connection)
}

final class OpenDeviceWindowController: NSWindowController {
    weak var delegate: OpenDeviceWindowControllerDelegate?

    private let recentConnections = RecentConnections()

    // Toolbox fields
    private let ipField = NSTextField()
    private let passwordField = NSSecureTextField()
    private let savePasswordCheckbox = NSButton(checkboxWithTitle: "Save Password", target: nil, action: nil)
    private let connectToolboxButton = NSButton(title: "Connect", target: nil, action: nil)
    private let toolboxErrorLabel = NSTextField(wrappingLabelWithString: "")

    // Viewer fields
    private let videoPortField = NSTextField()
    private let audioPortField = NSTextField()
    private let listenButton = NSButton(title: "Listen", target: nil, action: nil)

    // Tab view
    private let tabView = NSTabView()

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
        setupUI()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    // MARK: - UI Setup

    private func setupUI() {
        guard let contentView = window?.contentView else { return }

        tabView.translatesAutoresizingMaskIntoConstraints = false

        let toolboxTab = NSTabViewItem(identifier: "toolbox")
        toolboxTab.label = "Toolbox"
        toolboxTab.view = makeToolboxView()

        let viewerTab = NSTabViewItem(identifier: "viewer")
        viewerTab.label = "Viewer"
        viewerTab.view = makeViewerView()

        tabView.addTabViewItem(toolboxTab)
        tabView.addTabViewItem(viewerTab)

        contentView.addSubview(tabView)
        NSLayoutConstraint.activate([
            tabView.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 12),
            tabView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 12),
            tabView.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -12),
            tabView.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -12),
        ])
    }

    private func makeToolboxView() -> NSView {
        let container = NSView()

        let ipLabel = NSTextField(labelWithString: "IP Address:")
        ipField.placeholderString = "192.168.1.24"
        ipField.translatesAutoresizingMaskIntoConstraints = false
        ipLabel.translatesAutoresizingMaskIntoConstraints = false

        let passwordLabel = NSTextField(labelWithString: "Password (optional):")
        passwordField.placeholderString = "Password"
        passwordField.translatesAutoresizingMaskIntoConstraints = false
        passwordLabel.translatesAutoresizingMaskIntoConstraints = false

        savePasswordCheckbox.translatesAutoresizingMaskIntoConstraints = false

        toolboxErrorLabel.translatesAutoresizingMaskIntoConstraints = false
        toolboxErrorLabel.textColor = .systemRed
        toolboxErrorLabel.isHidden = true

        connectToolboxButton.translatesAutoresizingMaskIntoConstraints = false
        connectToolboxButton.bezelStyle = .rounded
        connectToolboxButton.keyEquivalent = "\r"
        connectToolboxButton.target = self
        connectToolboxButton.action = #selector(connectToolbox)

        var views: [NSView] = [
            ipLabel, ipField,
            passwordLabel, passwordField,
            savePasswordCheckbox,
            toolboxErrorLabel,
            connectToolboxButton,
        ]

        // Recent connections
        if !recentConnections.toolboxSessions.isEmpty {
            let recentLabel = NSTextField(labelWithString: "Recent:")
            recentLabel.font = .systemFont(ofSize: 11, weight: .semibold)
            recentLabel.translatesAutoresizingMaskIntoConstraints = false
            views.append(recentLabel)

            for session in recentConnections.toolboxSessions {
                let title = session.savePassword ? "\(session.ipAddress) 🔑" : session.ipAddress
                let button = NSButton(title: title, target: self, action: #selector(connectRecentToolbox(_:)))
                button.bezelStyle = .inline
                button.controlSize = .small
                button.tag = recentConnections.toolboxSessions.firstIndex(of: session) ?? 0
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
            ipField.widthAnchor.constraint(equalTo: stack.widthAnchor),
            passwordField.widthAnchor.constraint(equalTo: stack.widthAnchor),
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

    // MARK: - Actions

    @objc private func connectToolbox() {
        let ip = ipField.stringValue.trimmingCharacters(in: .whitespaces)
        guard !ip.isEmpty else { return }

        let password = passwordField.stringValue.isEmpty ? nil : passwordField.stringValue
        let savePassword = savePasswordCheckbox.state == .on

        toolboxErrorLabel.isHidden = true
        connectToolboxButton.isEnabled = false

        let connection = C64Connection()
        connection.connectToolbox(ip: ip, password: password, savePassword: savePassword) { [weak self] success in
            guard let self else { return }
            if success {
                self.delegate?.openDeviceWindowController(self, didConnectWith: connection)
            } else {
                self.toolboxErrorLabel.stringValue = connection.connectionError ?? "Connection failed"
                self.toolboxErrorLabel.isHidden = false
            }
            self.connectToolboxButton.isEnabled = true
        }
    }

    @objc private func startListening() {
        let videoPort = UInt16(videoPortField.stringValue) ?? 11000
        let audioPort = UInt16(audioPortField.stringValue) ?? 11001

        let connection = C64Connection()
        connection.listen(videoPort: videoPort, audioPort: audioPort)
        delegate?.openDeviceWindowController(self, didConnectWith: connection)
    }

    @objc private func connectRecentToolbox(_ sender: NSButton) {
        let index = sender.tag
        guard index >= 0, index < recentConnections.toolboxSessions.count else { return }
        let session = recentConnections.toolboxSessions[index]

        ipField.stringValue = session.ipAddress
        if let password = session.password {
            passwordField.stringValue = password
            savePasswordCheckbox.state = .on
        } else {
            passwordField.stringValue = ""
            savePasswordCheckbox.state = .off
        }
        connectToolbox()
    }

    @objc private func connectRecentViewer(_ sender: NSButton) {
        let index = sender.tag
        guard index >= 0, index < recentConnections.viewerSessions.count else { return }
        let session = recentConnections.viewerSessions[index]

        videoPortField.stringValue = "\(session.videoPort)"
        audioPortField.stringValue = "\(session.audioPort)"
        startListening()
    }
}
