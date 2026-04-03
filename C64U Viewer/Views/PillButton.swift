// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.

import AppKit

/// A flat pill-shaped button for use in inspector panels.
/// Draws a rounded rect background with a label or icon, similar to iOS 7 / Xcode style.
final class PillButton: NSButton {
    private var iconImage: NSImage?

    init(title: String, target: AnyObject?, action: Selector?) {
        super.init(frame: .zero)
        self.title = title
        self.target = target
        self.action = action
        commonInit()
        self.setContentHuggingPriority(.defaultLow, for: .horizontal)
    }

    init(symbolName: String, accessibilityDescription: String?, target: AnyObject?, action: Selector?) {
        super.init(frame: .zero)
        self.title = ""
        self.iconImage = NSImage(systemSymbolName: symbolName, accessibilityDescription: accessibilityDescription)
        self.target = target
        self.action = action
        commonInit()
        self.setContentHuggingPriority(.required, for: .horizontal)
    }

    private func commonInit() {
        self.bezelStyle = .toolbar
        self.font = .systemFont(ofSize: 11, weight: .medium)
        self.translatesAutoresizingMaskIntoConstraints = false
        self.wantsLayer = true
        self.isBordered = false
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    override var intrinsicContentSize: NSSize {
        if iconImage != nil {
            return NSSize(width: 30, height: 22)
        }
        let base = super.intrinsicContentSize
        return NSSize(width: base.width + 16, height: 22)
    }

    override func draw(_ dirtyRect: NSRect) {
        let path = NSBezierPath(roundedRect: bounds, xRadius: bounds.height / 2, yRadius: bounds.height / 2)

        let isDark = effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
        if isHighlighted {
            (isDark ? NSColor.white.withAlphaComponent(0.15) : NSColor.black.withAlphaComponent(0.1)).setFill()
        } else {
            (isDark ? NSColor.white.withAlphaComponent(0.08) : NSColor.black.withAlphaComponent(0.05)).setFill()
        }
        path.fill()

        (isDark ? NSColor.white.withAlphaComponent(0.15) : NSColor.black.withAlphaComponent(0.12)).setStroke()
        path.lineWidth = 0.5
        path.stroke()

        let color = isEnabled ? NSColor.labelColor : NSColor.tertiaryLabelColor

        if let icon = iconImage {
            let config = NSImage.SymbolConfiguration(pointSize: 11, weight: .medium)
            let sized = icon.withSymbolConfiguration(config) ?? icon
            let tinted = sized.withTintColor(color)
            let imageSize = tinted.size
            let imageRect = NSRect(
                x: (bounds.width - imageSize.width) / 2,
                y: (bounds.height - imageSize.height) / 2,
                width: imageSize.width,
                height: imageSize.height
            )
            tinted.draw(in: imageRect)
        } else {
            let style = NSMutableParagraphStyle()
            style.alignment = .center
            let attrs: [NSAttributedString.Key: Any] = [
                .font: font ?? .systemFont(ofSize: 11, weight: .medium),
                .foregroundColor: color,
                .paragraphStyle: style,
            ]
            let size = title.size(withAttributes: attrs)
            let textRect = NSRect(
                x: 0,
                y: (bounds.height - size.height) / 2,
                width: bounds.width,
                height: size.height
            )
            title.draw(in: textRect, withAttributes: attrs)
        }
    }

    override func resetCursorRects() {
        addCursorRect(bounds, cursor: .arrow)
    }
}

private extension NSImage {
    func withTintColor(_ color: NSColor) -> NSImage {
        let image = self.copy() as! NSImage
        image.lockFocus()
        color.set()
        let rect = NSRect(origin: .zero, size: image.size)
        rect.fill(using: .sourceAtop)
        image.unlockFocus()
        image.isTemplate = false
        return image
    }
}
