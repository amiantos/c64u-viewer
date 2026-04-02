// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.

import Foundation

struct ConfigItemDetail {
    let name: String
    let category: String
    var current: String
    let defaultValue: String?
    let values: [String]?
    let min: Int?
    let max: Int?
    let format: String?

    var controlType: ConfigControlType {
        if let values, !values.isEmpty { return .popup }
        if min != nil && max != nil { return .numeric }
        return .text
    }

    init(name: String, category: String, details: [String: Any]) {
        self.name = name
        self.category = category
        self.current = "\(details["current"] ?? "")"
        self.defaultValue = details["default"].map { "\($0)" }
        self.values = details["values"] as? [String]
        self.min = details["min"] as? Int
        self.max = details["max"] as? Int
        self.format = details["format"] as? String
    }
}

enum ConfigControlType {
    case popup
    case numeric
    case text
}

extension Notification.Name {
    static let driveStatusDidChange = Notification.Name("driveStatusDidChange")
}
