// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.

import MetalKit
import SwiftUI

struct ContentView: View {
    @State var connection: C64Connection
    @State private var showCRTSettings = false
    @State private var showAudioSettings = false

    private var keyboardActive: Bool {
        connection.keyboardForwarder?.isEnabled == true
    }

    var body: some View {
        ZStack {
            if !connection.isConnected {
                Color.black
                MetalView(renderer: connection.renderer)
                    .aspectRatio(CGFloat(384.0 / 272.0), contentMode: .fit)
                HomeView(connection: connection)
            } else {
                connectedView
            }

            // Settings modals (centered overlays)
            if showCRTSettings {
                settingsOverlay {
                    CRTSettingsOverlayView(
                        connection: connection,
                        onDismiss: { showCRTSettings = false }
                    )
                }
            }

            if showAudioSettings {
                settingsOverlay {
                    AudioSettingsOverlayView(
                        connection: connection,
                        onDismiss: { showAudioSettings = false }
                    )
                }
            }
        }
        .frame(minWidth: 480, minHeight: 340)
        .focusable(keyboardActive)
        .onKeyPress(phases: .down) { press in
            guard keyboardActive, let forwarder = connection.keyboardForwarder else {
                return .ignored
            }

            switch press.key {
            case .return, .init("\r"):
                forwarder.sendKey(0x0D)
                return .handled
            case .delete:
                forwarder.sendKey(0x14)
                return .handled
            case .escape:
                forwarder.sendKey(0x03)
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
                forwarder.sendKey(press.modifiers.contains(.shift) ? 0x93 : 0x13)
                return .handled
            default:
                break
            }

            let chars = press.characters
            if !chars.isEmpty {
                forwarder.handleKeyPress(chars)
                return .handled
            }

            return .ignored
        }
        .onChange(of: connection.isConnected) { _, isConnected in
            if !isConnected {
                showCRTSettings = false
                showAudioSettings = false
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

    // MARK: - Connected View

    private var connectedView: some View {
        VStack(spacing: 0) {
            // Toolbar (Toolbox mode only)
            if connection.connectionMode == .toolbox {
                ToolboxToolbarView(
                    connection: connection,
                    onShowCRTSettings: { showCRTSettings = true },
                    onShowAudioSettings: { showAudioSettings = true }
                )
            }

            // Main content: video + optional tool panel
            HStack(spacing: 0) {
                // Video area
                ZStack {
                    Color.black
                    MetalView(renderer: connection.renderer)
                        .aspectRatio(CGFloat(384.0 / 272.0), contentMode: .fit)

                    VStack(spacing: 0) {
                        Spacer()

                        if keyboardActive, let forwarder = connection.keyboardForwarder {
                            C64KeyStripView(forwarder: forwarder, connection: connection)
                        }

                        StatusBarView(connection: connection, keyboardActive: keyboardActive)
                    }
                    .allowsHitTesting(keyboardActive)
                }

                // Tool panel (right side)
                if connection.connectionMode == .toolbox, connection.activeToolPanel != nil {
                    ToolPanelContainer(connection: connection)
                }
            }
        }
    }

    // MARK: - Settings Overlay Wrapper

    private func settingsOverlay<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        ZStack {
            Color.black.opacity(0.4)
                .onTapGesture {
                    showCRTSettings = false
                    showAudioSettings = false
                }
            content()
        }
        .onKeyPress(.escape) {
            showCRTSettings = false
            showAudioSettings = false
            return .handled
        }
    }
}
