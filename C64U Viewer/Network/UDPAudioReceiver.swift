// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.

import Foundation
import Network

final class UDPAudioReceiver: @unchecked Sendable {
    static let audioPacketSize = 770
    static let audioHeaderSize = 2
    static let samplesPerPacket = 192 // stereo samples (each = 2 channels × 2 bytes = 4 bytes)

    private var listener: NWListener?
    private var activeConnection: NWConnection?
    private let queue = DispatchQueue(label: "com.c64uviewer.audio-udp", qos: .userInteractive)

    var onAudioData: ((_ pcmData: Data, _ sequenceNum: UInt16) -> Void)?
    private(set) var packetsReceived: UInt64 = 0

    func start(port: UInt16) {
        stop()

        let params = NWParameters.udp
        params.allowLocalEndpointReuse = true
        params.requiredLocalEndpoint = NWEndpoint.hostPort(host: .ipv4(.any), port: NWEndpoint.Port(rawValue: port)!)

        do {
            listener = try NWListener(using: params)
        } catch {
            print("Failed to create UDP audio listener: \(error)")
            return
        }

        listener?.newConnectionHandler = { [weak self] connection in
            self?.handleConnection(connection)
        }

        listener?.stateUpdateHandler = { state in
            switch state {
            case .ready:
                print("Audio UDP listener ready on port \(port)")
            case .failed(let error):
                print("Audio UDP listener failed: \(error)")
            default:
                break
            }
        }

        listener?.start(queue: queue)
    }

    func stop() {
        activeConnection?.cancel()
        activeConnection = nil
        listener?.cancel()
        listener = nil
    }

    private func handleConnection(_ connection: NWConnection) {
        activeConnection?.cancel()
        activeConnection = connection
        connection.start(queue: queue)
        receivePacket(on: connection)
    }

    private func receivePacket(on connection: NWConnection) {
        connection.receiveMessage { [weak self] content, _, _, error in
            guard let self, let data = content else {
                // Silence "Operation canceled" from intentional connection cleanup
                return
            }

            guard data.count == Self.audioPacketSize else { return }

            self.packetsReceived += 1
            let seqNum = data.withUnsafeBytes { buf in
                UInt16(littleEndian: buf.loadUnaligned(as: UInt16.self))
            }
            let pcmData = data.subdata(in: Self.audioHeaderSize..<data.count)
            self.onAudioData?(pcmData, seqNum)
            self.receivePacket(on: connection)
        }
    }
}
