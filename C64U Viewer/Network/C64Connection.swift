// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.

import Foundation
import Network
import Observation

@Observable
final class C64Connection {
    var hostname: String = "c64u" {
        didSet { UserDefaults.standard.set(hostname, forKey: "c64_hostname") }
    }
    var videoPort: UInt16 = 11000
    var audioPort: UInt16 = 11001
    var controlPort: UInt16 = 64

    var isConnected = false
    let presetManager = PresetManager()

    var crtSettings = CRTSettings() {
        didSet {
            renderer.crtSettings = crtSettings
            if oldValue.renderResolution != crtSettings.renderResolution {
                UserDefaults.standard.set(crtSettings.renderResolution.rawValue, forKey: "c64_renderResolution")
            }
        }
    }

    var volume: Float = 0.2 {
        didSet {
            audioPlayer.volume = volume
            UserDefaults.standard.set(volume, forKey: "c64_volume")
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
    let controlClient = TCPControlClient()
    let renderer = MetalRenderer()
    let mediaCapture = MediaCapture()

    var isRecording: Bool { mediaCapture.isRecording }

    func selectPreset(_ id: PresetIdentifier) {
        presetManager.selectedIdentifier = id
        var settings = presetManager.settings(for: id)
        settings.renderResolution = crtSettings.renderResolution
        crtSettings = settings
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

        // Restore saved settings
        if let saved = UserDefaults.standard.string(forKey: "c64_hostname"), !saved.isEmpty {
            hostname = saved
        }

        // Restore saved volume
        if UserDefaults.standard.object(forKey: "c64_volume") != nil {
            volume = UserDefaults.standard.float(forKey: "c64_volume")
        }

        // Load settings from preset manager
        var settings = presetManager.settings(for: presetManager.selectedIdentifier)
        if let res = UserDefaults.standard.string(forKey: "c64_renderResolution"),
           let r = CRTRenderResolution(rawValue: res) {
            settings.renderResolution = r
        }
        crtSettings = settings

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

    func connect() {
        guard !isConnected else { return }

        // Start UDP listeners
        videoReceiver.start(port: videoPort)
        audioReceiver.start(port: audioPort)
        audioPlayer.start()

        // Get local IP and send control commands to start streaming
        if let localIP = getLocalIPAddress() {
            controlClient.sendEnableStream(
                host: hostname, controlPort: controlPort,
                streamId: 0, clientIP: localIP, clientPort: videoPort
            )
            // Small delay before starting audio stream
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { [self] in
                controlClient.sendEnableStream(
                    host: hostname, controlPort: controlPort,
                    streamId: 1, clientIP: localIP, clientPort: audioPort
                )
            }
        }

        isConnected = true
        startFPSCounter()
    }

    func takeScreenshot() {
        mediaCapture.takeScreenshot()
    }

    func toggleRecording() {
        if mediaCapture.isRecording {
            mediaCapture.stopRecording()
        } else {
            let size = crtSettings.renderResolution.size
            mediaCapture.startRecording(resolution: size)
        }
    }

    func disconnect() {
        guard isConnected else { return }

        if mediaCapture.isRecording {
            mediaCapture.stopRecording()
        }

        controlClient.sendDisableStream(host: hostname, controlPort: controlPort, streamId: 0)
        controlClient.sendDisableStream(host: hostname, controlPort: controlPort, streamId: 1)

        videoReceiver.stop()
        audioReceiver.stop()
        audioPlayer.stop()
        isConnected = false
        fpsTimer?.cancel()
        fpsTimer = nil
        framesPerSecond = 0
    }

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

    private func getLocalIPAddress() -> String? {
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
