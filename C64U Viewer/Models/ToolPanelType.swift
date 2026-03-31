// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.

import Foundation

enum SidebarItem: String, CaseIterable, Identifiable {
    // Tools
    case basicScratchpad
    case fileManager

    // Developer
    case memoryBrowser
    case debugStreamViewer

    // Settings
    case system
    case displayAndAudio

    var id: String { rawValue }

    var label: String {
        switch self {
        case .basicScratchpad: "BASIC Scratchpad"
        case .fileManager: "File Manager"
        case .memoryBrowser: "Memory Browser"
        case .debugStreamViewer: "Debug Stream"
        case .system: "System"
        case .displayAndAudio: "Display & Audio"
        }
    }

    var icon: String {
        switch self {
        case .basicScratchpad: "chevron.left.forwardslash.chevron.right"
        case .fileManager: "folder"
        case .memoryBrowser: "memorychip"
        case .debugStreamViewer: "ladybug"
        case .system: "gearshape"
        case .displayAndAudio: "tv"
        }
    }

    var isImplemented: Bool {
        switch self {
        case .basicScratchpad, .fileManager, .system, .displayAndAudio, .memoryBrowser:
            return true
        default:
            return false
        }
    }

    var hasInspector: Bool {
        true
    }

    var preferredInspectorWidth: CGFloat {
        switch self {
        case .basicScratchpad: return 500
        case .fileManager: return 450
        case .system: return 420
        case .displayAndAudio: return 400
        case .memoryBrowser: return 500
        case .debugStreamViewer: return 450
        }
    }
}

// MARK: - Sidebar Sections

struct SidebarSection {
    let title: String?
    let items: [SidebarItem]
}

let sidebarSections: [SidebarSection] = [
    SidebarSection(title: "Tools", items: [.basicScratchpad, .fileManager]),
    SidebarSection(title: "Developer", items: [.memoryBrowser]),
    SidebarSection(title: "Settings", items: [.system, .displayAndAudio]),
]
