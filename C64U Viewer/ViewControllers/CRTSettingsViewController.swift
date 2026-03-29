// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.

import AppKit

final class CRTSettingsViewController: NSViewController {
    let connection: C64Connection
    private var sliders: [String: NSSlider] = [:]

    init(connection: C64Connection) {
        self.connection = connection
        super.init(nibName: nil, bundle: nil)
        self.title = "CRT Filter"
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    override func loadView() {
        let container = NSView()
        container.wantsLayer = true
        container.layer?.backgroundColor = NSColor(white: 0.1, alpha: 1.0).cgColor

        let scrollView = NSScrollView()
        scrollView.hasVerticalScroller = true
        scrollView.drawsBackground = false
        scrollView.translatesAutoresizingMaskIntoConstraints = false

        let contentView = FlippedView()
        contentView.translatesAutoresizingMaskIntoConstraints = false

        let stack = NSStackView()
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 6
        stack.translatesAutoresizingMaskIntoConstraints = false

        // Preset picker
        addSection("Preset", to: stack)
        let presetPopup = NSPopUpButton(frame: .zero, pullsDown: false)
        for preset in CRTPreset.allCases {
            presetPopup.addItem(withTitle: preset.rawValue)
        }
        if case .builtIn(let p) = connection.presetManager.selectedIdentifier,
           let idx = CRTPreset.allCases.firstIndex(of: p) {
            presetPopup.selectItem(at: idx)
        }
        presetPopup.target = self
        presetPopup.action = #selector(presetChanged(_:))
        presetPopup.translatesAutoresizingMaskIntoConstraints = false
        stack.addArrangedSubview(presetPopup)

        addSeparator(to: stack)
        addSection("Scanlines", to: stack)
        addSlider("scanlineIntensity", label: "Intensity", range: 0...1, to: stack)
        addSlider("scanlineWidth", label: "Width", range: 0...1, to: stack)

        addSeparator(to: stack)
        addSection("Blur & Bloom", to: stack)
        addSlider("blurRadius", label: "Blur", range: 0...1, to: stack)
        addSlider("bloomIntensity", label: "Bloom Intensity", range: 0...1, to: stack)
        addSlider("bloomRadius", label: "Bloom Radius", range: 0...1, to: stack)

        addSeparator(to: stack)
        addSection("Tint", to: stack)
        let tintPopup = NSPopUpButton(frame: .zero, pullsDown: false)
        for title in ["None", "Amber", "Green", "Monochrome"] {
            tintPopup.addItem(withTitle: title)
        }
        tintPopup.selectItem(at: connection.crtSettings.tintMode)
        tintPopup.target = self
        tintPopup.action = #selector(tintModeChanged(_:))
        tintPopup.translatesAutoresizingMaskIntoConstraints = false
        stack.addArrangedSubview(tintPopup)
        addSlider("tintStrength", label: "Strength", range: 0...1, to: stack)

        addSeparator(to: stack)
        addSection("Phosphor Mask", to: stack)
        let maskPopup = NSPopUpButton(frame: .zero, pullsDown: false)
        for title in ["None", "Aperture Grille", "Shadow Mask", "Slot Mask"] {
            maskPopup.addItem(withTitle: title)
        }
        maskPopup.selectItem(at: connection.crtSettings.maskType)
        maskPopup.target = self
        maskPopup.action = #selector(maskTypeChanged(_:))
        maskPopup.translatesAutoresizingMaskIntoConstraints = false
        stack.addArrangedSubview(maskPopup)
        addSlider("maskIntensity", label: "Intensity", range: 0...1, to: stack)

        addSeparator(to: stack)
        addSection("Screen Shape", to: stack)
        addSlider("curvatureAmount", label: "Curvature", range: 0...1, to: stack)
        addSlider("vignetteStrength", label: "Vignette", range: 0...1, to: stack)

        addSeparator(to: stack)
        addSection("Afterglow", to: stack)
        addSlider("afterglowStrength", label: "Strength", range: 0...1, to: stack)
        addSlider("afterglowDecaySpeed", label: "Decay Speed", range: 1...15, to: stack)

        contentView.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 12),
            stack.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 12),
            stack.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -12),
            stack.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -12),
            presetPopup.widthAnchor.constraint(equalTo: stack.widthAnchor),
            tintPopup.widthAnchor.constraint(equalTo: stack.widthAnchor),
            maskPopup.widthAnchor.constraint(equalTo: stack.widthAnchor),
        ])

        scrollView.documentView = contentView
        contentView.widthAnchor.constraint(equalTo: scrollView.contentView.widthAnchor).isActive = true

        container.addSubview(scrollView)
        NSLayoutConstraint.activate([
            scrollView.topAnchor.constraint(equalTo: container.topAnchor),
            scrollView.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            scrollView.bottomAnchor.constraint(equalTo: container.bottomAnchor),
        ])

        self.view = container
    }

    // MARK: - Helpers

    private func addSection(_ title: String, to stack: NSStackView) {
        let label = NSTextField(labelWithString: title)
        label.font = .systemFont(ofSize: 11, weight: .semibold)
        stack.addArrangedSubview(label)
    }

    private func addSeparator(to stack: NSStackView) {
        let sep = NSBox()
        sep.boxType = .separator
        sep.translatesAutoresizingMaskIntoConstraints = false
        stack.addArrangedSubview(sep)
        sep.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true
    }

    private func addSlider(_ key: String, label: String, range: ClosedRange<Float>, to stack: NSStackView) {
        let row = NSStackView()
        row.orientation = .horizontal
        row.spacing = 8
        row.translatesAutoresizingMaskIntoConstraints = false

        let nameLabel = NSTextField(labelWithString: label)
        nameLabel.font = .systemFont(ofSize: 11)
        nameLabel.setContentHuggingPriority(.defaultHigh, for: .horizontal)
        nameLabel.widthAnchor.constraint(equalToConstant: 100).isActive = true

        let slider = NSSlider(value: Double(currentValue(for: key)),
                              minValue: Double(range.lowerBound),
                              maxValue: Double(range.upperBound),
                              target: self,
                              action: #selector(sliderChanged(_:)))
        slider.identifier = NSUserInterfaceItemIdentifier(key)
        slider.controlSize = .small
        sliders[key] = slider

        row.addArrangedSubview(nameLabel)
        row.addArrangedSubview(slider)
        stack.addArrangedSubview(row)
        row.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true
    }

    private func currentValue(for key: String) -> Float {
        let s = connection.crtSettings
        switch key {
        case "scanlineIntensity": return s.scanlineIntensity
        case "scanlineWidth": return s.scanlineWidth
        case "blurRadius": return s.blurRadius
        case "bloomIntensity": return s.bloomIntensity
        case "bloomRadius": return s.bloomRadius
        case "afterglowStrength": return s.afterglowStrength
        case "afterglowDecaySpeed": return s.afterglowDecaySpeed
        case "tintStrength": return s.tintStrength
        case "maskIntensity": return s.maskIntensity
        case "curvatureAmount": return s.curvatureAmount
        case "vignetteStrength": return s.vignetteStrength
        default: return 0
        }
    }

    // MARK: - Actions

    @objc private func presetChanged(_ sender: NSPopUpButton) {
        let index = sender.indexOfSelectedItem
        guard index >= 0, index < CRTPreset.allCases.count else { return }
        connection.selectPreset(.builtIn(CRTPreset.allCases[index]))
        refreshSliders()
    }

    @objc private func tintModeChanged(_ sender: NSPopUpButton) {
        connection.crtSettings.tintMode = sender.indexOfSelectedItem
        connection.applySettingsChange()
    }

    @objc private func maskTypeChanged(_ sender: NSPopUpButton) {
        connection.crtSettings.maskType = sender.indexOfSelectedItem
        connection.applySettingsChange()
    }

    @objc private func sliderChanged(_ sender: NSSlider) {
        guard let key = sender.identifier?.rawValue else { return }
        let value = Float(sender.doubleValue)
        switch key {
        case "scanlineIntensity": connection.crtSettings.scanlineIntensity = value
        case "scanlineWidth": connection.crtSettings.scanlineWidth = value
        case "blurRadius": connection.crtSettings.blurRadius = value
        case "bloomIntensity": connection.crtSettings.bloomIntensity = value
        case "bloomRadius": connection.crtSettings.bloomRadius = value
        case "afterglowStrength": connection.crtSettings.afterglowStrength = value
        case "afterglowDecaySpeed": connection.crtSettings.afterglowDecaySpeed = value
        case "tintStrength": connection.crtSettings.tintStrength = value
        case "maskIntensity": connection.crtSettings.maskIntensity = value
        case "curvatureAmount": connection.crtSettings.curvatureAmount = value
        case "vignetteStrength": connection.crtSettings.vignetteStrength = value
        default: break
        }
        connection.applySettingsChange()
    }

    private func refreshSliders() {
        for (key, slider) in sliders {
            slider.doubleValue = Double(currentValue(for: key))
        }
    }
}

// MARK: - Flipped View (for scroll view document)

private final class FlippedView: NSView {
    override var isFlipped: Bool { true }
}
