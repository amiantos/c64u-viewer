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

    /// Character set for encoding query parameter values — matches JS encodeURIComponent behavior.
    /// Removes /:&=+ from urlQueryAllowed so forward slashes in file paths get encoded as %2F.
    private static let queryValueAllowed: CharacterSet = {
        var cs = CharacterSet.urlQueryAllowed
        cs.remove(charactersIn: "/:&=+")
        return cs
    }()

    private static func encodeQueryValue(_ value: String) -> String {
        value.addingPercentEncoding(withAllowedCharacters: queryValueAllowed) ?? value
    }

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
        let encoded = Self.encodeQueryValue(path)
        Log.info("runPRGByPath: '\(path)' -> '\(encoded)'")
        try await put("/v1/runners:run_prg?file=\(encoded)")
    }

    func loadPRGByPath(_ path: String) async throws {
        let encoded = Self.encodeQueryValue(path)
        Log.info("loadPRGByPath: '\(path)' -> '\(encoded)'")
        try await put("/v1/runners:load_prg?file=\(encoded)")
    }

    func playSIDByPath(_ path: String) async throws {
        let encoded = Self.encodeQueryValue(path)
        Log.info("playSIDByPath: '\(path)' -> '\(encoded)'")
        try await put("/v1/runners:sidplay?file=\(encoded)")
    }

    func playMODByPath(_ path: String) async throws {
        let encoded = Self.encodeQueryValue(path)
        Log.info("playMODByPath: '\(path)' -> '\(encoded)'")
        try await put("/v1/runners:modplay?file=\(encoded)")
    }

    func runCRTByPath(_ path: String) async throws {
        let encoded = Self.encodeQueryValue(path)
        Log.info("runCRTByPath: '\(path)' -> '\(encoded)'")
        try await put("/v1/runners:run_crt?file=\(encoded)")
    }

    // MARK: - Drives

    func fetchDrives() async throws -> [String: [String: Any]] {
        let request = makeRequest("/v1/drives", method: "GET")
        let (data, response) = try await URLSession.shared.data(for: request)
        try validateResponse(response, data: data)
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
        let encoded = Self.encodeQueryValue(imagePath)
        Log.info("mountDisk: drive=\(drive) path='\(imagePath)' -> '\(encoded)'")
        try await put("/v1/drives/\(drive):mount?image=\(encoded)")
    }

    func removeDisk(drive: String) async throws {
        try await put("/v1/drives/\(drive):remove")
    }

    func resetDrive(_ drive: String) async throws {
        try await put("/v1/drives/\(drive):reset")
    }

    // MARK: - Configuration

    func fetchConfigCategories() async throws -> [String] {
        let request = makeRequest("/v1/configs", method: "GET")
        let (data, response) = try await URLSession.shared.data(for: request)
        try validateResponse(response, data: data)
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let categories = json["categories"] as? [String] else { return [] }
        return categories
    }

    func fetchConfigCategory(_ category: String) async throws -> [String: Any] {
        let encoded = category.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? category
        let request = makeRequest("/v1/configs/\(encoded)", method: "GET")
        let (data, response) = try await URLSession.shared.data(for: request)
        try validateResponse(response, data: data)
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let items = json[category] as? [String: Any] else { return [:] }
        return items
    }

    func setConfigItem(_ category: String, item: String, value: String) async throws {
        let catEncoded = category.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? category
        let itemEncoded = item.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? item
        let valEncoded = Self.encodeQueryValue(value)
        try await put("/v1/configs/\(catEncoded)/\(itemEncoded)?value=\(valEncoded)")
    }

    func fetchConfigItemDetails(_ category: String, item: String) async throws -> [String: Any] {
        let catEncoded = category.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? category
        let itemEncoded = item.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? item
        let request = makeRequest("/v1/configs/\(catEncoded)/\(itemEncoded)", method: "GET")
        let (data, response) = try await URLSession.shared.data(for: request)
        try validateResponse(response, data: data)
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let categoryData = json[category] as? [String: Any],
              let itemData = categoryData[item] as? [String: Any] else { return [:] }
        return itemData
    }

    func saveConfigToFlash() async throws {
        try await put("/v1/configs:save_to_flash")
    }

    func loadConfigFromFlash() async throws {
        try await put("/v1/configs:load_from_flash")
    }

    func resetConfigToDefault() async throws {
        let request = makeRequest("/v1/configs:reset_to_default", method: "PUT")
        let (data, response) = try await URLSession.shared.data(for: request)
        // Device may reboot — treat 502 as success
        if let http = response as? HTTPURLResponse, http.statusCode == 502 {
            return
        }
        try validateResponse(response, data: data)
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
        try validateResponse(response, data: data)
        return data
    }

    func writeMem(address: Int, data: Data) async throws {
        let hex = String(format: "%04X", address)
        try await post("/v1/machine:writemem?address=\(hex)", body: data)
    }

    func writeMemHex(address: Int, dataHex: String) async throws {
        let addrHex = String(format: "%04X", address)
        try await put("/v1/machine:writemem?address=\(addrHex)&data=\(dataHex)")
    }

    // MARK: - HTTP Helpers

    @discardableResult
    private func get<T: Decodable>(_ path: String) async throws -> T {
        let request = makeRequest(path, method: "GET")
        let (data, response) = try await URLSession.shared.data(for: request)
        try validateResponse(response, data: data)
        return try JSONDecoder().decode(T.self, from: data)
    }

    @discardableResult
    private func put(_ path: String) async throws -> Data {
        let request = makeRequest(path, method: "PUT")
        let (data, response) = try await URLSession.shared.data(for: request)
        try validateResponse(response, data: data)
        return data
    }

    @discardableResult
    private func post(_ path: String, body: Data) async throws -> Data {
        var request = makeRequest(path, method: "POST")
        request.httpBody = body
        request.setValue("application/octet-stream", forHTTPHeaderField: "Content-Type")
        let (data, response) = try await URLSession.shared.data(for: request)
        try validateResponse(response, data: data)
        return data
    }

    private func makeRequest(_ path: String, method: String) -> URLRequest {
        let urlString = "\(baseURL)\(path)"
        Log.debug("[\(method)] \(urlString)")
        var request = URLRequest(url: URL(string: urlString)!)
        request.httpMethod = method
        if let password {
            request.setValue(password, forHTTPHeaderField: "X-Password")
        }
        return request
    }

    private func validateResponse(_ response: URLResponse, data: Data? = nil) throws {
        guard let http = response as? HTTPURLResponse else {
            Log.error("Invalid response (not HTTP)")
            throw C64APIError.invalidResponse
        }
        guard (200...299).contains(http.statusCode) else {
            let body = data.flatMap { String(data: $0, encoding: .utf8) } ?? ""
            Log.error("HTTP \(http.statusCode): \(http.url?.absoluteString ?? "?") — \(body)")
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
