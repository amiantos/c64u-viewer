// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.

import AppKit
import MetalKit

final class VideoViewController: NSViewController {
    let connection: C64Connection
    private var mtkView: MTKView!

    private let aspectRatio: CGFloat = 384.0 / 272.0

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

        container.addSubview(mtkView)
        self.view = container
    }

    override func viewDidLayout() {
        super.viewDidLayout()
        layoutMTKView()
    }

    private func layoutMTKView() {
        let bounds = view.safeAreaRect
        guard bounds.width > 0, bounds.height > 0 else { return }

        let containerAspect = bounds.width / bounds.height

        let fitSize: CGSize
        if containerAspect > aspectRatio {
            // Container is wider — fit to height
            fitSize = CGSize(width: bounds.height * aspectRatio, height: bounds.height)
        } else {
            // Container is taller — fit to width
            fitSize = CGSize(width: bounds.width, height: bounds.width / aspectRatio)
        }

        let x = bounds.origin.x + (bounds.width - fitSize.width) / 2
        let y = bounds.origin.y + (bounds.height - fitSize.height) / 2
        mtkView.frame = CGRect(x: x, y: y, width: fitSize.width, height: fitSize.height)
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
