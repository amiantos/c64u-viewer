// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.

import AppKit
import MetalKit

final class VideoViewController: NSViewController {
    let connection: C64Connection
    private var mtkView: MTKView!
    private var statusBar: StatusBarView!
    private var keyStripView: KeyStripView?
    private var statusTimer: DispatchSourceTimer?

    private let aspectRatio: CGFloat = 384.0 / 272.0

    var onMenuButton: (() -> Void)?

    init(connection: C64Connection) {
        self.connection = connection
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    override func loadView() {
        let container = NSView()
        container.wantsLayer = true
        container.layer?.backgroundColor = NSColor.black.cgColor

        mtkView = MTKView()
        mtkView.device = connection.renderer.device
        mtkView.colorPixelFormat = .bgra8Unorm
        mtkView.isPaused = false
        mtkView.enableSetNeedsDisplay = false
        mtkView.delegate = connection.renderer

        statusBar = StatusBarView()
        statusBar.translatesAutoresizingMaskIntoConstraints = false

        container.addSubview(mtkView)
        container.addSubview(statusBar)

        NSLayoutConstraint.activate([
            statusBar.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            statusBar.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            statusBar.bottomAnchor.constraint(equalTo: container.bottomAnchor),
        ])

        self.view = container

        startStatusUpdates()
    }

    override func viewDidLayout() {
        super.viewDidLayout()
        layoutMTKView()
    }

    // MARK: - Keyboard Strip

    func setKeyboardStripVisible(_ visible: Bool) {
        if visible {
            guard keyStripView == nil, let forwarder = connection.keyboardForwarder else { return }
            let strip = KeyStripView(forwarder: forwarder)
            strip.onMenuButton = onMenuButton
            strip.translatesAutoresizingMaskIntoConstraints = false
            view.addSubview(strip)
            NSLayoutConstraint.activate([
                strip.leadingAnchor.constraint(equalTo: view.leadingAnchor),
                strip.trailingAnchor.constraint(equalTo: view.trailingAnchor),
                strip.bottomAnchor.constraint(equalTo: statusBar.topAnchor),
            ])
            keyStripView = strip
        } else {
            keyStripView?.removeFromSuperview()
            keyStripView = nil
        }
    }

    // MARK: - Layout

    private func layoutMTKView() {
        let bounds = view.safeAreaRect
        guard bounds.width > 0, bounds.height > 0 else { return }

        // Reserve space for status bar
        let statusHeight: CGFloat = 24
        let available = CGRect(x: bounds.origin.x, y: bounds.origin.y + statusHeight,
                               width: bounds.width, height: bounds.height - statusHeight)

        let containerAspect = available.width / available.height

        let fitSize: CGSize
        if containerAspect > aspectRatio {
            fitSize = CGSize(width: available.height * aspectRatio, height: available.height)
        } else {
            fitSize = CGSize(width: available.width, height: available.width / aspectRatio)
        }

        let x = available.origin.x + (available.width - fitSize.width) / 2
        let y = available.origin.y + (available.height - fitSize.height) / 2
        mtkView.frame = CGRect(x: x, y: y, width: fitSize.width, height: fitSize.height)
    }

    // MARK: - Status Updates

    private func startStatusUpdates() {
        let timer = DispatchSource.makeTimerSource(queue: .main)
        timer.schedule(deadline: .now(), repeating: .milliseconds(500))
        timer.setEventHandler { [weak self] in
            guard let self else { return }
            let keyboardActive = self.connection.keyboardForwarder?.isEnabled == true
            self.statusBar.update(
                fps: self.connection.framesPerSecond,
                isRecording: self.connection.isRecording,
                isKeyboardActive: keyboardActive
            )
        }
        timer.resume()
        statusTimer = timer
    }

    deinit {
        statusTimer?.cancel()
    }
}

private extension NSView {
    var safeAreaRect: NSRect {
        let insets = safeAreaInsets
        return NSRect(
            x: insets.left,
            y: insets.bottom,
            width: bounds.width - insets.left - insets.right,
            height: bounds.height - insets.top - insets.bottom
        )
    }
}
