// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.

import AppKit

/// An NSView that draws a solid background color, responding to appearance changes.
/// Unlike setting layer.backgroundColor (which snapshots a CGColor), this uses
/// NSColor.drawSwatch which respects dynamic/semantic colors.
final class BackgroundView: NSView {
    var backgroundColor: NSColor = .controlBackgroundColor {
        didSet { needsDisplay = true }
    }

    override func draw(_ dirtyRect: NSRect) {
        backgroundColor.setFill()
        dirtyRect.fill()
    }
}
