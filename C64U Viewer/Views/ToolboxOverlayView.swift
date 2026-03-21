// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.

import SwiftUI
internal import UniformTypeIdentifiers

struct ToolboxOverlayView: View {
    @Bindable var connection: C64Connection
    let onDismiss: () -> Void

    @State private var showResetConfirm = false
    @State private var showRebootConfirm = false
    @State private var showPowerOffConfirm = false

    var body: some View {
        ZStack {
            // Dismiss background
            Color.black.opacity(0.4)
                .onTapGesture { onDismiss() }

            VStack(spacing: 16) {
                // Header
                HStack {
                    Text("Toolbox")
                        .font(.headline)
                    Spacer()
                    Button { onDismiss() } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.title2)
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                }

                Divider()

                // Device Info
                if let info = connection.deviceInfo {
                    deviceInfoSection(info)
                    Divider()
                }

                if connection.isWaitingForReboot {
                    HStack(spacing: 6) {
                        ProgressView()
                            .controlSize(.small)
                        Text("Waiting for device to restart...")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                } else if let error = connection.connectionError {
                    Label(error, systemImage: "exclamationmark.triangle")
                        .font(.caption)
                        .foregroundStyle(.red)
                }

                // Audio Controls
                audioSection
                Divider()

                // CRT Preset
                presetSection
                Divider()

                // Machine Controls
                machineControlsSection
            }
            .padding(20)
            .frame(width: 380)
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12))
            .shadow(radius: 20)
        }
        .onKeyPress(.escape) {
            onDismiss()
            return .handled
        }
        .confirmationDialog("Reset Machine?", isPresented: $showResetConfirm) {
            Button("Reset", role: .destructive) { connection.machineAction(.reset) }
        }
        .confirmationDialog("Reboot Machine?", isPresented: $showRebootConfirm) {
            Button("Reboot", role: .destructive) { connection.machineAction(.reboot) }
        }
        .confirmationDialog("Power Off Machine?", isPresented: $showPowerOffConfirm) {
            Button("Power Off", role: .destructive) { connection.machineAction(.powerOff) }
        }
    }

    private func deviceInfoSection(_ info: DeviceInfo) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Device Info")
                .font(.subheadline)
                .foregroundStyle(.secondary)
            LabeledContent("Product", value: info.product)
            LabeledContent("Firmware", value: info.firmwareVersion)
            LabeledContent("Hostname", value: info.hostname)
        }
        .font(.caption)
    }

    private var audioSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Audio")
                .font(.subheadline)
                .foregroundStyle(.secondary)
            SliderRow(label: "Volume", value: Binding(
                get: { connection.volume },
                set: {
                    connection.volume = $0
                    connection.isMuted = false
                }
            ), range: 0...1)
            SliderRow(label: "Balance", value: $connection.balance, range: -1...1)
        }
    }

    private var presetSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("CRT Preset")
                .font(.subheadline)
                .foregroundStyle(.secondary)
            Picker("Preset", selection: Binding(
                get: { connection.presetManager.selectedIdentifier },
                set: { connection.selectPreset($0) }
            )) {
                ForEach(CRTPreset.allCases) { preset in
                    let modified = connection.presetManager.isModified(preset)
                    Text(modified ? "\(preset.rawValue) *" : preset.rawValue)
                        .tag(PresetIdentifier.builtIn(preset))
                }
                if !connection.presetManager.customPresets.isEmpty {
                    Divider()
                    ForEach(connection.presetManager.customPresets) { custom in
                        Text(custom.name)
                            .tag(PresetIdentifier.custom(custom.id))
                    }
                }
            }
            .labelsHidden()
        }
    }

    private var machineControlsSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Machine Control")
                .font(.subheadline)
                .foregroundStyle(.secondary)

            HStack(spacing: 8) {
                if connection.streamsActive {
                    Button("Stop Streams") {
                        connection.stopStreams()
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .tint(.red)
                } else {
                    Button("Start Streams") {
                        connection.startStreams()
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                }

                Button("Run File...") {
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
                .buttonStyle(.bordered)
                .controlSize(.small)

                Button("Menu") {
                    connection.machineAction(.menuButton)
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }

            HStack(spacing: 8) {
                Button("Reset") {
                    showResetConfirm = true
                }
                .buttonStyle(.bordered)
                .controlSize(.small)

                Button("Reboot") {
                    showRebootConfirm = true
                }
                .buttonStyle(.bordered)
                .controlSize(.small)

                Button("Power Off") {
                    showPowerOffConfirm = true
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .tint(.red)
            }

            Text("Run File accepts .sid, .prg, and .crt files")
                .font(.caption2)
                .foregroundStyle(.tertiary)
        }
    }
}
