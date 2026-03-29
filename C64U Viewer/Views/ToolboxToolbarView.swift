// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.

import SwiftUI
internal import UniformTypeIdentifiers

struct ToolboxToolbarView: View {
    @Bindable var connection: C64Connection
    let onShowCRTSettings: () -> Void
    let onShowAudioSettings: () -> Void

    @State private var showResetConfirm = false
    @State private var showRebootConfirm = false
    @State private var showPowerOffConfirm = false
    @State private var showKeyboardInfo = false

    private static let keyboardInfoShownKey = "c64_keyboard_info_shown"

    var body: some View {
        HStack(spacing: 6) {
            // Machine controls
            HStack(spacing: 2) {
                toolbarButton("Reset", icon: "arrow.counterclockwise") {
                    showResetConfirm = true
                }
                toolbarButton("Reboot", icon: "arrow.trianglehead.2.clockwise") {
                    showRebootConfirm = true
                }
                toolbarButton("Power Off", icon: "power") {
                    showPowerOffConfirm = true
                }
                toolbarButton("Menu", icon: "line.3.horizontal") {
                    connection.machineAction(.menuButton)
                }
            }

            toolbarDivider

            // Stream & file controls
            HStack(spacing: 2) {
                if connection.streamsActive {
                    toolbarButton("Stop Streams", icon: "stop.circle.fill", active: true) {
                        connection.stopStreams()
                    }
                } else {
                    toolbarButton("Start Streams", icon: "play.circle.fill") {
                        connection.startStreams()
                    }
                }

                toolbarButton("Run File", icon: "doc.fill.badge.plus") {
                    runFile()
                }

                if let forwarder = connection.keyboardForwarder {
                    toolbarButton(
                        "Keyboard",
                        icon: forwarder.isEnabled ? "keyboard.fill" : "keyboard",
                        active: forwarder.isEnabled
                    ) {
                        if forwarder.isEnabled {
                            forwarder.isEnabled = false
                        } else if UserDefaults.standard.bool(forKey: Self.keyboardInfoShownKey) {
                            forwarder.isEnabled = true
                        } else {
                            showKeyboardInfo = true
                        }
                    }
                }
            }

            toolbarDivider

            // Settings
            HStack(spacing: 2) {
                toolbarButton("CRT", icon: "tv") { onShowCRTSettings() }
                toolbarButton("Audio", icon: "speaker.wave.2.fill") { onShowAudioSettings() }
            }

            Spacer()

            // Status indicators
            statusArea

            // Tools menu
            toolsMenu
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .background(.ultraThinMaterial)
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

    // MARK: - Status

    @ViewBuilder
    private var statusArea: some View {
        if connection.isWaitingForReboot {
            HStack(spacing: 4) {
                ProgressView().controlSize(.small)
                Text("Restarting...")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        } else if let error = connection.connectionError {
            Text(error)
                .font(.caption)
                .foregroundStyle(.red)
                .lineLimit(1)
        }
    }

    // MARK: - Tools Menu

    private var toolsMenu: some View {
        Menu {
            ForEach(ToolPanelType.allCases) { tool in
                Button {
                    if connection.activeToolPanel == tool {
                        connection.activeToolPanel = nil
                    } else {
                        connection.activeToolPanel = tool
                    }
                } label: {
                    if connection.activeToolPanel == tool {
                        Label(tool.label, systemImage: "checkmark")
                    } else {
                        Text(tool.label)
                    }
                }
            }

            if connection.activeToolPanel != nil {
                Divider()
                Button("Close Panel") {
                    connection.activeToolPanel = nil
                }
            }
        } label: {
            Label("Tools", systemImage: "wrench.and.screwdriver")
                .font(.caption)
                .fontWeight(.medium)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(
                    connection.activeToolPanel != nil
                        ? Color.accentColor.opacity(0.2)
                        : Color.white.opacity(0.1),
                    in: RoundedRectangle(cornerRadius: 6)
                )
        }
        .menuStyle(.borderlessButton)
        .fixedSize()
    }

    // MARK: - Helpers

    private var toolbarDivider: some View {
        Divider().frame(height: 18)
    }

    private func toolbarButton(_ label: String, icon: String, active: Bool = false, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 12))
                .frame(width: 26, height: 26)
                .foregroundStyle(active ? Color.accentColor : .primary)
                .background(active ? Color.accentColor.opacity(0.15) : Color.clear, in: RoundedRectangle(cornerRadius: 5))
        }
        .buttonStyle(.plain)
        .help(label)
    }

    private func runFile() {
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
}
