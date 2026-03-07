// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.

import AVFoundation
import Foundation

final class AudioPlayer: @unchecked Sendable {
    private let engine = AVAudioEngine()
    private let playerNode = AVAudioPlayerNode()
    private let format: AVAudioFormat
    private var isPlaying = false
    var onAudioDataForRecording: ((Data) -> Void)?

    var volume: Float = 0.2 {
        didSet { engine.mainMixerNode.outputVolume = volume }
    }

    init() {
        // 48kHz stereo 16-bit integer (close enough to PAL 47982.89 / NTSC 47940.34)
        format = AVAudioFormat(commonFormat: .pcmFormatInt16, sampleRate: 48000, channels: 2, interleaved: true)!
    }

    func start() {
        guard !isPlaying else { return }

        engine.attach(playerNode)
        engine.connect(playerNode, to: engine.mainMixerNode, format: format)

        do {
            try engine.start()
            playerNode.play()
            isPlaying = true
        } catch {
            print("Audio engine failed to start: \(error)")
        }
    }

    func stop() {
        guard isPlaying else { return }
        playerNode.stop()
        engine.stop()
        engine.detach(playerNode)
        isPlaying = false
    }

    func scheduleAudio(_ pcmData: Data) {
        guard isPlaying else { return }

        // pcmData: 768 bytes = 192 stereo samples × 4 bytes (2ch × 16-bit)
        let sampleCount = pcmData.count / 4 // 4 bytes per stereo sample (2 × Int16)
        guard sampleCount > 0 else { return }

        guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(sampleCount)) else {
            return
        }
        buffer.frameLength = AVAudioFrameCount(sampleCount)

        // Copy interleaved 16-bit PCM data directly into the buffer
        pcmData.withUnsafeBytes { srcPtr in
            guard let src = srcPtr.baseAddress else { return }
            if let dst = buffer.int16ChannelData?[0] {
                // Interleaved: copy all samples (L,R,L,R,...)
                memcpy(dst, src, pcmData.count)
            }
        }

        playerNode.scheduleBuffer(buffer)
        onAudioDataForRecording?(pcmData)
    }
}
