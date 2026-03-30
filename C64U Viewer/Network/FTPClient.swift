// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.

import Foundation
import Network

// MARK: - FTP File Entry

struct FTPFileEntry {
    let name: String
    let path: String
    let size: UInt64
    let isDirectory: Bool
    let modificationDate: Date?
}

// MARK: - FTP Client

actor FTPClient {
    private let host: String
    private let port: UInt16
    private var controlConnection: NWConnection?
    private let queue = DispatchQueue(label: "com.c64uviewer.ftp")

    enum FTPError: LocalizedError {
        case notConnected
        case connectionFailed(String)
        case commandFailed(Int, String)
        case parseError(String)
        case transferFailed(String)

        var errorDescription: String? {
            switch self {
            case .notConnected: return "Not connected to FTP server"
            case .connectionFailed(let msg): return "FTP connection failed: \(msg)"
            case .commandFailed(let code, let msg): return "FTP error \(code): \(msg)"
            case .parseError(let msg): return "FTP parse error: \(msg)"
            case .transferFailed(let msg): return "FTP transfer failed: \(msg)"
            }
        }
    }

    init(host: String, port: UInt16 = 21) {
        self.host = host
        self.port = port
    }

    // MARK: - Connection

    func connect() async throws {
        let connection = NWConnection(
            host: NWEndpoint.Host(host),
            port: NWEndpoint.Port(rawValue: port)!,
            using: .tcp
        )

        controlConnection = connection

        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            connection.stateUpdateHandler = { state in
                switch state {
                case .ready:
                    connection.stateUpdateHandler = nil
                    continuation.resume()
                case .failed(let error):
                    connection.stateUpdateHandler = nil
                    continuation.resume(throwing: FTPError.connectionFailed(error.localizedDescription))
                default:
                    break
                }
            }
            connection.start(queue: queue)
        }

        // Read server greeting
        let greeting = try await readResponse()
        guard greeting.code == 220 else {
            throw FTPError.commandFailed(greeting.code, greeting.message)
        }

        // Anonymous login
        let userResp = try await sendCommand("USER anonymous")
        if userResp.code == 331 {
            let passResp = try await sendCommand("PASS anonymous@")
            guard passResp.code == 230 else {
                throw FTPError.commandFailed(passResp.code, passResp.message)
            }
        }

        // Set binary mode
        let _ = try await sendCommand("TYPE I")
    }

    func disconnect() {
        controlConnection?.cancel()
        controlConnection = nil
    }

    // MARK: - Directory Operations

    func listDirectory(_ path: String) async throws -> [FTPFileEntry] {
        let (dataHost, dataPort) = try await enterPassiveMode()
        let _ = try await sendCommand("CWD \(path)")
        let pwdResp = try await sendCommand("PWD")
        let currentPath = parsePWDResponse(pwdResp.message)

        // Open data connection
        let dataConnection = NWConnection(
            host: NWEndpoint.Host(dataHost),
            port: NWEndpoint.Port(rawValue: dataPort)!,
            using: .tcp
        )

        let rawData = try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Data, Error>) in
            dataConnection.stateUpdateHandler = { state in
                if case .failed(let error) = state {
                    dataConnection.stateUpdateHandler = nil
                    continuation.resume(throwing: FTPError.transferFailed(error.localizedDescription))
                }
            }
            dataConnection.start(queue: self.queue)

            // Send LIST command on control connection after data connection is ready
            Task {
                do {
                    let listResp = try await self.sendCommand("LIST")
                    guard listResp.code == 150 || listResp.code == 125 else {
                        continuation.resume(throwing: FTPError.commandFailed(listResp.code, listResp.message))
                        return
                    }

                    // Read all data
                    let data = try await self.readAllData(from: dataConnection)
                    dataConnection.cancel()

                    // Read transfer complete response
                    let _ = try await self.readResponse()
                    continuation.resume(returning: data)
                } catch {
                    dataConnection.cancel()
                    continuation.resume(throwing: error)
                }
            }
        }

        let listing = String(data: rawData, encoding: .utf8) ?? ""
        return parseListResponse(listing, parentPath: currentPath)
    }

    func createDirectory(_ path: String) async throws {
        let resp = try await sendCommand("MKD \(path)")
        guard resp.code == 257 else {
            throw FTPError.commandFailed(resp.code, resp.message)
        }
    }

    func deleteFile(_ path: String) async throws {
        let resp = try await sendCommand("DELE \(path)")
        guard resp.code == 250 else {
            throw FTPError.commandFailed(resp.code, resp.message)
        }
    }

    func deleteDirectory(_ path: String) async throws {
        let resp = try await sendCommand("RMD \(path)")
        guard resp.code == 250 else {
            throw FTPError.commandFailed(resp.code, resp.message)
        }
    }

    func rename(from: String, to: String) async throws {
        let rnfrResp = try await sendCommand("RNFR \(from)")
        guard rnfrResp.code == 350 else {
            throw FTPError.commandFailed(rnfrResp.code, rnfrResp.message)
        }
        let rntoResp = try await sendCommand("RNTO \(to)")
        guard rntoResp.code == 250 else {
            throw FTPError.commandFailed(rntoResp.code, rntoResp.message)
        }
    }

    // MARK: - File Transfer

    func uploadFile(localURL: URL, remotePath: String, progress: ((Int64, Int64) -> Void)? = nil) async throws {
        let fileData = try Data(contentsOf: localURL)
        let totalBytes = Int64(fileData.count)

        let (dataHost, dataPort) = try await enterPassiveMode()

        let dataConnection = NWConnection(
            host: NWEndpoint.Host(dataHost),
            port: NWEndpoint.Port(rawValue: dataPort)!,
            using: .tcp
        )

        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            dataConnection.stateUpdateHandler = { state in
                if case .failed(let error) = state {
                    dataConnection.stateUpdateHandler = nil
                    continuation.resume(throwing: FTPError.transferFailed(error.localizedDescription))
                }
            }
            dataConnection.start(queue: self.queue)

            Task {
                do {
                    let storResp = try await self.sendCommand("STOR \(remotePath)")
                    guard storResp.code == 150 || storResp.code == 125 else {
                        dataConnection.cancel()
                        continuation.resume(throwing: FTPError.commandFailed(storResp.code, storResp.message))
                        return
                    }

                    // Send data in chunks
                    let chunkSize = 65536
                    var offset = 0
                    while offset < fileData.count {
                        let end = min(offset + chunkSize, fileData.count)
                        let chunk = fileData[offset..<end]

                        try await withCheckedThrowingContinuation { (sendCont: CheckedContinuation<Void, Error>) in
                            dataConnection.send(content: chunk, completion: .contentProcessed { error in
                                if let error {
                                    sendCont.resume(throwing: error)
                                } else {
                                    sendCont.resume()
                                }
                            })
                        }

                        offset = end
                        progress?(Int64(offset), totalBytes)
                    }

                    // Close data connection to signal transfer complete
                    dataConnection.send(content: nil, contentContext: .finalMessage, isComplete: true, completion: .contentProcessed { _ in })
                    dataConnection.cancel()

                    let _ = try await self.readResponse()
                    continuation.resume()
                } catch {
                    dataConnection.cancel()
                    continuation.resume(throwing: error)
                }
            }
        }
    }

    func downloadFile(remotePath: String, localURL: URL, progress: ((Int64, Int64) -> Void)? = nil) async throws {
        // Get file size first
        let sizeResp = try await sendCommand("SIZE \(remotePath)")
        let totalBytes = Int64(sizeResp.message.trimmingCharacters(in: .whitespaces)) ?? 0

        let (dataHost, dataPort) = try await enterPassiveMode()

        let dataConnection = NWConnection(
            host: NWEndpoint.Host(dataHost),
            port: NWEndpoint.Port(rawValue: dataPort)!,
            using: .tcp
        )

        let fileData = try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Data, Error>) in
            dataConnection.stateUpdateHandler = { state in
                if case .failed(let error) = state {
                    dataConnection.stateUpdateHandler = nil
                    continuation.resume(throwing: FTPError.transferFailed(error.localizedDescription))
                }
            }
            dataConnection.start(queue: self.queue)

            Task {
                do {
                    let retrResp = try await self.sendCommand("RETR \(remotePath)")
                    guard retrResp.code == 150 || retrResp.code == 125 else {
                        dataConnection.cancel()
                        continuation.resume(throwing: FTPError.commandFailed(retrResp.code, retrResp.message))
                        return
                    }

                    let data = try await self.readAllData(from: dataConnection, progress: { bytesRead in
                        progress?(bytesRead, totalBytes)
                    })
                    dataConnection.cancel()

                    let _ = try await self.readResponse()
                    continuation.resume(returning: data)
                } catch {
                    dataConnection.cancel()
                    continuation.resume(throwing: error)
                }
            }
        }

        try fileData.write(to: localURL)
    }

    // MARK: - Recursive Upload

    func uploadDirectory(localURL: URL, remotePath: String, progress: ((Int, Int, String) -> Void)? = nil) async throws {
        let fileManager = FileManager.default
        let enumerator = fileManager.enumerator(at: localURL, includingPropertiesForKeys: [.isDirectoryKey])

        // Collect all items first for progress tracking
        var items: [(url: URL, relativePath: String, isDirectory: Bool)] = []
        while let url = enumerator?.nextObject() as? URL {
            let resourceValues = try url.resourceValues(forKeys: [.isDirectoryKey])
            let isDir = resourceValues.isDirectory ?? false
            let relativePath = url.path.replacingOccurrences(of: localURL.path, with: "")
            items.append((url, relativePath, isDir))
        }

        // Create the root remote directory
        try? await createDirectory(remotePath)

        let totalItems = items.count
        for (index, item) in items.enumerated() {
            let fullRemotePath = remotePath + item.relativePath
            progress?(index + 1, totalItems, item.url.lastPathComponent)

            if item.isDirectory {
                try? await createDirectory(fullRemotePath)
            } else {
                try await uploadFile(localURL: item.url, remotePath: fullRemotePath)
            }
        }
    }

    // MARK: - Protocol Helpers

    private struct FTPResponse {
        let code: Int
        let message: String
    }

    private func sendCommand(_ command: String) async throws -> FTPResponse {
        guard let connection = controlConnection else {
            throw FTPError.notConnected
        }

        let data = Data((command + "\r\n").utf8)
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            connection.send(content: data, completion: .contentProcessed { error in
                if let error {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume()
                }
            })
        }

        return try await readResponse()
    }

    private func readResponse() async throws -> FTPResponse {
        guard let connection = controlConnection else {
            throw FTPError.notConnected
        }

        let data = try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Data, Error>) in
            connection.receive(minimumIncompleteLength: 1, maximumLength: 4096) { content, _, _, error in
                if let error {
                    continuation.resume(throwing: error)
                } else if let content {
                    continuation.resume(returning: content)
                } else {
                    continuation.resume(throwing: FTPError.connectionFailed("Connection closed"))
                }
            }
        }

        let responseString = String(data: data, encoding: .utf8) ?? ""
        // Parse FTP response: "NNN message\r\n"
        // Handle multi-line responses
        let lines = responseString.components(separatedBy: "\r\n").filter { !$0.isEmpty }
        guard let lastLine = lines.last, lastLine.count >= 3,
              let code = Int(lastLine.prefix(3)) else {
            throw FTPError.parseError("Invalid FTP response: \(responseString)")
        }

        let message = String(lastLine.dropFirst(4))
        return FTPResponse(code: code, message: message)
    }

    private func enterPassiveMode() async throws -> (String, UInt16) {
        let resp = try await sendCommand("PASV")
        guard resp.code == 227 else {
            throw FTPError.commandFailed(resp.code, resp.message)
        }

        // Parse "227 Entering Passive Mode (h1,h2,h3,h4,p1,p2)"
        guard let parenStart = resp.message.firstIndex(of: "("),
              let parenEnd = resp.message.firstIndex(of: ")") else {
            throw FTPError.parseError("Cannot parse PASV response: \(resp.message)")
        }

        let numbers = resp.message[resp.message.index(after: parenStart)..<parenEnd]
            .split(separator: ",")
            .compactMap { UInt16($0) }

        guard numbers.count == 6 else {
            throw FTPError.parseError("Cannot parse PASV numbers: \(resp.message)")
        }

        // Use the original host instead of the PASV-reported IP
        // (C64U may report an internal IP that's not reachable)
        let port = numbers[4] * 256 + numbers[5]
        return (host, port)
    }

    private func readAllData(from connection: NWConnection, progress: ((Int64) -> Void)? = nil) async throws -> Data {
        var buffer = Data()

        while true {
            do {
                let chunk = try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Data?, Error>) in
                    connection.receive(minimumIncompleteLength: 1, maximumLength: 65536) { content, _, isComplete, error in
                        if let error {
                            continuation.resume(throwing: error)
                        } else if let content, !content.isEmpty {
                            continuation.resume(returning: content)
                        } else if isComplete {
                            continuation.resume(returning: nil)
                        } else {
                            continuation.resume(returning: nil)
                        }
                    }
                }

                guard let chunk else { break }
                buffer.append(chunk)
                progress?(Int64(buffer.count))
            } catch {
                // Connection closed = transfer complete
                break
            }
        }

        return buffer
    }

    // MARK: - LIST Response Parsing

    private func parseListResponse(_ listing: String, parentPath: String) -> [FTPFileEntry] {
        var entries: [FTPFileEntry] = []
        let lines = listing.components(separatedBy: "\r\n").filter { !$0.isEmpty }

        for line in lines {
            guard let entry = parseListLine(line, parentPath: parentPath) else { continue }
            // Skip . and .. entries
            if entry.name == "." || entry.name == ".." { continue }
            entries.append(entry)
        }

        return entries.sorted { a, b in
            if a.isDirectory != b.isDirectory { return a.isDirectory }
            return a.name.localizedCaseInsensitiveCompare(b.name) == .orderedAscending
        }
    }

    private func parseListLine(_ line: String, parentPath: String) -> FTPFileEntry? {
        // Unix-style: drwxr-xr-x 2 owner group 4096 Jan 01 12:00 filename
        // Minimum: permissions, links, owner, group, size, month, day, time/year, name
        let components = line.split(separator: " ", maxSplits: 8, omittingEmptySubsequences: true)
        guard components.count >= 9 else { return nil }

        let permissions = String(components[0])
        let isDirectory = permissions.hasPrefix("d")
        let size = UInt64(components[4]) ?? 0
        let name = String(components[8])
        let path = parentPath.hasSuffix("/") ? parentPath + name : parentPath + "/" + name

        return FTPFileEntry(
            name: name,
            path: path,
            size: size,
            isDirectory: isDirectory,
            modificationDate: nil
        )
    }

    private func parsePWDResponse(_ message: String) -> String {
        // Parse "257 "/path" is current directory"
        guard let firstQuote = message.firstIndex(of: "\""),
              let lastQuote = message[message.index(after: firstQuote)...].firstIndex(of: "\"") else {
            return "/"
        }
        return String(message[message.index(after: firstQuote)..<lastQuote])
    }
}
