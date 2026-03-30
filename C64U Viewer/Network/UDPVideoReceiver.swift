// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.

import Foundation
import Network

final class UDPVideoReceiver: @unchecked Sendable {
    private var listener: NWListener?
    private var activeConnection: NWConnection?
    private let queue = DispatchQueue(label: "com.c64uviewer.video-udp", qos: .userInteractive)
    private let frameAssembler: FrameAssembler
    private var timeoutTimer: DispatchSourceTimer?

    private(set) var packetsReceived: UInt64 = 0

    init(frameAssembler: FrameAssembler) {
        self.frameAssembler = frameAssembler
    }

    func start(port: UInt16) {
        stop()

        let params = NWParameters.udp
        params.allowLocalEndpointReuse = true
        params.requiredLocalEndpoint = NWEndpoint.hostPort(host: .ipv4(.any), port: NWEndpoint.Port(rawValue: port)!)

        do {
            listener = try NWListener(using: params)
        } catch {
            print("Failed to create UDP video listener: \(error)")
            return
        }

        listener?.newConnectionHandler = { [weak self] connection in
            self?.handleConnection(connection)
        }

        listener?.stateUpdateHandler = { state in
            switch state {
            case .ready:
                print("Video UDP listener ready on port \(port)")
            case .failed(let error):
                print("Video UDP listener failed: \(error)")
            default:
                break
            }
        }

        listener?.start(queue: queue)
        startTimeoutTimer()
    }

    func stop() {
        timeoutTimer?.cancel()
        timeoutTimer = nil
        activeConnection?.cancel()
        activeConnection = nil
        listener?.cancel()
        listener = nil
    }

    private func handleConnection(_ connection: NWConnection) {
        // Cancel any previous connection
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
            self.packetsReceived += 1
            self.frameAssembler.processPacket(data)
            self.receivePacket(on: connection)
        }
    }

    private func startTimeoutTimer() {
        let timer = DispatchSource.makeTimerSource(queue: queue)
        timer.schedule(deadline: .now() + .milliseconds(100), repeating: .milliseconds(100))
        timer.setEventHandler { [weak self] in
            self?.frameAssembler.checkTimeout()
        }
        timer.resume()
        timeoutTimer = timer
    }
}
