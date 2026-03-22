// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.

import SwiftUI

struct HomeView: View {
    @Bindable var connection: C64Connection
    @State private var videoPortText = "11000"
    @State private var audioPortText = "11001"
    @State private var ipAddress = ""
    @State private var password = ""
    @State private var savePassword = false

    var body: some View {
        VStack(spacing: 0) {
            Text("C64 Ultimate Toolbox")
                .font(.largeTitle)
                .fontWeight(.bold)
                .padding(.top, 24)
                .padding(.bottom, 20)

            ScrollView {
                VStack(spacing: 20) {
                    viewerSection
                    Divider().padding(.horizontal)
                    toolboxSection
                }
                .frame(maxWidth: 500)
                .padding(.horizontal, 24)
                .padding(.bottom, 24)
                .frame(maxWidth: .infinity)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(.ultraThinMaterial)
    }

    // MARK: - Viewer Mode

    private var viewerSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("Viewer Mode", systemImage: "tv")
                .font(.headline)

            if let localIP = connection.getLocalIPAddress() {
                Text("Local IP: \(localIP)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            LabeledContent("Video Port") {
                TextField("11000", text: $videoPortText)
                    .textFieldStyle(.roundedBorder)
            }
            LabeledContent("Audio Port") {
                TextField("11001", text: $audioPortText)
                    .textFieldStyle(.roundedBorder)
            }
            HStack {
                Spacer()
                Button("Listen") {
                    let vp = UInt16(videoPortText) ?? 11000
                    let ap = UInt16(audioPortText) ?? 11001
                    connection.listen(videoPort: vp, audioPort: ap)
                }
                .buttonStyle(.borderedProminent)
            }

            if !connection.recentConnections.viewerSessions.isEmpty {
                Text("Recent")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)

                ForEach(connection.recentConnections.viewerSessions) { session in
                    HStack {
                        Text("Ports \(session.videoPort) / \(session.audioPort)")
                            .font(.caption)
                        Spacer()
                        Button("Listen") {
                            connection.listen(videoPort: session.videoPort, audioPort: session.audioPort)
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                    }
                }
            }
        }
        .padding()
        .background(.background.opacity(0.5), in: RoundedRectangle(cornerRadius: 10))
    }

    // MARK: - Toolbox Mode

    private var toolboxSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("Toolbox Mode", systemImage: "wrench.and.screwdriver")
                .font(.headline)

            HStack {
                Text("IP Address")
                    .frame(width: 80, alignment: .trailing)
                TextField("192.168.1.24", text: $ipAddress)
                    .textFieldStyle(.roundedBorder)
            }
            HStack {
                Text("Password")
                    .frame(width: 80, alignment: .trailing)
                SecureField("optional", text: $password)
                    .textFieldStyle(.roundedBorder)
                Toggle("Save Password", isOn: $savePassword)
                    .toggleStyle(.checkbox)
                    .disabled(password.isEmpty)
            }
            if let error = connection.connectionError {
                Label(error, systemImage: "exclamationmark.triangle.fill")
                    .font(.caption)
                    .foregroundStyle(.red)
            }
            HStack {
                Spacer()
                Button("Connect") {
                    connection.connectionError = nil
                    connection.connectToolbox(
                        ip: ipAddress,
                        password: password.isEmpty ? nil : password,
                        savePassword: savePassword
                    )
                }
                .buttonStyle(.borderedProminent)
                .disabled(ipAddress.isEmpty)
            }

            if !connection.recentConnections.toolboxSessions.isEmpty {
                Text("Recent")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)

                ForEach(connection.recentConnections.toolboxSessions) { session in
                    HStack {
                        Text(session.ipAddress)
                            .font(.caption)
                        if session.savePassword {
                            Image(systemName: "lock.fill")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        Button("Connect") {
                            ipAddress = session.ipAddress
                            if let savedPw = session.password {
                                password = savedPw
                            }
                            connection.connectToolbox(
                                ip: session.ipAddress,
                                password: session.password,
                                savePassword: session.savePassword
                            )
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                    }
                }
            }
        }
        .padding()
        .background(.background.opacity(0.5), in: RoundedRectangle(cornerRadius: 10))
    }
}

#Preview {
    HomeView(connection: C64Connection())
        .frame(width: 768, height: 544)
}
