// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.

import MetalKit
import SwiftUI

struct ContentView: View {
    @State var connection: C64Connection

    var body: some View {
        ZStack {
            Color.black

            MetalView(renderer: connection.renderer)
                .aspectRatio(CGFloat(384.0 / 272.0), contentMode: .fit)

            // Connection status overlay
            if !connection.isConnected {
                VStack(spacing: 12) {
                    Text("C64U Viewer")
                        .font(.title)
                        .foregroundStyle(.white)
                    Text("Not Connected")
                        .foregroundStyle(.secondary)
                    Button("Connect") {
                        connection.connect()
                    }
                    .buttonStyle(.borderedProminent)
                }
                .padding(24)
                .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12))
            }

            // Status bar overlay
            if connection.isConnected {
                VStack {
                    Spacer()
                    HStack {
                        if connection.isRecording {
                            Text("REC")
                                .font(.caption)
                                .bold()
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(.red.opacity(0.8), in: RoundedRectangle(cornerRadius: 4))
                                .foregroundStyle(.white)
                        }
                        Spacer()
                        Text("\(Int(connection.framesPerSecond)) fps")
                            .font(.caption)
                            .monospacedDigit()
                            .foregroundStyle(.white.opacity(0.7))
                    }
                    .padding(8)
                }
            }
        }
        .frame(minWidth: 480, minHeight: 340)
    }
}
