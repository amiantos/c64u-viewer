// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.

import SwiftUI

struct ToolPanelDivider: View {
    @Binding var width: CGFloat

    @State private var isDragging = false
    @State private var startWidth: CGFloat = 0

    var body: some View {
        Rectangle()
            .fill(isDragging ? Color.accentColor.opacity(0.5) : Color.gray.opacity(0.3))
            .frame(width: 5)
            .onHover { inside in
                if inside {
                    NSCursor.resizeLeftRight.push()
                } else {
                    NSCursor.pop()
                }
            }
            .gesture(
                DragGesture()
                    .onChanged { value in
                        if !isDragging {
                            isDragging = true
                            startWidth = width
                        }
                        // Dragging left = panel grows (negative translation)
                        let newWidth = startWidth - value.translation.width
                        width = min(600, max(250, newWidth))
                    }
                    .onEnded { _ in
                        isDragging = false
                    }
            )
    }
}
