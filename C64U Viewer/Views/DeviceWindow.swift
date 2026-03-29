// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.

import AppKit

final class DeviceWindow: NSWindow {
    override func keyDown(with event: NSEvent) {
        if let controller = windowController as? DeviceWindowController,
           controller.handleKeyDown(with: event) {
            return
        }
        super.keyDown(with: event)
    }
}
