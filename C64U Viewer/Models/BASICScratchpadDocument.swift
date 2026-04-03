// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.

import Foundation

final class BASICScratchpadDocument {
    var code: String = BASICSamples.helloWorld
    var savedContent: String = BASICSamples.helloWorld
    var fileURL: URL? = nil

    var isDirty: Bool { code != savedContent }

    var displayName: String {
        fileURL?.lastPathComponent ?? "Untitled"
    }
}
