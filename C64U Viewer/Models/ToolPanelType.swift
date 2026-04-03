// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.

import Foundation

/// Inspector panels opened via toolbar buttons on the right side
enum InspectorPanel: String, CaseIterable {
    case system
    case displayAndAudio

    var label: String {
        switch self {
        case .system: "Device Info"
        case .displayAndAudio: "App Settings"
        }
    }

    var icon: String {
        switch self {
        case .system: "gearshape"
        case .displayAndAudio: "tv"
        }
    }

    var preferredWidth: CGFloat {
        switch self {
        case .system: return 420
        case .displayAndAudio: return 400
        }
    }
}
