// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.

import SwiftUI

struct CRTSettingsOverlayView: View {
    @Bindable var connection: C64Connection
    let onDismiss: () -> Void

    @State private var showingSaveAs = false
    @State private var newPresetName = ""

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                // Header
                HStack {
                    Spacer()

                    Text("CRT Settings")
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

                Form {
                    presetSection
                    scanlineSection
                    bloomBlurSection
                    tintSection
                    phosphorMaskSection
                    screenShapeSection
                    afterglowSection
                }
                .formStyle(.grouped)
            }
            .padding(20)
        }
        .frame(width: 460)
        .frame(maxHeight: 600)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16))
        .shadow(radius: 20)
        .alert("Save As New Preset", isPresented: $showingSaveAs) {
            TextField("Preset Name", text: $newPresetName)
            Button("Save") {
                guard !newPresetName.isEmpty else { return }
                let id = connection.presetManager.saveAsCustom(
                    name: newPresetName,
                    settings: connection.crtSettings
                )
                connection.presetManager.selectedIdentifier = .custom(id)
                newPresetName = ""
            }
            Button("Cancel", role: .cancel) { newPresetName = "" }
        }
    }

    private var presetSection: some View {
        Section {
            HStack {
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

                Button("Save As...") {
                    showingSaveAs = true
                }

                if case .builtIn(let preset) = connection.presetManager.selectedIdentifier,
                   connection.presetManager.isModified(preset) {
                    Button("Reset") {
                        connection.presetManager.resetBuiltIn(preset)
                        connection.selectPreset(.builtIn(preset))
                    }
                }

                if case .custom(let id) = connection.presetManager.selectedIdentifier {
                    Button("Delete", role: .destructive) {
                        connection.presetManager.deleteCustom(id: id)
                        connection.crtSettings = connection.presetManager.settings(
                            for: connection.presetManager.selectedIdentifier
                        )
                    }
                }
            }
        }
    }

    private var scanlineSection: some View {
        Section("Scanlines") {
            SliderRow(label: "Intensity", value: settingsBinding(\.scanlineIntensity), range: 0...1)
            SliderRow(label: "Width", value: settingsBinding(\.scanlineWidth), range: 0...1)
        }
    }

    private var bloomBlurSection: some View {
        Section("Bloom & Blur") {
            SliderRow(label: "Blur Radius", value: settingsBinding(\.blurRadius), range: 0...1)
            SliderRow(label: "Bloom Intensity", value: settingsBinding(\.bloomIntensity), range: 0...1)
            SliderRow(label: "Bloom Radius", value: settingsBinding(\.bloomRadius), range: 0...1)
        }
    }

    private var tintSection: some View {
        Section("Tint") {
            Picker("Tint Mode", selection: settingsBinding(\.tintMode)) {
                Text("None").tag(0)
                Text("Amber").tag(1)
                Text("Green").tag(2)
                Text("Monochrome").tag(3)
            }
            SliderRow(label: "Tint Strength", value: settingsBinding(\.tintStrength), range: 0...1)
        }
    }

    private var phosphorMaskSection: some View {
        Section("Phosphor Mask") {
            Picker("Mask Type", selection: settingsBinding(\.maskType)) {
                Text("None").tag(0)
                Text("Aperture Grille").tag(1)
                Text("Shadow Mask").tag(2)
                Text("Slot Mask").tag(3)
            }
            SliderRow(label: "Mask Intensity", value: settingsBinding(\.maskIntensity), range: 0...1)
        }
    }

    private var screenShapeSection: some View {
        Section("Screen Shape") {
            SliderRow(label: "Curvature", value: settingsBinding(\.curvatureAmount), range: 0...1)
            SliderRow(label: "Vignette", value: settingsBinding(\.vignetteStrength), range: 0...1)
        }
    }

    private var afterglowSection: some View {
        Section("Afterglow") {
            SliderRow(label: "Strength", value: settingsBinding(\.afterglowStrength), range: 0...1)
            SliderRow(label: "Decay Speed", value: settingsBinding(\.afterglowDecaySpeed), range: 1...15)
        }
    }

    private func settingsBinding<T>(_ keyPath: WritableKeyPath<CRTSettings, T>) -> Binding<T> {
        Binding(
            get: { connection.crtSettings[keyPath: keyPath] },
            set: {
                connection.crtSettings[keyPath: keyPath] = $0
                connection.applySettingsChange()
            }
        )
    }
}
