// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.

enum SidebarItem: String, CaseIterable, Identifiable {
    case dataStreams
    case crtSettings
    case audioSettings
    case basicScratchpad

    var id: String { rawValue }

    var label: String {
        switch self {
        case .dataStreams: "Data Streams"
        case .crtSettings: "CRT Filter"
        case .audioSettings: "Audio"
        case .basicScratchpad: "BASIC Scratchpad"
        }
    }

    var icon: String {
        switch self {
        case .dataStreams: "play.display"
        case .crtSettings: "tv"
        case .audioSettings: "speaker.wave.2.fill"
        case .basicScratchpad: "chevron.left.forwardslash.chevron.right"
        }
    }

    /// Whether this item opens an inspector panel
    var hasInspector: Bool {
        self != .dataStreams
    }
}
