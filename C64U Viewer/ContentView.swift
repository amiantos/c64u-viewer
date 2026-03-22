// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.

import MetalKit
import SwiftUI

struct ContentView: View {
    @State var connection: C64Connection
    @State private var showOverlay = false

    private var keyboardActive: Bool {
        connection.keyboardForwarder?.isEnabled == true
    }

    var body: some View {
        ZStack {
            Color.black

            MetalView(renderer: connection.renderer)
                .aspectRatio(CGFloat(384.0 / 272.0), contentMode: .fit)

            if !connection.isConnected {
                HomeView(connection: connection)
            }

            if connection.isConnected {
                // Clickable area to show overlay (below everything else)
                if !showOverlay {
                    Color.clear
                        .contentShape(Rectangle())
                        .onTapGesture { showOverlay = true }
                }

                // Status bar + keyboard strip (on top of tap area)
                VStack(spacing: 0) {
                    Spacer()

                    if keyboardActive, let forwarder = connection.keyboardForwarder {
                        C64KeyStripView(forwarder: forwarder, connection: connection)
                    }

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
                        if keyboardActive {
                            Text("KB")
                                .font(.caption)
                                .bold()
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(.blue.opacity(0.8), in: RoundedRectangle(cornerRadius: 4))
                                .foregroundStyle(.white)
                        }
                        Text("\(Int(connection.framesPerSecond)) fps")
                            .font(.caption)
                            .monospacedDigit()
                            .foregroundStyle(.white.opacity(0.7))
                    }
                    .padding(8)
                }
                .allowsHitTesting(keyboardActive)
            }

            // Unified overlay (works in both Viewer and Toolbox modes)
            if showOverlay && connection.isConnected {
                OverlayContainerView(connection: connection) {
                    showOverlay = false
                }
            }
        }
        .frame(minWidth: 480, minHeight: 340)
        .focusable(keyboardActive)
        .onKeyPress(phases: .down) { press in
            guard keyboardActive, let forwarder = connection.keyboardForwarder else {
                return .ignored
            }

            // Handle special keys via key equivalents
            switch press.key {
            case .return, .init("\r"):
                forwarder.sendKey(0x0D)
                return .handled
            case .delete:
                forwarder.sendKey(0x14)
                return .handled
            case .escape:
                forwarder.sendKey(0x03) // RUN/STOP
                return .handled
            case .upArrow:
                forwarder.sendKey(0x91)
                return .handled
            case .downArrow:
                forwarder.sendKey(0x11)
                return .handled
            case .leftArrow:
                forwarder.sendKey(0x9D)
                return .handled
            case .rightArrow:
                forwarder.sendKey(0x1D)
                return .handled
            case .home:
                if press.modifiers.contains(.shift) {
                    forwarder.sendKey(0x93) // CLR
                } else {
                    forwarder.sendKey(0x13) // HOME
                }
                return .handled
            default:
                break
            }

            // Handle printable characters
            let chars = press.characters
            if !chars.isEmpty {
                forwarder.handleKeyPress(chars)
                return .handled
            }

            return .ignored
        }
        .onChange(of: connection.isConnected) { _, isConnected in
            if !isConnected {
                showOverlay = false
            }
        }
        .onChange(of: connection.isRecording) { _, isRecording in
            if let window = NSApplication.shared.windows.first {
                if isRecording {
                    window.styleMask.remove(.resizable)
                } else {
                    window.styleMask.insert(.resizable)
                }
            }
        }
    }
}
