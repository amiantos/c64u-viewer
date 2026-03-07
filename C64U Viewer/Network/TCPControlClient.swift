// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.

import Foundation
import Network

final class TCPControlClient: @unchecked Sendable {
    private let queue = DispatchQueue(label: "com.c64uviewer.control-tcp")

    func sendEnableStream(host: String, controlPort: UInt16 = 64, streamId: UInt8, clientIP: String, clientPort: UInt16) {
        // First send stop command to clear any previous state
        sendDisableStream(host: host, controlPort: controlPort, streamId: streamId)

        // Small delay to ensure stop is processed
        queue.asyncAfter(deadline: .now() + .milliseconds(100)) { [weak self] in
            self?.sendEnableCommand(host: host, controlPort: controlPort, streamId: streamId,
                                    clientIP: clientIP, clientPort: clientPort)
        }
    }

    private func sendEnableCommand(host: String, controlPort: UInt16, streamId: UInt8, clientIP: String, clientPort: UInt16) {
        let destString = "\(clientIP):\(clientPort)"
        let destBytes = Array(destString.utf8)

        // Command: [0x20+streamId, 0xFF, paramLen_lo, paramLen_hi, duration_lo, duration_hi, destString...]
        var cmd = [UInt8]()
        cmd.append(0x20 + streamId)
        cmd.append(0xFF)
        let paramLen = UInt16(2 + destBytes.count)
        cmd.append(UInt8(paramLen & 0xFF))
        cmd.append(UInt8(paramLen >> 8))
        cmd.append(0x00) // Duration: 0 = forever
        cmd.append(0x00)
        cmd.append(contentsOf: destBytes)

        sendTCPCommand(host: host, port: controlPort, data: Data(cmd))
    }

    func sendDisableStream(host: String, controlPort: UInt16 = 64, streamId: UInt8) {
        let cmd: [UInt8] = [0x30 + streamId, 0xFF, 0x00, 0x00]
        sendTCPCommand(host: host, port: controlPort, data: Data(cmd))
    }

    private func sendTCPCommand(host: String, port: UInt16, data: Data) {
        let endpoint = NWEndpoint.hostPort(host: NWEndpoint.Host(host), port: NWEndpoint.Port(rawValue: port)!)
        let connection = NWConnection(to: endpoint, using: .tcp)

        connection.stateUpdateHandler = { state in
            switch state {
            case .ready:
                connection.send(content: data, completion: .contentProcessed { error in
                    if let error {
                        print("TCP send error: \(error)")
                    }
                    connection.cancel()
                })
            case .failed(let error):
                print("TCP connection failed: \(error)")
            default:
                break
            }
        }

        connection.start(queue: queue)
    }
}
