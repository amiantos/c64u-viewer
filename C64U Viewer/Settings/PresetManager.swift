// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.

import Foundation

enum PresetIdentifier: Hashable, Codable {
    case builtIn(CRTPreset)
    case custom(UUID)
}

struct CustomPreset: Codable, Identifiable {
    let id: UUID
    var name: String
    var settings: CRTSettings
}

private struct PresetStore: Codable {
    var customPresets: [CustomPreset] = []
    var builtInOverrides: [String: CRTSettings] = [:]
    var selectedIdentifier: PresetIdentifier = .builtIn(.clean)
}

final class PresetManager {
    private(set) var customPresets: [CustomPreset] = []
    private(set) var builtInOverrides: [String: CRTSettings] = [:]
    var selectedIdentifier: PresetIdentifier = .builtIn(.clean)

    private var persistWorkItem: DispatchWorkItem?

    init() {
        load()
    }

    // MARK: - Computed Helpers

    func settings(for id: PresetIdentifier) -> CRTSettings {
        switch id {
        case .builtIn(let preset):
            return builtInOverrides[preset.rawValue] ?? preset.settings
        case .custom(let uuid):
            return customPresets.first(where: { $0.id == uuid })?.settings ?? CRTSettings()
        }
    }

    func displayName(for id: PresetIdentifier) -> String {
        switch id {
        case .builtIn(let preset):
            return isModified(preset) ? "\(preset.rawValue) *" : preset.rawValue
        case .custom(let uuid):
            return customPresets.first(where: { $0.id == uuid })?.name ?? "Unknown"
        }
    }

    func isModified(_ preset: CRTPreset) -> Bool {
        builtInOverrides[preset.rawValue] != nil
    }

    var allPresetEntries: [(id: PresetIdentifier, name: String, isModified: Bool)] {
        var entries: [(id: PresetIdentifier, name: String, isModified: Bool)] = []
        for preset in CRTPreset.allCases {
            let modified = isModified(preset)
            entries.append((
                id: .builtIn(preset),
                name: modified ? "\(preset.rawValue) *" : preset.rawValue,
                isModified: modified
            ))
        }
        for custom in customPresets {
            entries.append((id: .custom(custom.id), name: custom.name, isModified: false))
        }
        return entries
    }

    // MARK: - Actions

    func saveOverride(for preset: CRTPreset, settings: CRTSettings) {
        builtInOverrides[preset.rawValue] = settings
        schedulePersist()
    }

    func resetBuiltIn(_ preset: CRTPreset) {
        builtInOverrides.removeValue(forKey: preset.rawValue)
        schedulePersist()
    }

    func saveAsCustom(name: String, settings: CRTSettings) -> UUID {
        let id = UUID()
        let custom = CustomPreset(id: id, name: name, settings: settings)
        customPresets.append(custom)
        schedulePersist()
        return id
    }

    func updateCustom(id: UUID, settings: CRTSettings) {
        guard let index = customPresets.firstIndex(where: { $0.id == id }) else { return }
        customPresets[index].settings = settings
        schedulePersist()
    }

    func renameCustom(id: UUID, name: String) {
        guard let index = customPresets.firstIndex(where: { $0.id == id }) else { return }
        customPresets[index].name = name
        schedulePersist()
    }

    func deleteCustom(id: UUID) {
        customPresets.removeAll(where: { $0.id == id })
        if case .custom(let selectedId) = selectedIdentifier, selectedId == id {
            selectedIdentifier = .builtIn(.clean)
        }
        schedulePersist()
    }

    // MARK: - Persistence

    private static var storeURL: URL {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let dir = appSupport.appendingPathComponent("C64U Viewer", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("presets.json")
    }

    func schedulePersist() {
        persistWorkItem?.cancel()
        let item = DispatchWorkItem { [weak self] in
            self?.persist()
        }
        persistWorkItem = item
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5, execute: item)
    }

    func persist() {
        let store = PresetStore(
            customPresets: customPresets,
            builtInOverrides: builtInOverrides,
            selectedIdentifier: selectedIdentifier
        )
        do {
            let data = try JSONEncoder().encode(store)
            try data.write(to: Self.storeURL, options: .atomic)
        } catch {
            print("Failed to persist presets: \(error)")
        }
    }

    func load() {
        let url = Self.storeURL
        if FileManager.default.fileExists(atPath: url.path) {
            do {
                let data = try Data(contentsOf: url)
                let store = try JSONDecoder().decode(PresetStore.self, from: data)
                customPresets = store.customPresets
                builtInOverrides = store.builtInOverrides
                selectedIdentifier = store.selectedIdentifier
                return
            } catch {
                print("Failed to load presets: \(error)")
            }
        }

        // Migration from old UserDefaults
        if let presetRaw = UserDefaults.standard.string(forKey: "c64_preset"),
           let preset = CRTPreset(rawValue: presetRaw) {
            selectedIdentifier = .builtIn(preset)
        }
    }
}
