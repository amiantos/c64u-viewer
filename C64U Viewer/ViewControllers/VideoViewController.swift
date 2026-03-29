// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.

import AppKit
import MetalKit

final class VideoViewController: NSViewController {
    let connection: C64Connection
    private var mtkView: MTKView!

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
        mtkView.translatesAutoresizingMaskIntoConstraints = false

        container.addSubview(mtkView)

        // Maintain C64 aspect ratio (384:272) centered in the container
        NSLayoutConstraint.activate([
            mtkView.centerXAnchor.constraint(equalTo: container.centerXAnchor),
            mtkView.centerYAnchor.constraint(equalTo: container.centerYAnchor),
            mtkView.widthAnchor.constraint(lessThanOrEqualTo: container.widthAnchor),
            mtkView.heightAnchor.constraint(lessThanOrEqualTo: container.heightAnchor),
            mtkView.widthAnchor.constraint(equalTo: mtkView.heightAnchor, multiplier: 384.0 / 272.0),
        ])

        // Fill as much space as possible while maintaining aspect ratio
        let widthFill = mtkView.widthAnchor.constraint(equalTo: container.widthAnchor)
        widthFill.priority = .defaultHigh
        let heightFill = mtkView.heightAnchor.constraint(equalTo: container.heightAnchor)
        heightFill.priority = .defaultHigh
        NSLayoutConstraint.activate([widthFill, heightFill])

        self.view = container
    }
}
