// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.

import Foundation

struct DeviceInfo: Codable, Sendable {
    let product: String
    let firmwareVersion: String
    let fpgaVersion: String
    let coreVersion: String
    let hostname: String
    let uniqueId: String

    enum CodingKeys: String, CodingKey {
        case product, hostname
        case firmwareVersion = "firmware_version"
        case fpgaVersion = "fpga_version"
        case coreVersion = "core_version"
        case uniqueId = "unique_id"
    }
}

final class C64APIClient: Sendable {
    let baseURL: String
    let password: String?

    init(host: String, password: String? = nil) {
        self.baseURL = "http://\(host)"
        self.password = password?.isEmpty == true ? nil : password
    }

    // MARK: - Device Info

    func fetchInfo() async throws -> DeviceInfo {
        try await get("/v1/info")
    }

    // MARK: - Streams

    func startStream(_ name: String, clientIP: String, port: UInt16) async throws {
        try await put("/v1/streams/\(name):start?ip=\(clientIP):\(port)")
    }

    func stopStream(_ name: String) async throws {
        try await put("/v1/streams/\(name):stop")
    }

    // MARK: - Runners

    func runSID(data: Data) async throws {
        try await post("/v1/runners:sidplay", body: data)
    }

    func runMOD(data: Data) async throws {
        try await post("/v1/runners:modplay", body: data)
    }

    func runPRG(data: Data) async throws {
        try await post("/v1/runners:run_prg", body: data)
    }

    func runCRT(data: Data) async throws {
        try await post("/v1/runners:run_crt", body: data)
    }

    // MARK: - Runners (by device path)

    func runPRGByPath(_ path: String) async throws {
        try await put("/v1/runners:run_prg?file=\(path.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? path)")
    }

    func loadPRGByPath(_ path: String) async throws {
        try await put("/v1/runners:load_prg?file=\(path.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? path)")
    }

    func playSIDByPath(_ path: String) async throws {
        try await put("/v1/runners:sidplay?file=\(path.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? path)")
    }

    func playMODByPath(_ path: String) async throws {
        try await put("/v1/runners:modplay?file=\(path.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? path)")
    }

    func runCRTByPath(_ path: String) async throws {
        try await put("/v1/runners:run_crt?file=\(path.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? path)")
    }

    // MARK: - Drives

    func fetchDrives() async throws -> [String: [String: Any]] {
        let request = makeRequest("/v1/drives", method: "GET")
        let (data, response) = try await URLSession.shared.data(for: request)
        try validateResponse(response)
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let drives = json["drives"] as? [[String: Any]] else {
            return [:]
        }
        // Flatten: [ {"a": {...}}, {"b": {...}} ] → ["a": {...}, "b": {...}]
        var result: [String: [String: Any]] = [:]
        for driveObj in drives {
            for (key, value) in driveObj {
                if let info = value as? [String: Any] {
                    result[key] = info
                }
            }
        }
        return result
    }

    func mountDisk(drive: String, imagePath: String) async throws {
        try await put("/v1/drives/\(drive):mount?image=\(imagePath.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? imagePath)")
    }

    func removeDisk(drive: String) async throws {
        try await put("/v1/drives/\(drive):remove")
    }

    func resetDrive(_ drive: String) async throws {
        try await put("/v1/drives/\(drive):reset")
    }

    // MARK: - Machine Control

    func machineReset() async throws {
        try await put("/v1/machine:reset")
    }

    func machineReboot() async throws {
        try await put("/v1/machine:reboot")
    }

    func machinePowerOff() async throws {
        try await put("/v1/machine:poweroff")
    }

    func menuButton() async throws {
        try await put("/v1/machine:menu_button")
    }

    func machinePause() async throws {
        try await put("/v1/machine:pause")
    }

    func machineResume() async throws {
        try await put("/v1/machine:resume")
    }

    // MARK: - Memory Access

    func readMem(address: Int, length: Int = 1) async throws -> Data {
        let hex = String(format: "%04X", address)
        let request = makeRequest("/v1/machine:readmem?address=\(hex)&length=\(length)", method: "GET")
        let (data, response) = try await URLSession.shared.data(for: request)
        try validateResponse(response)
        return data
    }

    func writeMem(address: Int, data: Data) async throws {
        let hex = String(format: "%04X", address)
        try await post("/v1/machine:writemem?address=\(hex)", body: data)
    }

    // MARK: - HTTP Helpers

    @discardableResult
    private func get<T: Decodable>(_ path: String) async throws -> T {
        let request = makeRequest(path, method: "GET")
        let (data, response) = try await URLSession.shared.data(for: request)
        try validateResponse(response)
        return try JSONDecoder().decode(T.self, from: data)
    }

    @discardableResult
    private func put(_ path: String) async throws -> Data {
        let request = makeRequest(path, method: "PUT")
        let (data, response) = try await URLSession.shared.data(for: request)
        try validateResponse(response)
        return data
    }

    @discardableResult
    private func post(_ path: String, body: Data) async throws -> Data {
        var request = makeRequest(path, method: "POST")
        request.httpBody = body
        request.setValue("application/octet-stream", forHTTPHeaderField: "Content-Type")
        let (data, response) = try await URLSession.shared.data(for: request)
        try validateResponse(response)
        return data
    }

    private func makeRequest(_ path: String, method: String) -> URLRequest {
        var request = URLRequest(url: URL(string: "\(baseURL)\(path)")!)
        request.httpMethod = method
        if let password {
            request.setValue(password, forHTTPHeaderField: "X-Password")
        }
        return request
    }

    private func validateResponse(_ response: URLResponse) throws {
        guard let http = response as? HTTPURLResponse else {
            throw C64APIError.invalidResponse
        }
        guard (200...299).contains(http.statusCode) else {
            throw C64APIError.httpError(http.statusCode)
        }
    }
}

enum C64APIError: LocalizedError {
    case invalidResponse
    case httpError(Int)

    var errorDescription: String? {
        switch self {
        case .invalidResponse:
            "Invalid response from device"
        case .httpError(let code):
            "HTTP error \(code)"
        }
    }
}
