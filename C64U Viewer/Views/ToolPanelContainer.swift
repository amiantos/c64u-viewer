// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.

import SwiftUI

struct ToolPanelContainer: View {
    @Bindable var connection: C64Connection

    var body: some View {
        HStack(spacing: 0) {
            ToolPanelDivider(width: $connection.toolPanelWidth)

            Group {
                switch connection.activeToolPanel {
                case .basicScratchpad:
                    BASICScratchpadPanelView(connection: connection)
                case .none:
                    EmptyView()
                }
            }
            .frame(width: connection.toolPanelWidth)
        }
    }
}
