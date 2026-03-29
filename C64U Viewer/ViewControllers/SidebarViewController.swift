// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.

import AppKit

protocol SidebarViewControllerDelegate: AnyObject {
    func sidebarDidSelectItem(_ item: SidebarItem)
}

final class SidebarViewController: NSViewController, NSOutlineViewDataSource, NSOutlineViewDelegate {
    weak var delegate: SidebarViewControllerDelegate?
    let connection: C64Connection

    private let outlineView = NSOutlineView()
    private let sections = sidebarSections

    init(connection: C64Connection) {
        self.connection = connection
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    override func loadView() {
        let scrollView = NSScrollView()
        scrollView.hasVerticalScroller = true
        scrollView.autohidesScrollers = true

        let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("item"))
        column.title = ""
        outlineView.addTableColumn(column)
        outlineView.outlineTableColumn = column
        outlineView.headerView = nil
        outlineView.dataSource = self
        outlineView.delegate = self
        outlineView.style = .sourceList
        outlineView.rowHeight = 26
        outlineView.indentationPerLevel = 0

        scrollView.documentView = outlineView

        self.view = scrollView
        self.title = "Tools"

        // Expand all sections
        for section in sections {
            if let title = section.title {
                outlineView.expandItem(title)
            }
        }

    }

    func selectItem(_ item: SidebarItem) {
        let row = outlineView.row(forItem: item.rawValue)
        if row >= 0 {
            outlineView.selectRowIndexes(IndexSet(integer: row), byExtendingSelection: false)
        }
    }

    func deselectAll() {
        outlineView.deselectAll(nil)
    }

    // MARK: - NSOutlineViewDataSource

    func outlineView(_ outlineView: NSOutlineView, numberOfChildrenOfItem item: Any?) -> Int {
        if item == nil {
            // Root level: sections
            return sections.count
        }
        if let sectionKey = item as? String, let section = section(for: sectionKey) {
            return section.items.count
        }
        return 0
    }

    func outlineView(_ outlineView: NSOutlineView, child index: Int, ofItem item: Any?) -> Any {
        if item == nil {
            // Return section title as key
            return sections[index].title ?? ""
        }
        if let sectionKey = item as? String, let section = section(for: sectionKey) {
            return section.items[index].rawValue
        }
        return ""
    }

    func outlineView(_ outlineView: NSOutlineView, isItemExpandable item: Any) -> Bool {
        // Section headers are expandable (they have children)
        if let key = item as? String {
            return section(for: key) != nil
        }
        return false
    }

    // MARK: - NSOutlineViewDelegate

    func outlineView(_ outlineView: NSOutlineView, isGroupItem item: Any) -> Bool {
        // Section headers are group items
        if let key = item as? String {
            return section(for: key) != nil
        }
        return false
    }

    func outlineView(_ outlineView: NSOutlineView, shouldShowOutlineCellForItem item: Any) -> Bool {
        false // No disclosure triangles
    }

    func outlineView(_ outlineView: NSOutlineView, shouldSelectItem item: Any) -> Bool {
        // Only allow selecting leaf items (SidebarItem rawValues), not section headers
        guard let rawValue = item as? String, let sidebarItem = SidebarItem(rawValue: rawValue) else {
            return false
        }
        return sidebarItem.isImplemented
    }

    func outlineView(_ outlineView: NSOutlineView, viewFor tableColumn: NSTableColumn?, item: Any) -> NSView? {
        guard let key = item as? String else { return nil }

        // Check if it's a section header
        if let section = section(for: key), let title = section.title {
            let cellID = NSUserInterfaceItemIdentifier("SectionHeader")
            let cell: NSTableCellView
            if let existing = outlineView.makeView(withIdentifier: cellID, owner: nil) as? NSTableCellView {
                cell = existing
            } else {
                cell = NSTableCellView()
                cell.identifier = cellID
                let textField = NSTextField(labelWithString: "")
                textField.translatesAutoresizingMaskIntoConstraints = false
                textField.font = .systemFont(ofSize: 11, weight: .semibold)
                textField.textColor = .secondaryLabelColor
                cell.addSubview(textField)
                cell.textField = textField
                NSLayoutConstraint.activate([
                    textField.leadingAnchor.constraint(equalTo: cell.leadingAnchor, constant: 4),
                    textField.centerYAnchor.constraint(equalTo: cell.centerYAnchor),
                ])
            }
            cell.textField?.stringValue = title.uppercased()
            return cell
        }

        // Sidebar item
        guard let sidebarItem = SidebarItem(rawValue: key) else { return nil }

        let cellID = NSUserInterfaceItemIdentifier("SidebarCell")
        let cell: NSTableCellView
        if let existing = outlineView.makeView(withIdentifier: cellID, owner: nil) as? NSTableCellView {
            cell = existing
        } else {
            cell = NSTableCellView()
            cell.identifier = cellID

            let imageView = NSImageView()
            imageView.translatesAutoresizingMaskIntoConstraints = false
            cell.addSubview(imageView)
            cell.imageView = imageView

            let textField = NSTextField(labelWithString: "")
            textField.translatesAutoresizingMaskIntoConstraints = false
            cell.addSubview(textField)
            cell.textField = textField

            NSLayoutConstraint.activate([
                imageView.leadingAnchor.constraint(equalTo: cell.leadingAnchor, constant: 4),
                imageView.centerYAnchor.constraint(equalTo: cell.centerYAnchor),
                imageView.widthAnchor.constraint(equalToConstant: 16),
                imageView.heightAnchor.constraint(equalToConstant: 16),
                textField.leadingAnchor.constraint(equalTo: imageView.trailingAnchor, constant: 6),
                textField.trailingAnchor.constraint(equalTo: cell.trailingAnchor, constant: -4),
                textField.centerYAnchor.constraint(equalTo: cell.centerYAnchor),
            ])
        }

        cell.textField?.stringValue = sidebarItem.label
        cell.imageView?.image = NSImage(systemSymbolName: sidebarItem.icon, accessibilityDescription: sidebarItem.label)

        // Gray out unimplemented items
        let alpha: CGFloat = sidebarItem.isImplemented ? 1.0 : 0.4
        cell.textField?.alphaValue = alpha
        cell.imageView?.alphaValue = alpha

        return cell
    }

    func outlineViewSelectionDidChange(_ notification: Notification) {
        let row = outlineView.selectedRow
        guard row >= 0, let rawValue = outlineView.item(atRow: row) as? String,
              let item = SidebarItem(rawValue: rawValue) else { return }
        delegate?.sidebarDidSelectItem(item)
    }

    // MARK: - Helpers

    private func section(for key: String) -> SidebarSection? {
        sections.first { $0.title == key }
    }
}
