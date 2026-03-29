// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.

import SwiftUI
internal import UniformTypeIdentifiers

struct BASICScratchpadPanelView: View {
    @Bindable var connection: C64Connection

    @State private var errorMessage: String?
    @State private var isUploading = false
    @State private var showSpecialCodes = false

    var body: some View {
        VStack(spacing: 0) {
            header
                .padding(.horizontal, 12)
                .padding(.top, 12)
                .padding(.bottom, 8)

            BASICEditorView(text: $connection.basicScratchpadCode)
                .padding(.horizontal, 12)

            if showSpecialCodes {
                specialCodesReference
                    .padding(.horizontal, 12)
                    .padding(.top, 6)
            }

            statusBar
                .padding(.horizontal, 12)
                .padding(.top, 6)

            toolbar
                .padding(12)
        }
        .background(Color(nsColor: .controlBackgroundColor))
    }

    // MARK: - Header

    private var header: some View {
        HStack {
            Text("BASIC Scratchpad")
                .font(.headline)
            Spacer()
            Button {
                connection.activeToolPanel = nil
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
        }
    }

    // MARK: - Status Bar

    @ViewBuilder
    private var statusBar: some View {
        HStack {
            if let error = errorMessage {
                Label(error, systemImage: "exclamationmark.triangle.fill")
                    .font(.caption)
                    .foregroundStyle(.red)
            } else {
                let lineCount = connection.basicScratchpadCode
                    .split(separator: "\n", omittingEmptySubsequences: true).count
                Text("\(lineCount) line\(lineCount == 1 ? "" : "s")")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
        }
    }

    // MARK: - Toolbar

    private var toolbar: some View {
        HStack(spacing: 8) {
            Button {
                showSpecialCodes.toggle()
            } label: {
                Label(showSpecialCodes ? "Hide Codes" : "Codes",
                      systemImage: "character.bubble")
            }
            .buttonStyle(.bordered)
            .controlSize(.small)

            Menu {
                Menu("Samples") {
                    ForEach(BASICSamples.all, id: \.name) { sample in
                        Button(sample.name) {
                            connection.basicScratchpadCode = sample.code
                            errorMessage = nil
                        }
                    }
                }
                Divider()
                Button("Open...") { openFile() }
                Button("Save As...") { saveFile() }
            } label: {
                Label("File", systemImage: "doc")
            }
            .buttonStyle(.bordered)
            .controlSize(.small)

            Spacer()

            Button {
                uploadProgram()
            } label: {
                if isUploading {
                    ProgressView().controlSize(.small)
                } else {
                    Label("Run", systemImage: "play.fill")
                }
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.small)
            .disabled(connection.basicScratchpadCode.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isUploading)
        }
    }

    // MARK: - Special Codes Reference

    private var specialCodesReference: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Special Codes")
                .font(.caption2)
                .fontWeight(.medium)
                .foregroundStyle(.secondary)

            let columns = Array(repeating: GridItem(.flexible(), spacing: 2), count: 3)
            LazyVGrid(columns: columns, spacing: 1) {
                ForEach(BASICTokenizer.specialCodes, id: \.1) { code, _ in
                    Text(code)
                        .font(.system(size: 9, design: .monospaced))
                        .foregroundStyle(.pink)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }
        .padding(8)
        .background(.black.opacity(0.2), in: RoundedRectangle(cornerRadius: 6))
        .frame(maxHeight: 100)
    }

    // MARK: - Actions

    private func uploadProgram() {
        guard let client = connection.apiClient else { return }
        let code = connection.basicScratchpadCode

        errorMessage = nil
        isUploading = true

        Task {
            do {
                let (data, endAddr) = try BASICTokenizer.tokenize(program: code)
                try await client.writeMem(address: 0x0801, data: data)

                let ptrData = Data([UInt8(endAddr & 0xFF), UInt8(endAddr >> 8)])
                try await client.writeMem(address: 0x002D, data: ptrData)

                // Auto-run
                let runBytes: [UInt8] = [0x52, 0x55, 0x4E, 0x0D]
                try await client.writeMem(address: 0x0277, data: Data(runBytes))
                try await client.writeMem(address: 0x00C6, data: Data([UInt8(runBytes.count)]))

                errorMessage = nil
            } catch {
                errorMessage = error.localizedDescription
            }
            isUploading = false
        }
    }

    private func openFile() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [
            UTType(filenameExtension: "bas"),
            UTType.plainText,
        ].compactMap { $0 }
        panel.allowsMultipleSelection = false
        if panel.runModal() == .OK, let url = panel.url,
           let content = try? String(contentsOf: url, encoding: .utf8) {
            connection.basicScratchpadCode = content
            errorMessage = nil
        }
    }

    private func saveFile() {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [UTType(filenameExtension: "bas") ?? .plainText]
        panel.nameFieldStringValue = "program.bas"
        if panel.runModal() == .OK, let url = panel.url {
            try? connection.basicScratchpadCode.write(to: url, atomically: true, encoding: .utf8)
        }
    }
}
