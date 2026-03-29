// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.

enum ToolPanelType: String, CaseIterable, Identifiable {
    case basicScratchpad

    var id: String { rawValue }

    var label: String {
        switch self {
        case .basicScratchpad: "BASIC Scratchpad"
        }
    }

    var icon: String {
        switch self {
        case .basicScratchpad: "chevron.left.forwardslash.chevron.right"
        }
    }
}
