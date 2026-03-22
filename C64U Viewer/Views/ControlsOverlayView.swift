// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.

import SwiftUI
internal import UniformTypeIdentifiers

struct ControlsOverlayView: View {
    @Bindable var connection: C64Connection
    let onCustomize: () -> Void
    let onAudio: () -> Void
    let onDismiss: () -> Void

    @State private var showResetConfirm = false
    @State private var showRebootConfirm = false
    @State private var showPowerOffConfirm = false
    @State private var showKeyboardInfo = false

    private static let keyboardInfoShownKey = "c64_keyboard_info_shown"

    private let tileColumns = Array(repeating: GridItem(.flexible(), spacing: 10), count: 3)

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                header

                // Toolbox-only sections
                if connection.connectionMode == .toolbox {
                    deviceInfoTile
                }

                if connection.connectionMode == .toolbox {
                    controlGrid
                    statusArea
                } else {
                    // Viewer mode: just CRT filter button
                    viewerControls
                }
            }
            .padding(20)
        }
        .frame(width: 400)
        .frame(maxHeight: 560)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16))
        .shadow(radius: 20)
        .confirmationDialog("Reset Machine?", isPresented: $showResetConfirm) {
            Button("Reset", role: .destructive) { connection.machineAction(.reset) }
        }
        .confirmationDialog("Reboot Machine?", isPresented: $showRebootConfirm) {
            Button("Reboot", role: .destructive) { connection.machineAction(.reboot) }
        }
        .confirmationDialog("Power Off Machine?", isPresented: $showPowerOffConfirm) {
            Button("Power Off", role: .destructive) { connection.machineAction(.powerOff) }
        }
        .alert("Keyboard Forwarding", isPresented: $showKeyboardInfo) {
            Button("Enable") {
                UserDefaults.standard.set(true, forKey: Self.keyboardInfoShownKey)
                connection.keyboardForwarder?.isEnabled = true
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Keyboard input is forwarded to the C64 via the KERNAL keyboard buffer. This works with BASIC and programs that read input through the KERNAL, but does not work in the Ultimate menu or with most games that read the keyboard hardware directly.")
        }
    }

    // MARK: - Header

    private var header: some View {
        HStack {
            Text(connection.connectionMode == .toolbox ? "Toolbox" : "Controls")
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
    }

    // MARK: - Status (Toolbox only)

    @ViewBuilder
    private var statusArea: some View {
        if connection.isWaitingForReboot {
            HStack(spacing: 6) {
                ProgressView()
                    .controlSize(.small)
                Text("Waiting for device to restart...")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity)
            .padding(10)
            .background(.orange.opacity(0.15), in: RoundedRectangle(cornerRadius: 10))
        } else if let error = connection.connectionError {
            Label(error, systemImage: "exclamationmark.triangle.fill")
                .font(.caption)
                .foregroundStyle(.red)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(10)
                .background(.red.opacity(0.1), in: RoundedRectangle(cornerRadius: 10))
        }
    }

    // MARK: - Device Info (Toolbox only)

    @ViewBuilder
    private var deviceInfoTile: some View {
        if let info = connection.deviceInfo {
            HStack(spacing: 12) {
                Image(systemName: "desktopcomputer")
                    .font(.title2)
                    .foregroundStyle(.blue)
                    .frame(width: 36)
                VStack(alignment: .leading, spacing: 2) {
                    Text(info.product)
                        .font(.subheadline)
                        .fontWeight(.medium)
                    Text("v\(info.firmwareVersion) · \(info.hostname)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
            }
            .padding(12)
            .background(.background.opacity(0.6), in: RoundedRectangle(cornerRadius: 12))
        }
    }

    // MARK: - Viewer Controls

    private var viewerControls: some View {
        VStack(alignment: .leading, spacing: 8) {
            sectionHeader("Controls")
            LazyVGrid(columns: tileColumns, spacing: 10) {
                controlTile("Audio", icon: "speaker.wave.2.fill", color: .green) {
                    onAudio()
                }
                controlTile("CRT Filter", icon: "tv", color: .indigo) {
                    onCustomize()
                }
            }
        }
    }

    // MARK: - Control Grid (Toolbox only)

    private var controlGrid: some View {
        VStack(alignment: .leading, spacing: 8) {
            sectionHeader("Controls")
            LazyVGrid(columns: tileColumns, spacing: 10) {
                controlTile("Audio", icon: "speaker.wave.2.fill", color: .green) {
                    onAudio()
                }

                controlTile("CRT Filter", icon: "tv", color: .indigo) {
                    onCustomize()
                }

                if let forwarder = connection.keyboardForwarder {
                    if forwarder.isEnabled {
                        controlTile("Keyboard", icon: "keyboard.fill", color: .blue) {
                            forwarder.isEnabled = false
                        }
                    } else {
                        controlTile("Keyboard", icon: "keyboard", color: .gray) {
                            if UserDefaults.standard.bool(forKey: Self.keyboardInfoShownKey) {
                                forwarder.isEnabled = true
                            } else {
                                showKeyboardInfo = true
                            }
                        }
                    }
                }

                if connection.streamsActive {
                    controlTile("Stop Streams", icon: "stop.circle.fill", color: .red) {
                        connection.stopStreams()
                    }
                } else {
                    controlTile("Start Streams", icon: "play.circle.fill", color: .green) {
                        connection.startStreams()
                    }
                }

                controlTile("Run File", icon: "doc.fill.badge.plus", color: .blue) {
                    let panel = NSOpenPanel()
                    panel.allowedContentTypes = ["sid", "prg", "crt"].compactMap {
                        .init(filenameExtension: $0)
                    }
                    panel.allowsMultipleSelection = false
                    if panel.runModal() == .OK, let url = panel.url,
                       let data = try? Data(contentsOf: url) {
                        let ext = url.pathExtension.lowercased()
                        let type: RunnerType = switch ext {
                        case "sid": .sid
                        case "crt": .crt
                        default: .prg
                        }
                        connection.runFile(type: type, data: data)
                    }
                }

                controlTile("Menu", icon: "line.3.horizontal", color: .purple) {
                    connection.machineAction(.menuButton)
                }

                controlTile("Reset", icon: "arrow.counterclockwise", color: .orange) {
                    showResetConfirm = true
                }

                controlTile("Reboot", icon: "arrow.trianglehead.2.clockwise", color: .orange) {
                    showRebootConfirm = true
                }

                controlTile("Power Off", icon: "power", color: .red) {
                    showPowerOffConfirm = true
                }
            }
        }
    }

    // MARK: - Components

    private func controlTile(_ label: String, icon: String, color: Color, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: 8) {
                Image(systemName: icon)
                    .font(.title2)
                    .foregroundStyle(color)
                Text(label)
                    .font(.caption)
                    .foregroundStyle(.primary)
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
            }
            .frame(maxWidth: .infinity)
            .frame(height: 72)
            .background(.background.opacity(0.6), in: RoundedRectangle(cornerRadius: 12))
        }
        .buttonStyle(.plain)
    }

    private func sectionHeader(_ title: String) -> some View {
        Text(title)
            .font(.subheadline)
            .fontWeight(.medium)
            .foregroundStyle(.secondary)
    }
}
