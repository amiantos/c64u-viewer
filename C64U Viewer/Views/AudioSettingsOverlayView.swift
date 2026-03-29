// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.

import SwiftUI

struct AudioSettingsOverlayView: View {
    @Bindable var connection: C64Connection
    let onDismiss: () -> Void

    var body: some View {
        VStack(spacing: 16) {
            HStack {
                Spacer()

                Text("Audio")
                    .font(.title3)
                    .fontWeight(.semibold)

                Spacer()

                Button { onDismiss() } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.title2)
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
            }

            VStack(spacing: 6) {
                SliderRow(label: "Volume", value: Binding(
                    get: { connection.volume },
                    set: {
                        connection.volume = $0
                        connection.isMuted = false
                    }
                ), range: 0...1)
                SliderRow(label: "Balance", value: $connection.balance, range: -1...1)
            }
            .padding(12)
            .background(.background.opacity(0.6), in: RoundedRectangle(cornerRadius: 12))
        }
        .padding(20)
        .frame(width: 400)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16))
        .shadow(radius: 20)
    }
}
