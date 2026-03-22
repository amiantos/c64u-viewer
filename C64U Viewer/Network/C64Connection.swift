// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.

import Foundation
import Observation

@Observable
final class C64Connection {
    var videoPort: UInt16 = 11000
    var audioPort: UInt16 = 11001

    var isConnected = false
    var connectionMode: ConnectionMode?
    var apiClient: C64APIClient?
    var deviceInfo: DeviceInfo?
    var connectionError: String?
    var keyboardForwarder: C64KeyboardForwarder?

    let presetManager = PresetManager()
    let recentConnections = RecentConnections()

    var crtSettings = CRTSettings() {
        didSet {
            renderer.crtSettings = crtSettings
        }
    }

    var volume: Float = 0.2 {
        didSet {
            audioPlayer.volume = volume
            UserDefaults.standard.set(volume, forKey: "c64_volume")
        }
    }
    var balance: Float = 0.0 {
        didSet {
            audioPlayer.balance = balance
            UserDefaults.standard.set(balance, forKey: "c64_balance")
        }
    }
    var isMuted = false

    private(set) var framesPerSecond: Double = 0
    private var frameCount = 0
    private var fpsTimer: DispatchSourceTimer?

    let frameAssembler = FrameAssembler()
    let videoReceiver: UDPVideoReceiver
    let audioReceiver = UDPAudioReceiver()
    let audioPlayer = AudioPlayer()
    let renderer = MetalRenderer()
    let mediaCapture = MediaCapture()

    var isRecording: Bool { mediaCapture.isRecording }

    func selectPreset(_ id: PresetIdentifier) {
        presetManager.selectedIdentifier = id
        crtSettings = presetManager.settings(for: id)
        presetManager.schedulePersist()
    }

    func applySettingsChange() {
        switch presetManager.selectedIdentifier {
        case .builtIn(let preset):
            presetManager.saveOverride(for: preset, settings: crtSettings)
        case .custom(let id):
            presetManager.updateCustom(id: id, settings: crtSettings)
        }
    }

    init() {
        videoReceiver = UDPVideoReceiver(frameAssembler: frameAssembler)

        // Restore saved volume and balance
        if UserDefaults.standard.object(forKey: "c64_volume") != nil {
            volume = UserDefaults.standard.float(forKey: "c64_volume")
        }
        if UserDefaults.standard.object(forKey: "c64_balance") != nil {
            balance = UserDefaults.standard.float(forKey: "c64_balance")
        }

        // Load settings from preset manager
        crtSettings = presetManager.settings(for: presetManager.selectedIdentifier)

        mediaCapture.renderer = renderer
        mediaCapture.audioPlayer = audioPlayer

        frameAssembler.onFrameReady = { [weak self] rgbaData, width, height in
            guard let self else { return }
            DispatchQueue.main.async {
                self.frameCount += 1
                self.renderer.updateFrame(rgbaData: rgbaData, width: width, height: height)
            }
        }

        audioReceiver.onAudioData = { [weak self] pcmData, _ in
            self?.audioPlayer.scheduleAudio(pcmData)
        }
    }

    // MARK: - Viewer Mode

    func listen(videoPort: UInt16, audioPort: UInt16) {
        guard !isConnected else { return }

        self.videoPort = videoPort
        self.audioPort = audioPort
        connectionMode = .viewer
        connectionError = nil

        videoReceiver.start(port: videoPort)
        audioReceiver.start(port: audioPort)
        audioPlayer.start()

        recentConnections.addViewer(videoPort: videoPort, audioPort: audioPort)

        isConnected = true
        startFPSCounter()
    }

    // MARK: - Toolbox Mode

    func connectToolbox(ip: String, password: String?, savePassword: Bool) {
        guard !isConnected else { return }

        connectionMode = .toolbox
        connectionError = nil
        let client = C64APIClient(host: ip, password: password)
        apiClient = client

        // Verify connection before fully committing
        Task {
            do {
                let info = try await client.fetchInfo()
                self.deviceInfo = info
                print("C64U device: \(info.product) v\(info.firmwareVersion) (\(info.hostname))")

                // Connection verified — start everything
                keyboardForwarder = C64KeyboardForwarder(client: client)
                videoReceiver.start(port: videoPort)
                audioReceiver.start(port: audioPort)
                audioPlayer.start()
                isConnected = true
                startFPSCounter()
                recentConnections.addToolbox(ipAddress: ip, password: password, savePassword: savePassword)
                startStreams()
            } catch let error as C64APIError {
                if case .httpError(403) = error {
                    self.connectionError = "Incorrect password"
                } else {
                    self.connectionError = error.localizedDescription
                }
                print("C64U API error: \(error.localizedDescription)")
                apiClient = nil
                connectionMode = nil
            } catch {
                self.connectionError = error.localizedDescription
                print("C64U API error: \(error.localizedDescription)")
                apiClient = nil
                connectionMode = nil
            }
        }
    }

    // MARK: - Disconnect

    func disconnect() {
        guard isConnected else { return }

        if mediaCapture.isRecording {
            mediaCapture.stopRecording()
        }

        // Stop streams via API in Toolbox Mode
        if connectionMode == .toolbox, let client = apiClient {
            Task {
                try? await client.stopStream("video")
                try? await client.stopStream("audio")
            }
        }

        videoReceiver.stop()
        audioReceiver.stop()
        audioPlayer.stop()
        isConnected = false
        connectionMode = nil
        keyboardForwarder?.isEnabled = false
        keyboardForwarder = nil
        apiClient = nil
        deviceInfo = nil
        connectionError = nil
        streamsActive = false
        isWaitingForReboot = false
        fpsTimer?.cancel()
        fpsTimer = nil
        framesPerSecond = 0
    }

    // MARK: - Toolbox Actions

    var streamsActive = false

    func startStreams() {
        guard let client = apiClient else { return }
        Task {
            do {
                if let localIP = getLocalIPAddress() {
                    try await client.startStream("video", clientIP: localIP, port: videoPort)
                    try await client.startStream("audio", clientIP: localIP, port: audioPort)
                    self.streamsActive = true
                    self.connectionError = nil
                }
            } catch {
                print("C64U stream start error: \(error.localizedDescription)")
                self.connectionError = error.localizedDescription
            }
        }
    }

    func stopStreams() {
        guard let client = apiClient else { return }
        Task {
            do {
                try await client.stopStream("video")
                try await client.stopStream("audio")
                self.streamsActive = false
                self.connectionError = nil
            } catch {
                print("C64U stream stop error: \(error.localizedDescription)")
                self.connectionError = error.localizedDescription
            }
        }
    }

    func runFile(type: RunnerType, data: Data) {
        guard let client = apiClient else { return }
        Task {
            do {
                switch type {
                case .sid: try await client.runSID(data: data)
                case .prg: try await client.runPRG(data: data)
                case .crt: try await client.runCRT(data: data)
                }
            } catch {
                print("C64U runner error: \(error.localizedDescription)")
                self.connectionError = error.localizedDescription
            }
        }
    }

    var isWaitingForReboot = false

    func machineAction(_ action: MachineAction) {
        guard let client = apiClient else { return }
        Task {
            do {
                switch action {
                case .reset: try await client.machineReset()
                case .reboot: try await client.machineReboot()
                case .powerOff: try await client.machinePowerOff()
                case .menuButton: try await client.menuButton()
                }

                if action == .reboot {
                    await waitForDeviceAndRestartStreams(client: client)
                } else if action == .powerOff {
                    disconnect()
                }
            } catch {
                print("C64U machine error: \(error.localizedDescription)")
                self.connectionError = error.localizedDescription
            }
        }
    }

    private func waitForDeviceAndRestartStreams(client: C64APIClient) async {
        isWaitingForReboot = true
        streamsActive = false
        connectionError = "Waiting for device to restart..."

        // Wait a few seconds for device to go down
        try? await Task.sleep(for: .seconds(3))

        // Poll until device responds (up to 60 seconds)
        for _ in 0..<30 {
            guard isConnected else { break }
            do {
                let info = try await client.fetchInfo()
                self.deviceInfo = info
                self.connectionError = nil
                self.isWaitingForReboot = false
                startStreams()
                return
            } catch {
                try? await Task.sleep(for: .seconds(2))
            }
        }

        isWaitingForReboot = false
        connectionError = "Device did not come back online"
    }

    // MARK: - Capture

    func takeScreenshot() {
        mediaCapture.takeScreenshot()
    }

    func toggleRecording() {
        if mediaCapture.isRecording {
            mediaCapture.stopRecording()
        } else {
            let size = renderer.currentRenderSize
            guard size.width > 0 && size.height > 0 else { return }
            mediaCapture.startRecording(resolution: size)
        }
    }

    // MARK: - Private

    private func startFPSCounter() {
        let timer = DispatchSource.makeTimerSource(queue: .main)
        timer.schedule(deadline: .now() + 1, repeating: 1)
        timer.setEventHandler { [weak self] in
            guard let self else { return }
            self.framesPerSecond = Double(self.frameCount)
            self.frameCount = 0
        }
        timer.resume()
        fpsTimer = timer
    }

    func getLocalIPAddress() -> String? {
        var address: String?
        var ifaddr: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&ifaddr) == 0, let firstAddr = ifaddr else { return nil }
        defer { freeifaddrs(ifaddr) }

        for ptr in sequence(first: firstAddr, next: { $0.pointee.ifa_next }) {
            let flags = Int32(ptr.pointee.ifa_flags)
            let addr = ptr.pointee.ifa_addr.pointee

            guard (flags & (IFF_UP | IFF_RUNNING)) != 0,
                  (flags & IFF_LOOPBACK) == 0,
                  addr.sa_family == UInt8(AF_INET) else { continue }

            var hostname = [CChar](repeating: 0, count: Int(NI_MAXHOST))
            if getnameinfo(ptr.pointee.ifa_addr, socklen_t(addr.sa_len),
                           &hostname, socklen_t(hostname.count),
                           nil, 0, NI_NUMERICHOST) == 0 {
                address = String(cString: hostname)
                break
            }
        }
        return address
    }
}

enum RunnerType {
    case sid, prg, crt
}

enum MachineAction: Equatable {
    case reset, reboot, powerOff, menuButton
}
