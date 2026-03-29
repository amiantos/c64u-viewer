// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.

import SwiftUI

struct StatusBarView: View {
    let connection: C64Connection
    let keyboardActive: Bool

    var body: some View {
        HStack {
            if connection.isRecording {
                badge("REC", color: .red)
            }
            Spacer()
            if keyboardActive {
                badge("KB", color: .blue)
            }
            Text("\(Int(connection.framesPerSecond)) fps")
                .font(.caption)
                .monospacedDigit()
                .foregroundStyle(.white.opacity(0.7))
        }
        .padding(8)
    }

    private func badge(_ text: String, color: Color) -> some View {
        Text(text)
            .font(.caption)
            .bold()
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(color.opacity(0.8), in: RoundedRectangle(cornerRadius: 4))
            .foregroundStyle(.white)
    }
}
