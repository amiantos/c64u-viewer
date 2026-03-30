// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.

import AppKit

final class AudioSettingsViewController: NSViewController {
    let connection: C64Connection

    init(connection: C64Connection) {
        self.connection = connection
        super.init(nibName: nil, bundle: nil)
        self.title = "Audio"
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    override func loadView() {
        let container = BackgroundView()
        container.backgroundColor = .controlBackgroundColor

        let stack = NSStackView()
        stack.orientation = .vertical
        stack.spacing = 12
        stack.translatesAutoresizingMaskIntoConstraints = false

        stack.addArrangedSubview(makeSliderRow("Volume", value: Double(connection.volume),
                                                range: 0...1, action: #selector(volumeChanged(_:))))
        stack.addArrangedSubview(makeSliderRow("Balance", value: Double(connection.balance),
                                                range: -1...1, action: #selector(balanceChanged(_:))))

        container.addSubview(stack)

        let safe = container.safeAreaLayoutGuide
        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: safe.topAnchor, constant: 16),
            stack.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 16),
            stack.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -16),
        ])

        self.view = container
    }

    private func makeSliderRow(_ label: String, value: Double, range: ClosedRange<Double>, action: Selector) -> NSStackView {
        let row = NSStackView()
        row.orientation = .horizontal
        row.spacing = 8

        let nameLabel = NSTextField(labelWithString: label)
        nameLabel.font = .systemFont(ofSize: 11)
        nameLabel.widthAnchor.constraint(equalToConstant: 60).isActive = true

        let slider = NSSlider(value: value, minValue: range.lowerBound, maxValue: range.upperBound,
                              target: self, action: action)
        slider.controlSize = .small

        row.addArrangedSubview(nameLabel)
        row.addArrangedSubview(slider)
        return row
    }

    @objc private func volumeChanged(_ sender: NSSlider) {
        connection.volume = Float(sender.doubleValue)
        connection.isMuted = false
    }

    @objc private func balanceChanged(_ sender: NSSlider) {
        connection.balance = Float(sender.doubleValue)
    }
}
