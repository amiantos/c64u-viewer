// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.

import Foundation

enum SidebarItem: String, CaseIterable, Identifiable {
    // Settings
    case crtSettings
    case audioSettings

    // Tools
    case basicScratchpad
    case fileManager
    case driveManagement
    case diskFlipList
    case configurationManager

    // Developer
    case memoryBrowser
    case debugStreamViewer

    var id: String { rawValue }

    var label: String {
        switch self {
        case .crtSettings: "CRT Filter"
        case .audioSettings: "Audio"
        case .basicScratchpad: "BASIC Scratchpad"
        case .fileManager: "File Manager"
        case .driveManagement: "Drive Management"
        case .diskFlipList: "Disk Flip List"
        case .configurationManager: "Configuration"
        case .memoryBrowser: "Memory Browser"
        case .debugStreamViewer: "Debug Stream"
        }
    }

    var icon: String {
        switch self {
        case .crtSettings: "tv"
        case .audioSettings: "speaker.wave.2.fill"
        case .basicScratchpad: "chevron.left.forwardslash.chevron.right"
        case .fileManager: "folder"
        case .driveManagement: "externaldrive"
        case .diskFlipList: "square.stack"
        case .configurationManager: "gearshape"
        case .memoryBrowser: "memorychip"
        case .debugStreamViewer: "ladybug"
        }
    }

    var isImplemented: Bool {
        switch self {
        case .crtSettings, .audioSettings, .basicScratchpad, .fileManager:
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
        case .crtSettings: return 380
        case .audioSettings: return 350
        case .basicScratchpad: return 500
        case .fileManager, .driveManagement, .diskFlipList, .configurationManager: return 450
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
    SidebarSection(title: "Tools", items: [.basicScratchpad, .fileManager, .driveManagement, .diskFlipList, .configurationManager]),
    SidebarSection(title: "Developer", items: [.memoryBrowser, .debugStreamViewer]),
    SidebarSection(title: "Settings", items: [.crtSettings, .audioSettings]),
]
