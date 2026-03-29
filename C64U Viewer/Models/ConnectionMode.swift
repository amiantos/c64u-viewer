// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.

import Foundation

enum ConnectionMode {
    case viewer
    case toolbox
}

struct ViewerSession: Codable, Identifiable, Equatable {
    var id: String { "\(videoPort)-\(audioPort)" }
    let videoPort: UInt16
    let audioPort: UInt16
    let date: Date
}

struct ToolboxSession: Codable, Identifiable, Equatable {
    var id: String { ipAddress }
    let ipAddress: String
    let savePassword: Bool
    let password: String?
    let date: Date
}

final class RecentConnections {
    var viewerSessions: [ViewerSession] = []
    var toolboxSessions: [ToolboxSession] = []

    private let viewerKey = "c64_recent_viewer"
    private let toolboxKey = "c64_recent_toolbox"
    private let maxRecent = 5

    init() {
        if let data = UserDefaults.standard.data(forKey: viewerKey),
           let sessions = try? JSONDecoder().decode([ViewerSession].self, from: data) {
            viewerSessions = sessions
        }
        if let data = UserDefaults.standard.data(forKey: toolboxKey),
           let sessions = try? JSONDecoder().decode([ToolboxSession].self, from: data) {
            toolboxSessions = sessions
        }
    }

    func addViewer(videoPort: UInt16, audioPort: UInt16) {
        let session = ViewerSession(videoPort: videoPort, audioPort: audioPort, date: Date())
        viewerSessions.removeAll { $0.id == session.id }
        viewerSessions.insert(session, at: 0)
        if viewerSessions.count > maxRecent { viewerSessions.removeLast() }
        save()
    }

    func addToolbox(ipAddress: String, password: String?, savePassword: Bool) {
        let session = ToolboxSession(
            ipAddress: ipAddress,
            savePassword: savePassword,
            password: savePassword ? password : nil,
            date: Date()
        )
        toolboxSessions.removeAll { $0.id == session.id }
        toolboxSessions.insert(session, at: 0)
        if toolboxSessions.count > maxRecent { toolboxSessions.removeLast() }
        save()
    }

    func removeViewer(_ session: ViewerSession) {
        viewerSessions.removeAll { $0.id == session.id }
        save()
    }

    func removeToolbox(_ session: ToolboxSession) {
        toolboxSessions.removeAll { $0.id == session.id }
        save()
    }

    private func save() {
        if let data = try? JSONEncoder().encode(viewerSessions) {
            UserDefaults.standard.set(data, forKey: viewerKey)
        }
        if let data = try? JSONEncoder().encode(toolboxSessions) {
            UserDefaults.standard.set(data, forKey: toolboxKey)
        }
    }
}
