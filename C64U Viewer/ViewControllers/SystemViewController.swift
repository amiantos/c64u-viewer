// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.

import AppKit

final class SystemViewController: NSViewController {
    let connection: C64Connection

    // Drive UI
    private var driveALabel: NSTextField!
    private var driveATypeLabel: NSTextField!
    private var driveBLabel: NSTextField!
    private var driveBTypeLabel: NSTextField!

    // Stream UI
    private var streamStatusLabel: NSTextField!
    private var streamFPSLabel: NSTextField!
    private var streamTimer: DispatchSourceTimer?

    // Config UI
    private var configStack: NSStackView!
    private var searchField: NSSearchField!
    private var allConfigCategories: [(category: String, header: NSButton, itemsContainer: NSStackView, items: [ConfigItemRow])] = []
    private var collapsedCategories: Set<String> = []
    private var preSearchCollapsed: Set<String>?

    // Loading indicator
    private var loadingLabel: NSTextField?

    // Currently active edit row (only one at a time)
    private weak var activeEditRow: ConfigItemRow?

    init(connection: C64Connection) {
        self.connection = connection
        super.init(nibName: nil, bundle: nil)
        self.title = "System"
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

        // ── Device Info ──
        if let info = connection.deviceInfo {
            addSection("Device", to: stack)
            addInfoRow("Product", value: info.product, to: stack)
            addInfoRow("Firmware", value: "v\(info.firmwareVersion)", to: stack)
            addInfoRow("FPGA", value: info.fpgaVersion, to: stack)
            addInfoRow("Hostname", value: info.hostname, to: stack)
            addSeparator(to: stack)
        }

        // ── Streams ──
        addSection("Streams", to: stack)

        streamStatusLabel = NSTextField(labelWithString: connection.streamsActive ? "Active" : "Inactive")
        streamStatusLabel.font = .systemFont(ofSize: 11)
        streamStatusLabel.textColor = connection.streamsActive ? .systemGreen : .secondaryLabelColor
        addInfoRowWithLabel("Status", valueLabel: streamStatusLabel, to: stack)

        streamFPSLabel = NSTextField(labelWithString: "\(Int(connection.framesPerSecond)) fps")
        streamFPSLabel.font = .monospacedDigitSystemFont(ofSize: 11, weight: .regular)
        addInfoRowWithLabel("Video FPS", valueLabel: streamFPSLabel, to: stack)

        addSeparator(to: stack)
        startStreamTimer()

        // ── Drives ──
        addSection("Drives", to: stack)

        let driveARow = makeDriveRow("A")
        driveALabel = driveARow.imageLabel
        driveATypeLabel = driveARow.typeLabel
        stack.addArrangedSubview(driveARow.view)

        let driveBRow = makeDriveRow("B")
        driveBLabel = driveBRow.imageLabel
        driveBTypeLabel = driveBRow.typeLabel
        stack.addArrangedSubview(driveBRow.view)

        addSeparator(to: stack)

        // ── Configuration ──
        addSection("Configuration", to: stack)

        searchField = NSSearchField()
        searchField.placeholderString = "Search settings…"
        searchField.translatesAutoresizingMaskIntoConstraints = false
        searchField.target = self
        searchField.action = #selector(searchChanged(_:))

        let refreshButton = PillButton(symbolName: "arrow.clockwise", accessibilityDescription: "Refresh", target: self, action: #selector(refreshAll))
        refreshButton.toolTip = "Refresh all device data"

        let saveButton = PillButton(symbolName: "memorychip", accessibilityDescription: "Save to Flash", target: self, action: #selector(saveToFlash))
        saveButton.toolTip = "Save configuration to flash"

        let searchRow = NSStackView(views: [searchField, refreshButton, saveButton])
        searchRow.orientation = .horizontal
        searchRow.distribution = .fill
        searchRow.spacing = 4
        searchRow.translatesAutoresizingMaskIntoConstraints = false
        searchField.setContentHuggingPriority(.defaultLow, for: .horizontal)
        stack.addArrangedSubview(searchRow)

        configStack = NSStackView()
        configStack.orientation = .vertical
        configStack.alignment = .leading
        configStack.spacing = 2
        configStack.translatesAutoresizingMaskIntoConstraints = false
        stack.addArrangedSubview(configStack)

        // Loading indicator
        let loading = NSTextField(labelWithString: "Loading configuration…")
        loading.font = .systemFont(ofSize: 10)
        loading.textColor = .tertiaryLabelColor
        loading.translatesAutoresizingMaskIntoConstraints = false
        configStack.addArrangedSubview(loading)
        loadingLabel = loading

        contentView.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 12),
            stack.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 12),
            stack.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -12),
            stack.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -12),
            searchRow.widthAnchor.constraint(equalTo: stack.widthAnchor),
            configStack.widthAnchor.constraint(equalTo: stack.widthAnchor),
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

        NotificationCenter.default.addObserver(self, selector: #selector(driveStatusChanged), name: .driveStatusDidChange, object: nil)

        refreshDriveStatus()
        loadAllConfigs()
    }

    deinit {
        streamTimer?.cancel()
        NotificationCenter.default.removeObserver(self)
    }

    // MARK: - Public Actions

    @objc func refreshAll() {
        refreshDriveStatus()
        reloadAllConfigs()
    }

    @objc func saveToFlash() {
        guard let window = view.window, let client = connection.apiClient else { return }
        let alert = NSAlert()
        alert.messageText = "Save to Flash?"
        alert.informativeText = "This will write the current configuration to non-volatile memory."
        alert.alertStyle = .informational
        alert.addButton(withTitle: "Save")
        alert.addButton(withTitle: "Cancel")
        alert.beginSheetModal(for: window) { response in
            guard response == .alertFirstButtonReturn else { return }
            Task {
                do {
                    try await client.saveConfigToFlash()
                    Log.info("Configuration saved to flash")
                } catch {
                    Log.error("Save to flash failed: \(error.localizedDescription)")
                }
            }
        }
    }

    @objc func resetToDefault() {
        guard let window = view.window, let client = connection.apiClient else { return }
        let alert = NSAlert()
        alert.messageText = "Reset to Defaults?"
        alert.informativeText = "This will reset all settings to factory defaults. Values stored in flash are not affected."
        alert.alertStyle = .warning
        alert.addButton(withTitle: "Reset")
        alert.addButton(withTitle: "Cancel")
        alert.beginSheetModal(for: window) { [weak self] response in
            guard response == .alertFirstButtonReturn else { return }
            Task {
                do {
                    try await client.resetConfigToDefault()
                    Log.info("Configuration reset to defaults")
                    try? await Task.sleep(for: .milliseconds(500))
                    await MainActor.run {
                        self?.reloadAllConfigs()
                    }
                } catch {
                    Log.error("Reset to default failed: \(error.localizedDescription)")
                }
            }
        }
    }

    // MARK: - Device Info

    private func addInfoRow(_ label: String, value: String, to stack: NSStackView) {
        let valueLabel = NSTextField(labelWithString: value)
        valueLabel.font = .systemFont(ofSize: 11)
        valueLabel.textColor = .secondaryLabelColor
        addInfoRowWithLabel(label, valueLabel: valueLabel, to: stack)
    }

    private func addInfoRowWithLabel(_ label: String, valueLabel: NSTextField, to stack: NSStackView) {
        let row = NSStackView()
        row.orientation = .horizontal
        row.spacing = 8
        row.translatesAutoresizingMaskIntoConstraints = false

        let nameLabel = NSTextField(labelWithString: label)
        nameLabel.font = .systemFont(ofSize: 11, weight: .medium)
        nameLabel.textColor = .labelColor
        nameLabel.widthAnchor.constraint(equalToConstant: 70).isActive = true

        row.addArrangedSubview(nameLabel)
        row.addArrangedSubview(valueLabel)
        stack.addArrangedSubview(row)
        row.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true
    }

    // MARK: - Stream Status

    private func startStreamTimer() {
        let timer = DispatchSource.makeTimerSource(queue: .main)
        timer.schedule(deadline: .now() + 0.5, repeating: 0.5)
        timer.setEventHandler { [weak self] in
            self?.updateStreamStatus()
        }
        timer.resume()
        streamTimer = timer
    }

    private func updateStreamStatus() {
        let active = connection.streamsActive
        streamStatusLabel.stringValue = active ? "Active" : "Inactive"
        streamStatusLabel.textColor = active ? .systemGreen : .secondaryLabelColor
        streamFPSLabel.stringValue = "\(Int(connection.framesPerSecond)) fps"
    }

    // MARK: - Drive Status

    private func makeDriveRow(_ drive: String) -> (view: NSView, imageLabel: NSTextField, typeLabel: NSTextField) {
        let row = NSStackView()
        row.orientation = .horizontal
        row.spacing = 4
        row.translatesAutoresizingMaskIntoConstraints = false

        let icon = NSImageView(image: NSImage(systemSymbolName: "externaldrive.fill", accessibilityDescription: nil)!)
        icon.contentTintColor = .secondaryLabelColor
        icon.setContentHuggingPriority(.required, for: .horizontal)

        let driveLabel = NSTextField(labelWithString: "\(drive):")
        driveLabel.font = .systemFont(ofSize: 10, weight: .semibold)
        driveLabel.textColor = .secondaryLabelColor
        driveLabel.setContentHuggingPriority(.required, for: .horizontal)

        let typeLabel = NSTextField(labelWithString: "")
        typeLabel.font = .systemFont(ofSize: 10)
        typeLabel.textColor = .tertiaryLabelColor
        typeLabel.setContentHuggingPriority(.required, for: .horizontal)

        let imageLabel = NSTextField(labelWithString: "—")
        imageLabel.font = .systemFont(ofSize: 10)
        imageLabel.lineBreakMode = .byTruncatingMiddle

        let ejectButton = NSButton(image: NSImage(systemSymbolName: "eject.fill", accessibilityDescription: "Eject")!, target: self, action: #selector(ejectDrive(_:)))
        ejectButton.bezelStyle = .toolbar
        ejectButton.controlSize = .mini
        ejectButton.tag = drive == "A" ? 0 : 1

        row.addArrangedSubview(icon)
        row.addArrangedSubview(driveLabel)
        row.addArrangedSubview(typeLabel)
        row.addArrangedSubview(imageLabel)
        row.addArrangedSubview(ejectButton)

        return (row, imageLabel, typeLabel)
    }

    @objc private func driveStatusChanged() {
        refreshDriveStatus()
    }

    private func refreshDriveStatus() {
        guard let client = connection.apiClient else { return }
        Task {
            do {
                let drives = try await client.fetchDrives()
                updateDriveUI(driveALabel, typeLabel: driveATypeLabel, info: drives["a"])
                updateDriveUI(driveBLabel, typeLabel: driveBTypeLabel, info: drives["b"])
            } catch {
                Log.error("[System] Drive status error: \(error)")
            }
        }
    }

    private func updateDriveUI(_ label: NSTextField?, typeLabel: NSTextField?, info: [String: Any]?) {
        guard let label, let typeLabel else { return }
        guard let info else {
            label.stringValue = "—"
            label.textColor = .tertiaryLabelColor
            typeLabel.stringValue = ""
            return
        }

        let enabled = info["enabled"] as? Bool ?? false
        let image = info["image_file"] as? String ?? ""
        let driveType = info["type"] as? String ?? ""

        typeLabel.stringValue = "[\(driveType)]"

        if !enabled {
            label.stringValue = "Disabled"
            label.textColor = .tertiaryLabelColor
        } else if image.isEmpty {
            label.stringValue = "Empty"
            label.textColor = .secondaryLabelColor
        } else {
            label.stringValue = (image as NSString).lastPathComponent
            label.textColor = .labelColor
        }
    }

    @objc private func ejectDrive(_ sender: NSButton) {
        let drive = sender.tag == 0 ? "a" : "b"
        guard let client = connection.apiClient else { return }
        Task {
            do {
                try await client.removeDisk(drive: drive)
                NotificationCenter.default.post(name: .driveStatusDidChange, object: nil)
                refreshDriveStatus()
            } catch {
                Log.error("[System] Eject error: \(error)")
            }
        }
    }

    // MARK: - Configuration

    private func loadAllConfigs() {
        guard let client = connection.apiClient else { return }
        Task {
            do {
                let categories = try await client.fetchConfigCategories()
                for category in categories {
                    let items = try await client.fetchConfigCategory(category)
                    addConfigCategory(category, items: items)
                }
                loadingLabel?.removeFromSuperview()
                loadingLabel = nil
            } catch {
                Log.error("[System] Config load error: \(error)")
                loadingLabel?.stringValue = "Error loading configuration"
                loadingLabel?.textColor = .systemRed
            }
        }
    }

    private func reloadAllConfigs() {
        // Dismiss any active editor
        activeEditRow?.dismissEditor()
        activeEditRow = nil

        // Clear existing config UI
        for (_, header, container, _) in allConfigCategories {
            header.removeFromSuperview()
            container.removeFromSuperview()
        }
        allConfigCategories.removeAll()
        collapsedCategories.removeAll()
        preSearchCollapsed = nil

        let loading = NSTextField(labelWithString: "Loading configuration…")
        loading.font = .systemFont(ofSize: 10)
        loading.textColor = .tertiaryLabelColor
        loading.translatesAutoresizingMaskIntoConstraints = false
        configStack.addArrangedSubview(loading)
        loadingLabel = loading

        loadAllConfigs()
    }

    private func addConfigCategory(_ category: String, items: [String: Any]) {
        let sortedKeys = items.keys.sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }

        // Disclosure header button
        let header = NSButton()
        header.bezelStyle = .toolbar
        header.setButtonType(.pushOnPushOff)
        header.title = "\(category) (\(sortedKeys.count))"
        header.font = .systemFont(ofSize: 10, weight: .semibold)
        header.contentTintColor = .secondaryLabelColor
        header.alignment = .left
        header.imagePosition = .imageLeading
        header.image = NSImage(systemSymbolName: "chevron.right", accessibilityDescription: nil)
        header.target = self
        header.action = #selector(toggleCategory(_:))
        header.translatesAutoresizingMaskIntoConstraints = false
        configStack.addArrangedSubview(header)
        header.widthAnchor.constraint(equalTo: configStack.widthAnchor).isActive = true

        // Items container
        let itemsContainer = NSStackView()
        itemsContainer.orientation = .vertical
        itemsContainer.alignment = .leading
        itemsContainer.spacing = 1
        itemsContainer.translatesAutoresizingMaskIntoConstraints = false
        configStack.addArrangedSubview(itemsContainer)
        itemsContainer.widthAnchor.constraint(equalTo: configStack.widthAnchor).isActive = true

        var itemViews: [ConfigItemRow] = []
        for key in sortedKeys {
            let value = "\(items[key] ?? "")"
            let row = ConfigItemRow(category: category, name: key, value: value, connection: connection) { [weak self] row in
                self?.activateEditor(for: row)
            }
            itemsContainer.addArrangedSubview(row)
            row.widthAnchor.constraint(equalTo: itemsContainer.widthAnchor).isActive = true
            itemViews.append(row)
        }

        // Start collapsed
        collapsedCategories.insert(category)
        itemsContainer.isHidden = true

        allConfigCategories.append((category, header, itemsContainer, itemViews))
    }

    /// Dismiss any active editor and activate the new one
    fileprivate func activateEditor(for row: ConfigItemRow) {
        if activeEditRow === row { return }
        activeEditRow?.dismissEditor()
        activeEditRow = row
        row.fetchDetailsAndEdit()
    }

    @objc private func toggleCategory(_ sender: NSButton) {
        guard let index = allConfigCategories.firstIndex(where: { $0.header === sender }) else { return }
        let entry = allConfigCategories[index]
        let category = entry.category

        if collapsedCategories.contains(category) {
            collapsedCategories.remove(category)
            entry.itemsContainer.isHidden = false
            sender.image = NSImage(systemSymbolName: "chevron.down", accessibilityDescription: nil)
        } else {
            collapsedCategories.insert(category)
            entry.itemsContainer.isHidden = true
            sender.image = NSImage(systemSymbolName: "chevron.right", accessibilityDescription: nil)
        }
    }

    // MARK: - Search

    @objc private func searchChanged(_ sender: NSSearchField) {
        let query = sender.stringValue.lowercased()

        if query.isEmpty {
            if let saved = preSearchCollapsed {
                for entry in allConfigCategories {
                    let shouldCollapse = saved.contains(entry.category)
                    entry.itemsContainer.isHidden = shouldCollapse
                    entry.header.image = NSImage(systemSymbolName: shouldCollapse ? "chevron.right" : "chevron.down", accessibilityDescription: nil)
                    if shouldCollapse {
                        collapsedCategories.insert(entry.category)
                    } else {
                        collapsedCategories.remove(entry.category)
                    }
                    for item in entry.items { item.isHidden = false }
                    entry.header.isHidden = false
                }
                preSearchCollapsed = nil
            }
            return
        }

        if preSearchCollapsed == nil {
            preSearchCollapsed = collapsedCategories
        }

        for entry in allConfigCategories {
            var hasVisibleItems = false
            for itemView in entry.items {
                let matches = itemView.itemName.lowercased().contains(query)
                    || itemView.currentValue.lowercased().contains(query)
                itemView.isHidden = !matches
                if matches { hasVisibleItems = true }
            }

            if hasVisibleItems {
                entry.header.isHidden = false
                entry.itemsContainer.isHidden = false
                collapsedCategories.remove(entry.category)
                entry.header.image = NSImage(systemSymbolName: "chevron.down", accessibilityDescription: nil)
            } else if entry.category.lowercased().contains(query) {
                entry.header.isHidden = false
                entry.itemsContainer.isHidden = false
                for item in entry.items { item.isHidden = false }
                collapsedCategories.remove(entry.category)
                entry.header.image = NSImage(systemSymbolName: "chevron.down", accessibilityDescription: nil)
            } else {
                entry.header.isHidden = true
                entry.itemsContainer.isHidden = true
            }
        }
    }

    // MARK: - UI Helpers

    private func addSection(_ title: String, to stack: NSStackView) {
        let label = NSTextField(labelWithString: title)
        label.font = .systemFont(ofSize: 13, weight: .bold)
        label.textColor = .secondaryLabelColor
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
}

// MARK: - Config Item Row

/// Shows a static label + value. On click, fetches item details and swaps in an edit control.
private final class ConfigItemRow: NSView {
    let category: String
    let itemName: String
    private(set) var currentValue: String
    private let connection: C64Connection
    private let onActivate: (ConfigItemRow) -> Void

    private let row: NSStackView
    private let nameLabel: NSTextField
    private let valueLabel: NSTextField
    private var editControl: NSView?
    private var isEditing = false
    private var clickGesture: NSClickGestureRecognizer?

    init(category: String, name: String, value: String, connection: C64Connection, onActivate: @escaping (ConfigItemRow) -> Void) {
        self.category = category
        self.itemName = name
        self.currentValue = value
        self.connection = connection
        self.onActivate = onActivate

        row = NSStackView()
        nameLabel = NSTextField(labelWithString: name)
        valueLabel = NSTextField(labelWithString: value)

        super.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false
        setupUI()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    private func setupUI() {
        row.orientation = .horizontal
        row.spacing = 6
        row.distribution = .fill
        row.translatesAutoresizingMaskIntoConstraints = false

        nameLabel.font = .systemFont(ofSize: 10)
        nameLabel.alignment = .right
        nameLabel.lineBreakMode = .byTruncatingTail
        nameLabel.setContentCompressionResistancePriority(.required, for: .horizontal)
        nameLabel.setContentHuggingPriority(.required, for: .horizontal)
        nameLabel.widthAnchor.constraint(equalToConstant: 150).isActive = true

        valueLabel.font = .systemFont(ofSize: 10)
        valueLabel.textColor = .secondaryLabelColor
        valueLabel.alignment = .left
        valueLabel.lineBreakMode = .byTruncatingTail
        valueLabel.setContentHuggingPriority(.defaultLow, for: .horizontal)
        valueLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)

        row.addArrangedSubview(nameLabel)
        row.addArrangedSubview(valueLabel)
        row.edgeInsets = NSEdgeInsets(top: 4, left: 0, bottom: 4, right: 0)

        addSubview(row)
        NSLayoutConstraint.activate([
            row.topAnchor.constraint(equalTo: topAnchor),
            row.leadingAnchor.constraint(equalTo: leadingAnchor),
            row.trailingAnchor.constraint(equalTo: trailingAnchor),
            row.bottomAnchor.constraint(equalTo: bottomAnchor),
        ])

        // Click to edit
        let click = NSClickGestureRecognizer(target: self, action: #selector(rowClicked(_:)))
        addGestureRecognizer(click)
        clickGesture = click
    }

    @objc private func rowClicked(_ sender: NSClickGestureRecognizer) {
        if !isEditing {
            onActivate(self)
        }
    }

    // MARK: - Edit Mode

    func fetchDetailsAndEdit() {
        guard !isEditing, let client = connection.apiClient else { return }
        valueLabel.stringValue = "Loading…"
        valueLabel.textColor = .tertiaryLabelColor

        Task {
            do {
                let details = try await client.fetchConfigItemDetails(category, item: itemName)
                let detail = ConfigItemDetail(name: itemName, category: category, details: details)
                showEditor(for: detail)
            } catch {
                Log.error("[System] Failed to fetch details for \(category)/\(itemName): \(error)")
                valueLabel.stringValue = currentValue
                valueLabel.textColor = .secondaryLabelColor
            }
        }
    }

    private func showEditor(for detail: ConfigItemDetail) {
        isEditing = true
        valueLabel.isHidden = true

        // Remove gesture recognizer so edit controls receive clicks
        if let gesture = clickGesture {
            removeGestureRecognizer(gesture)
        }

        if let defaultValue = detail.defaultValue {
            nameLabel.toolTip = "Default: \(defaultValue)"
        }

        let control: NSView
        switch detail.controlType {
        case .popup:
            control = makePopupControl(detail: detail)
        case .numeric:
            control = makeNumericControl(detail: detail)
        case .text:
            control = makeTextControl(detail: detail)
        }

        row.addArrangedSubview(control)
        control.setContentHuggingPriority(.required, for: .horizontal)
        editControl = control
    }

    func dismissEditor() {
        guard isEditing else { return }
        isEditing = false
        nameLabel.toolTip = nil

        if let control = editControl {
            row.removeArrangedSubview(control)
            control.removeFromSuperview()
            editControl = nil
        }

        // Restore gesture recognizer
        if let gesture = clickGesture {
            addGestureRecognizer(gesture)
        }

        valueLabel.stringValue = currentValue
        valueLabel.textColor = .secondaryLabelColor
        valueLabel.isHidden = false
    }

    // MARK: - Edit Controls

    private func makePopupControl(detail: ConfigItemDetail) -> NSView {
        let popup = NSPopUpButton(frame: .zero, pullsDown: false)
        popup.controlSize = .small
        popup.font = .systemFont(ofSize: 10)
        popup.translatesAutoresizingMaskIntoConstraints = false

        if let values = detail.values {
            popup.addItems(withTitles: values)
            popup.selectItem(withTitle: detail.current)
        }

        popup.target = self
        popup.action = #selector(popupChanged(_:))
        popup.setContentHuggingPriority(.defaultHigh, for: .horizontal)

        return popup
    }

    private func makeNumericControl(detail: ConfigItemDetail) -> NSView {
        let container = NSStackView()
        container.orientation = .horizontal
        container.spacing = 2
        container.translatesAutoresizingMaskIntoConstraints = false

        let textField = NSTextField()
        textField.font = .monospacedDigitSystemFont(ofSize: 10, weight: .regular)
        textField.controlSize = .small
        textField.stringValue = detail.current
        textField.alignment = .right
        textField.translatesAutoresizingMaskIntoConstraints = false
        textField.widthAnchor.constraint(greaterThanOrEqualToConstant: 50).isActive = true
        textField.delegate = self
        textField.tag = 100

        let stepper = NSStepper()
        stepper.controlSize = .small
        stepper.minValue = Double(detail.min ?? 0)
        stepper.maxValue = Double(detail.max ?? 100)
        stepper.integerValue = Int(detail.current) ?? detail.min ?? 0
        stepper.valueWraps = false
        stepper.target = self
        stepper.action = #selector(stepperChanged(_:))
        stepper.translatesAutoresizingMaskIntoConstraints = false
        stepper.tag = 101

        container.addArrangedSubview(textField)
        container.addArrangedSubview(stepper)
        container.setContentHuggingPriority(.defaultHigh, for: .horizontal)

        return container
    }

    private func makeTextControl(detail: ConfigItemDetail) -> NSView {
        let textField = NSTextField()
        textField.font = .monospacedSystemFont(ofSize: 10, weight: .regular)
        textField.controlSize = .small
        textField.stringValue = detail.current
        textField.translatesAutoresizingMaskIntoConstraints = false
        textField.setContentHuggingPriority(.defaultHigh, for: .horizontal)
        textField.delegate = self

        return textField
    }

    // MARK: - Actions

    @objc private func popupChanged(_ sender: NSPopUpButton) {
        guard let value = sender.titleOfSelectedItem else { return }
        setConfigValue(value)
    }

    @objc private func stepperChanged(_ sender: NSStepper) {
        let value = "\(sender.integerValue)"
        if let container = sender.superview as? NSStackView,
           let textField = container.arrangedSubviews.first(where: { $0.tag == 100 }) as? NSTextField {
            textField.stringValue = value
        }
        setConfigValue(value)
    }

    private func setConfigValue(_ value: String) {
        guard let client = connection.apiClient else { return }
        currentValue = value
        Task {
            do {
                try await client.setConfigItem(category, item: itemName, value: value)
                Log.info("[System] Set \(category)/\(itemName) = \(value)")
            } catch {
                Log.error("[System] Failed to set \(category)/\(itemName): \(error)")
                flashError()
            }
        }
    }

    private func flashError() {
        wantsLayer = true
        layer?.backgroundColor = NSColor.systemRed.withAlphaComponent(0.2).cgColor
        DispatchQueue.main.asyncAfter(deadline: .now() + 1) { [weak self] in
            self?.layer?.backgroundColor = nil
        }
    }
}

// MARK: - NSTextFieldDelegate

extension ConfigItemRow: NSTextFieldDelegate {
    func control(_ control: NSControl, textShouldEndEditing fieldEditor: NSText) -> Bool {
        let value = fieldEditor.string

        if let container = control.superview as? NSStackView,
           let stepper = container.arrangedSubviews.first(where: { $0.tag == 101 }) as? NSStepper {
            stepper.integerValue = Int(value) ?? stepper.integerValue
        }

        setConfigValue(value)
        return true
    }
}

// MARK: - FlippedView

private final class FlippedView: NSView {
    override var isFlipped: Bool { true }
}
