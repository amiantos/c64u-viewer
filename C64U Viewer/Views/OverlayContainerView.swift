// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.

import SwiftUI

enum OverlayMode {
    case controls
    case crtSettings
    case audio
}

struct OverlayContainerView: View {
    @Bindable var connection: C64Connection
    let onDismiss: () -> Void
    @State private var mode: OverlayMode = .controls

    var body: some View {
        ZStack {
            Color.black.opacity(mode == .crtSettings ? 0.0 : 0.4)
                .onTapGesture { onDismiss() }
                .animation(.easeInOut(duration: 0.2), value: mode)

            switch mode {
            case .controls:
                ControlsOverlayView(
                    connection: connection,
                    onCustomize: { mode = .crtSettings },
                    onAudio: { mode = .audio },
                    onDismiss: onDismiss
                )
            case .crtSettings:
                CRTSettingsOverlayView(
                    connection: connection,
                    onBack: { mode = .controls },
                    onDismiss: onDismiss
                )
            case .audio:
                AudioSettingsOverlayView(
                    connection: connection,
                    onBack: { mode = .controls },
                    onDismiss: onDismiss
                )
            }
        }
        .onKeyPress(.escape) {
            if mode != .controls {
                mode = .controls
            } else {
                onDismiss()
            }
            return .handled
        }
    }
}
