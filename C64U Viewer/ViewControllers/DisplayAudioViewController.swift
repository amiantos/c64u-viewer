// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.

import AppKit

final class DisplayAudioViewController: NSViewController {
    let connection: C64Connection
    private var sliders: [String: NSSlider] = [:]
    private var valueLabels: [String: NSTextField] = [:]
    private var presetPopup: NSPopUpButton!
    private var saveAsButton: NSButton!
    private var resetButton: NSButton!
    private var deleteButton: NSButton!
    private var tintModePopup: NSPopUpButton!
    private var maskTypePopup: NSPopUpButton!
    private var overlayTintPopup: NSPopUpButton!

    init(connection: C64Connection) {
        self.connection = connection
        super.init(nibName: nil, bundle: nil)
        self.title = "Settings"
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    override func loadView() {
        let container = NSView()

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

        // ── Audio ──
        addSection("Audio", to: stack)
        addSlider("volume", label: "Volume", range: 0...1, to: stack)
        addSlider("balance", label: "Balance", range: -1...1, to: stack)

        addSeparator(to: stack)

        // ── CRT Preset ──
        addSection("CRT Preset", to: stack)
        presetPopup = NSPopUpButton(frame: .zero, pullsDown: false)
        presetPopup.controlSize = .small
        presetPopup.font = .systemFont(ofSize: NSFont.smallSystemFontSize)
        rebuildPresetPopup()
        presetPopup.target = self
        presetPopup.action = #selector(presetChanged(_:))
        presetPopup.translatesAutoresizingMaskIntoConstraints = false

        saveAsButton = NSButton(title: "Save As…", target: self, action: #selector(saveAsPreset))
        saveAsButton.controlSize = .small
        saveAsButton.bezelStyle = .rounded

        resetButton = NSButton(title: "Reset", target: self, action: #selector(resetPreset))
        resetButton.controlSize = .small
        resetButton.bezelStyle = .rounded

        deleteButton = NSButton(title: "Delete", target: self, action: #selector(deletePreset))
        deleteButton.controlSize = .small
        deleteButton.bezelStyle = .rounded

        let presetRow = NSStackView(views: [presetPopup, saveAsButton, resetButton, deleteButton])
        presetRow.orientation = .horizontal
        presetRow.distribution = .fill
        presetRow.spacing = 6
        presetRow.translatesAutoresizingMaskIntoConstraints = false
        presetPopup.setContentHuggingPriority(.defaultLow, for: .horizontal)
        saveAsButton.setContentHuggingPriority(.required, for: .horizontal)
        resetButton.setContentHuggingPriority(.required, for: .horizontal)
        deleteButton.setContentHuggingPriority(.required, for: .horizontal)
        stack.addArrangedSubview(presetRow)
        presetRow.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true
        updatePresetButtons()

        // ── Scanlines ──
        addSubsection("Scanlines", to: stack)
        addSlider("scanlineIntensity", label: "Intensity", range: 0...1, to: stack)
        addSlider("scanlineWidth", label: "Width", range: 0...1, to: stack)

        addSubsection("Blur & Bloom", to: stack)
        addSlider("blurRadius", label: "Blur", range: 0...1, to: stack)
        addSlider("bloomIntensity", label: "Bloom Intensity", range: 0...1, to: stack)
        addSlider("bloomRadius", label: "Bloom Radius", range: 0...1, to: stack)

        addSubsection("Tint", to: stack)
        tintModePopup = NSPopUpButton(frame: .zero, pullsDown: false)
        tintModePopup.controlSize = .small
        tintModePopup.font = .systemFont(ofSize: NSFont.smallSystemFontSize)
        for title in ["None", "Amber", "Green", "Monochrome"] {
            tintModePopup.addItem(withTitle: title)
        }
        tintModePopup.selectItem(at: connection.crtSettings.tintMode)
        tintModePopup.target = self
        tintModePopup.action = #selector(tintModeChanged(_:))
        tintModePopup.translatesAutoresizingMaskIntoConstraints = false
        tintModePopup.setContentHuggingPriority(.defaultLow, for: .horizontal)

        let tintTypeRow = NSStackView()
        tintTypeRow.orientation = .horizontal
        tintTypeRow.distribution = .fill
        tintTypeRow.spacing = 8
        tintTypeRow.translatesAutoresizingMaskIntoConstraints = false
        let tintTypeLabel = NSTextField(labelWithString: "Type")
        tintTypeLabel.font = .systemFont(ofSize: 11)
        tintTypeLabel.setContentHuggingPriority(.required, for: .horizontal)
        tintTypeLabel.widthAnchor.constraint(equalToConstant: 100).isActive = true
        tintTypeRow.addArrangedSubview(tintTypeLabel)
        tintTypeRow.addArrangedSubview(tintModePopup)
        stack.addArrangedSubview(tintTypeRow)
        tintTypeRow.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true
        addSlider("tintStrength", label: "Strength", range: 0...1, to: stack)

        addSubsection("Phosphor Mask", to: stack)
        maskTypePopup = NSPopUpButton(frame: .zero, pullsDown: false)
        maskTypePopup.controlSize = .small
        maskTypePopup.font = .systemFont(ofSize: NSFont.smallSystemFontSize)
        for title in ["None", "Aperture Grille", "Shadow Mask", "Slot Mask"] {
            maskTypePopup.addItem(withTitle: title)
        }
        maskTypePopup.selectItem(at: connection.crtSettings.maskType)
        maskTypePopup.target = self
        maskTypePopup.action = #selector(maskTypeChanged(_:))
        maskTypePopup.translatesAutoresizingMaskIntoConstraints = false
        maskTypePopup.setContentHuggingPriority(.defaultLow, for: .horizontal)

        let maskTypeRow = NSStackView()
        maskTypeRow.orientation = .horizontal
        maskTypeRow.distribution = .fill
        maskTypeRow.spacing = 8
        maskTypeRow.translatesAutoresizingMaskIntoConstraints = false
        let maskTypeLabel = NSTextField(labelWithString: "Type")
        maskTypeLabel.font = .systemFont(ofSize: 11)
        maskTypeLabel.setContentHuggingPriority(.required, for: .horizontal)
        maskTypeLabel.widthAnchor.constraint(equalToConstant: 100).isActive = true
        maskTypeRow.addArrangedSubview(maskTypeLabel)
        maskTypeRow.addArrangedSubview(maskTypePopup)
        stack.addArrangedSubview(maskTypeRow)
        maskTypeRow.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true
        addSlider("maskIntensity", label: "Intensity", range: 0...1, to: stack)

        addSubsection("Screen Shape", to: stack)
        addSlider("curvatureAmount", label: "Curvature", range: 0...1, to: stack)
        addSlider("vignetteStrength", label: "Vignette", range: 0...1, to: stack)

        addSubsection("Afterglow", to: stack)
        addSlider("afterglowStrength", label: "Strength", range: 0...1, to: stack)
        addSlider("afterglowDecaySpeed", label: "Decay Speed", range: 1...15, to: stack)

        addSeparator(to: stack)

        // ── Keyboard Overlay ──
        addSection("Keyboard Overlay", to: stack)
        addSlider("overlayBgOpacity", label: "Background", range: 0...1, to: stack)
        addSlider("overlayButtonOpacity", label: "Buttons", range: 0...1, to: stack)

        overlayTintPopup = NSPopUpButton(frame: .zero, pullsDown: false)
        overlayTintPopup.controlSize = .small
        overlayTintPopup.font = .systemFont(ofSize: NSFont.smallSystemFontSize)
        for title in ["White", "Green", "Amber"] {
            overlayTintPopup.addItem(withTitle: title)
        }
        overlayTintPopup.selectItem(at: UserDefaults.standard.integer(forKey: "keyboard_overlay_tint"))
        overlayTintPopup.target = self
        overlayTintPopup.action = #selector(overlayTintChanged(_:))
        overlayTintPopup.translatesAutoresizingMaskIntoConstraints = false
        overlayTintPopup.setContentHuggingPriority(.defaultLow, for: .horizontal)

        let tintRow = NSStackView()
        tintRow.orientation = .horizontal
        tintRow.distribution = .fill
        tintRow.spacing = 8
        tintRow.translatesAutoresizingMaskIntoConstraints = false
        let tintLabel = NSTextField(labelWithString: "Tint Color")
        tintLabel.font = .systemFont(ofSize: 11)
        tintLabel.setContentHuggingPriority(.required, for: .horizontal)
        tintLabel.widthAnchor.constraint(equalToConstant: 100).isActive = true
        tintRow.addArrangedSubview(tintLabel)
        tintRow.addArrangedSubview(overlayTintPopup)
        stack.addArrangedSubview(tintRow)
        tintRow.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true

        contentView.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 12),
            stack.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 12),
            stack.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -12),
            stack.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -12),
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

    // MARK: - Preset Management

    private func rebuildPresetPopup() {
        presetPopup.removeAllItems()
        for entry in connection.presetManager.allPresetEntries {
            presetPopup.addItem(withTitle: entry.name)
        }
        if let idx = connection.presetManager.allPresetEntries.firstIndex(where: { $0.id == connection.presetManager.selectedIdentifier }) {
            presetPopup.selectItem(at: idx)
        }
    }

    private func updatePresetButtons() {
        saveAsButton.isHidden = false
        switch connection.presetManager.selectedIdentifier {
        case .builtIn(let preset):
            resetButton.isHidden = !connection.presetManager.isModified(preset)
            deleteButton.isHidden = true
        case .custom:
            resetButton.isHidden = true
            deleteButton.isHidden = false
        }
    }

    // MARK: - UI Helpers

    private func addSection(_ title: String, to stack: NSStackView) {
        let label = NSTextField(labelWithString: title)
        label.font = .systemFont(ofSize: 13, weight: .bold)
        label.textColor = .secondaryLabelColor
        stack.addArrangedSubview(label)
    }

    private func addSubsection(_ title: String, to stack: NSStackView) {
        let spacer = NSView()
        spacer.translatesAutoresizingMaskIntoConstraints = false
        spacer.heightAnchor.constraint(equalToConstant: 4).isActive = true
        spacer.setContentHuggingPriority(.required, for: .vertical)
        stack.addArrangedSubview(spacer)

        let label = NSTextField(labelWithString: title)
        label.font = .systemFont(ofSize: 11, weight: .semibold)
        label.textColor = .tertiaryLabelColor
        stack.addArrangedSubview(label)
    }

    private func addSeparator(to stack: NSStackView) {
        let topSpacer = NSView()
        topSpacer.translatesAutoresizingMaskIntoConstraints = false
        topSpacer.heightAnchor.constraint(equalToConstant: 4).isActive = true
        topSpacer.setContentHuggingPriority(.required, for: .vertical)
        stack.addArrangedSubview(topSpacer)

        let sep = NSBox()
        sep.boxType = .separator
        sep.translatesAutoresizingMaskIntoConstraints = false
        stack.addArrangedSubview(sep)
        sep.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true

        let bottomSpacer = NSView()
        bottomSpacer.translatesAutoresizingMaskIntoConstraints = false
        bottomSpacer.heightAnchor.constraint(equalToConstant: 4).isActive = true
        bottomSpacer.setContentHuggingPriority(.required, for: .vertical)
        stack.addArrangedSubview(bottomSpacer)
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

        let value = currentValue(for: key)
        let slider = NSSlider(value: Double(value),
                              minValue: Double(range.lowerBound),
                              maxValue: Double(range.upperBound),
                              target: self,
                              action: #selector(sliderChanged(_:)))
        slider.identifier = NSUserInterfaceItemIdentifier(key)
        slider.controlSize = .small
        sliders[key] = slider

        let valueLabel = NSTextField(labelWithString: formatSliderValue(value))
        valueLabel.font = .monospacedDigitSystemFont(ofSize: 10, weight: .regular)
        valueLabel.textColor = .secondaryLabelColor
        valueLabel.alignment = .right
        valueLabel.widthAnchor.constraint(equalToConstant: 36).isActive = true
        valueLabels[key] = valueLabel

        row.addArrangedSubview(nameLabel)
        row.addArrangedSubview(slider)
        row.addArrangedSubview(valueLabel)
        stack.addArrangedSubview(row)
        row.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true
    }

    private func currentValue(for key: String) -> Float {
        switch key {
        case "volume": return connection.volume
        case "balance": return connection.balance
        case "overlayBgOpacity":
            return UserDefaults.standard.object(forKey: "keyboard_overlay_bg_opacity") as? Float ?? 0.0
        case "overlayButtonOpacity":
            return UserDefaults.standard.object(forKey: "keyboard_overlay_button_opacity") as? Float ?? 1.0
        default: break
        }
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

    private func formatSliderValue(_ value: Float) -> String {
        if abs(value) >= 10 {
            return String(format: "%.1f", value)
        }
        return String(format: "%.2f", value)
    }

    // MARK: - Actions

    @objc private func sliderChanged(_ sender: NSSlider) {
        guard let key = sender.identifier?.rawValue else { return }
        let value = Float(sender.doubleValue)
        valueLabels[key]?.stringValue = formatSliderValue(value)

        // Audio sliders
        if key == "volume" {
            connection.volume = value
            connection.isMuted = false
            return
        }
        if key == "balance" {
            connection.balance = value
            return
        }

        // Keyboard overlay sliders
        if key == "overlayBgOpacity" {
            UserDefaults.standard.set(value, forKey: "keyboard_overlay_bg_opacity")
            NotificationCenter.default.post(name: .keyboardOverlaySettingsChanged, object: nil)
            return
        }
        if key == "overlayButtonOpacity" {
            UserDefaults.standard.set(value, forKey: "keyboard_overlay_button_opacity")
            NotificationCenter.default.post(name: .keyboardOverlaySettingsChanged, object: nil)
            return
        }

        // CRT sliders
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
        rebuildPresetPopup()
        updatePresetButtons()
    }

    @objc private func presetChanged(_ sender: NSPopUpButton) {
        let entries = connection.presetManager.allPresetEntries
        let index = sender.indexOfSelectedItem
        guard index >= 0, index < entries.count else { return }
        connection.selectPreset(entries[index].id)
        refreshSliders()
        updatePresetButtons()
    }

    @objc private func tintModeChanged(_ sender: NSPopUpButton) {
        connection.crtSettings.tintMode = sender.indexOfSelectedItem
        connection.applySettingsChange()
        rebuildPresetPopup()
        updatePresetButtons()
    }

    @objc private func overlayTintChanged(_ sender: NSPopUpButton) {
        UserDefaults.standard.set(sender.indexOfSelectedItem, forKey: "keyboard_overlay_tint")
        NotificationCenter.default.post(name: .keyboardOverlaySettingsChanged, object: nil)
    }

    @objc private func maskTypeChanged(_ sender: NSPopUpButton) {
        connection.crtSettings.maskType = sender.indexOfSelectedItem
        connection.applySettingsChange()
        rebuildPresetPopup()
        updatePresetButtons()
    }

    @objc private func saveAsPreset() {
        let alert = NSAlert()
        alert.messageText = "Save As New Preset"
        alert.addButton(withTitle: "Save")
        alert.addButton(withTitle: "Cancel")
        let nameField = NSTextField(frame: NSRect(x: 0, y: 0, width: 200, height: 24))
        nameField.placeholderString = "Preset Name"
        alert.accessoryView = nameField
        guard let window = view.window else { return }
        alert.beginSheetModal(for: window) { [weak self] response in
            guard let self, response == .alertFirstButtonReturn else { return }
            let name = nameField.stringValue.trimmingCharacters(in: .whitespaces)
            guard !name.isEmpty else { return }
            let id = self.connection.presetManager.saveAsCustom(name: name, settings: self.connection.crtSettings)
            self.connection.presetManager.selectedIdentifier = .custom(id)
            self.rebuildPresetPopup()
            self.updatePresetButtons()
        }
    }

    @objc private func resetPreset() {
        guard case .builtIn(let preset) = connection.presetManager.selectedIdentifier else { return }
        connection.presetManager.resetBuiltIn(preset)
        connection.selectPreset(.builtIn(preset))
        refreshSliders()
        rebuildPresetPopup()
        updatePresetButtons()
    }

    @objc private func deletePreset() {
        guard case .custom(let id) = connection.presetManager.selectedIdentifier else { return }
        connection.presetManager.deleteCustom(id: id)
        connection.crtSettings = connection.presetManager.settings(for: connection.presetManager.selectedIdentifier)
        refreshSliders()
        rebuildPresetPopup()
        updatePresetButtons()
    }

    private func refreshSliders() {
        for (key, slider) in sliders {
            let value = currentValue(for: key)
            slider.doubleValue = Double(value)
            valueLabels[key]?.stringValue = formatSliderValue(value)
        }
        tintModePopup.selectItem(at: connection.crtSettings.tintMode)
        maskTypePopup.selectItem(at: connection.crtSettings.maskType)
    }
}

// MARK: - Helpers

private final class FlippedView: NSView {
    override var isFlipped: Bool { true }
}
