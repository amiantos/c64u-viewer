// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain name at https://mozilla.org/MPL/2.0/.

import AppKit

final class KeyStripView: NSView {
    private weak var forwarder: C64KeyboardForwarder?
    var onMenuButton: (() -> Void)?

    init(forwarder: C64KeyboardForwarder) {
        self.forwarder = forwarder
        super.init(frame: .zero)
        setupViews()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    private func setupViews() {
        wantsLayer = true
        layer?.backgroundColor = NSColor.black.withAlphaComponent(0.6).cgColor

        let topRow = NSStackView()
        topRow.orientation = .horizontal
        topRow.spacing = 2
        topRow.translatesAutoresizingMaskIntoConstraints = false

        // F1-F8
        for key in [SpecialKey.f1, .f2, .f3, .f4, .f5, .f6, .f7, .f8] {
            topRow.addArrangedSubview(makeKeyButton(key))
        }

        let bottomRow = NSStackView()
        bottomRow.orientation = .horizontal
        bottomRow.spacing = 2
        bottomRow.translatesAutoresizingMaskIntoConstraints = false

        // Menu button
        let menuBtn = NSButton(title: "MENU", target: self, action: #selector(menuTapped))
        menuBtn.font = .monospacedSystemFont(ofSize: 9, weight: .medium)
        menuBtn.bezelStyle = .toolbar
        menuBtn.contentTintColor = .systemBlue
        bottomRow.addArrangedSubview(menuBtn)

        // Special keys
        for key in [SpecialKey.runStop, .home, .clr, .inst, .instDel,
                    .cursorUp, .cursorDown, .cursorLeft, .cursorRight,
                    .pound, .upArrow, .leftArrow, .shiftReturn] {
            bottomRow.addArrangedSubview(makeKeyButton(key))
        }

        let stack = NSStackView(views: [topRow, bottomRow])
        stack.orientation = .vertical
        stack.spacing = 2
        stack.translatesAutoresizingMaskIntoConstraints = false
        stack.edgeInsets = NSEdgeInsets(top: 4, left: 8, bottom: 4, right: 8)

        addSubview(stack)
        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: topAnchor),
            stack.bottomAnchor.constraint(equalTo: bottomAnchor),
            stack.leadingAnchor.constraint(equalTo: leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: trailingAnchor),
        ])
    }

    private func makeKeyButton(_ key: SpecialKey) -> NSButton {
        let button = NSButton(title: key.rawValue, target: self, action: #selector(keyTapped(_:)))
        button.font = .monospacedSystemFont(ofSize: 9, weight: .medium)
        button.bezelStyle = .toolbar
        button.tag = Int(key.petscii)
        return button
    }

    @objc private func keyTapped(_ sender: NSButton) {
        forwarder?.sendKey(UInt8(sender.tag))
    }

    @objc private func menuTapped() {
        onMenuButton?()
    }
}
