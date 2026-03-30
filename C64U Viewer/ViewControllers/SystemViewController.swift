// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.

import AppKit

final class SystemViewController: NSViewController {
    let connection: C64Connection
    private var driveALabel: NSTextField!
    private var driveATypeLabel: NSTextField!
    private var driveBLabel: NSTextField!
    private var driveBTypeLabel: NSTextField!
    private var configStack: NSStackView!
    private var searchField: NSSearchField!
    private var allConfigViews: [(category: String, view: NSView, items: [NSView])] = []

    init(connection: C64Connection) {
        self.connection = connection
        super.init(nibName: nil, bundle: nil)
        self.title = "System"
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    override func loadView() {
        let container = BackgroundView()
        container.backgroundColor = .controlBackgroundColor

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
        stack.addArrangedSubview(searchField)

        // Config categories container
        configStack = NSStackView()
        configStack.orientation = .vertical
        configStack.alignment = .leading
        configStack.spacing = 4
        configStack.translatesAutoresizingMaskIntoConstraints = false
        stack.addArrangedSubview(configStack)

        contentView.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 12),
            stack.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 12),
            stack.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -12),
            stack.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -12),
            searchField.widthAnchor.constraint(equalTo: stack.widthAnchor),
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

        refreshDriveStatus()
        loadAllConfigs()
    }

    // MARK: - Device Info

    private func addInfoRow(_ label: String, value: String, to stack: NSStackView) {
        let row = NSStackView()
        row.orientation = .horizontal
        row.spacing = 8
        row.translatesAutoresizingMaskIntoConstraints = false

        let nameLabel = NSTextField(labelWithString: label)
        nameLabel.font = .systemFont(ofSize: 11, weight: .medium)
        nameLabel.textColor = .secondaryLabelColor
        nameLabel.widthAnchor.constraint(equalToConstant: 70).isActive = true

        let valueLabel = NSTextField(labelWithString: value)
        valueLabel.font = .systemFont(ofSize: 11)

        row.addArrangedSubview(nameLabel)
        row.addArrangedSubview(valueLabel)
        stack.addArrangedSubview(row)
        row.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true
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

    private func refreshDriveStatus() {
        guard let client = connection.apiClient else { return }
        Task {
            do {
                let drives = try await client.fetchDrives()
                updateDriveUI(driveALabel, typeLabel: driveATypeLabel, info: drives["a"])
                updateDriveUI(driveBLabel, typeLabel: driveBTypeLabel, info: drives["b"])
            } catch {
                print("[System] Drive status error: \(error)")
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
                refreshDriveStatus()
            } catch {
                print("[System] Eject error: \(error)")
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
            } catch {
                print("[System] Config load error: \(error)")
            }
        }
    }

    private func addConfigCategory(_ category: String, items: [String: Any]) {
        let header = NSTextField(labelWithString: category)
        header.font = .systemFont(ofSize: 10, weight: .semibold)
        header.textColor = .secondaryLabelColor
        configStack.addArrangedSubview(header)

        var itemViews: [NSView] = [header]

        let sortedKeys = items.keys.sorted()
        for key in sortedKeys {
            let value = items[key]
            let row = makeConfigRow(category: category, item: key, value: value)
            configStack.addArrangedSubview(row)
            row.widthAnchor.constraint(equalTo: configStack.widthAnchor).isActive = true
            itemViews.append(row)
        }

        let sep = NSBox()
        sep.boxType = .separator
        sep.translatesAutoresizingMaskIntoConstraints = false
        configStack.addArrangedSubview(sep)
        sep.widthAnchor.constraint(equalTo: configStack.widthAnchor).isActive = true
        itemViews.append(sep)

        allConfigViews.append((category, header, itemViews))
    }

    private func makeConfigRow(category: String, item: String, value: Any?) -> NSView {
        let row = NSStackView()
        row.orientation = .horizontal
        row.spacing = 6
        row.translatesAutoresizingMaskIntoConstraints = false

        let nameLabel = NSTextField(labelWithString: item)
        nameLabel.font = .systemFont(ofSize: 10)
        nameLabel.lineBreakMode = .byTruncatingTail
        nameLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)

        let valueStr = "\(value ?? "")"
        let valueLabel = NSTextField(labelWithString: valueStr)
        valueLabel.font = .monospacedSystemFont(ofSize: 10, weight: .regular)
        valueLabel.textColor = .secondaryLabelColor
        valueLabel.alignment = .right
        valueLabel.setContentHuggingPriority(.required, for: .horizontal)

        row.addArrangedSubview(nameLabel)
        row.addArrangedSubview(valueLabel)

        return row
    }

    @objc private func searchChanged(_ sender: NSSearchField) {
        let query = sender.stringValue.lowercased()

        for (_, _, items) in allConfigViews {
            for itemView in items {
                if query.isEmpty {
                    itemView.isHidden = false
                } else {
                    // Check if any text in the view matches the query
                    let matches = viewContainsText(itemView, query: query)
                    itemView.isHidden = !matches
                }
            }
        }
    }

    private func viewContainsText(_ view: NSView, query: String) -> Bool {
        if let textField = view as? NSTextField {
            return textField.stringValue.lowercased().contains(query)
        }
        if let stack = view as? NSStackView {
            return stack.arrangedSubviews.contains { viewContainsText($0, query: query) }
        }
        return false
    }

    // MARK: - UI Helpers

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
}

private final class FlippedView: NSView {
    override var isFlipped: Bool { true }
}
