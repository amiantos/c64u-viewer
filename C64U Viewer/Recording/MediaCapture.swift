// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.

import AppKit
import AVFoundation
import CoreMedia
import CoreVideo
import Metal

@MainActor
final class MediaCapture {
    private(set) var isRecording = false

    private var assetWriter: AVAssetWriter?
    private var videoInput: AVAssetWriterInput?
    private var audioInput: AVAssetWriterInput?
    private var pixelBufferAdaptor: AVAssetWriterInputPixelBufferAdaptor?

    private var recordingStartTime: CFAbsoluteTime = 0
    private var audioSampleOffset: Int64 = 0

    // CVPixelBuffer-backed MTLTexture for zero-copy GPU capture
    private var capturePixelBuffer: CVPixelBuffer?
    private var captureTextureCache: CVMetalTextureCache?

    weak var renderer: MetalRenderer?
    weak var audioPlayer: AudioPlayer?

    // MARK: - Screenshot

    func takeScreenshot() {
        guard let renderer else { return }

        // Create a managed readback texture for screenshot (one-shot, OK to be slow)
        let crtSize = renderer.crtSettings.renderResolution.size
        let desc = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: .bgra8Unorm,
            width: crtSize.width, height: crtSize.height,
            mipmapped: false
        )
        desc.usage = [.shaderRead, .renderTarget]
        desc.storageMode = .managed
        guard let texture = renderer.device.makeTexture(descriptor: desc) else { return }

        renderer.captureTexture = texture
        renderer.captureNextFrame = true
        renderer.onFrameCaptured = { [weak self] tex in
            guard let self else { return }
            self.renderer?.captureTexture = nil
            if !self.isRecording {
                self.renderer?.onFrameCaptured = nil
            }
            self.saveScreenshot(from: tex)
        }
    }

    private func saveScreenshot(from texture: MTLTexture) {
        let width = texture.width
        let height = texture.height
        let bytesPerRow = width * 4

        var bytes = [UInt8](repeating: 0, count: bytesPerRow * height)
        texture.getBytes(&bytes, bytesPerRow: bytesPerRow,
                         from: MTLRegion(origin: MTLOrigin(),
                                         size: MTLSize(width: width, height: height, depth: 1)),
                         mipmapLevel: 0)

        let colorSpace = CGColorSpace(name: CGColorSpace.sRGB)!
        guard let context = CGContext(
            data: &bytes, width: width, height: height,
            bitsPerComponent: 8, bytesPerRow: bytesPerRow,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue
        ), let image = context.makeImage() else { return }

        let rep = NSBitmapImageRep(cgImage: image)
        guard let pngData = rep.representation(using: .png, properties: [:]) else { return }

        let panel = NSSavePanel()
        panel.allowedContentTypes = [.png]
        panel.directoryURL = FileManager.default.urls(for: .desktopDirectory, in: .userDomainMask).first
        panel.nameFieldStringValue = "C64 Screenshot \(Self.timestamp()).png"

        guard panel.runModal() == .OK, let url = panel.url else { return }
        try? pngData.write(to: url)
    }

    // MARK: - Recording

    func startRecording(resolution: (width: Int, height: Int)) {
        guard let renderer else { return }

        // Create texture cache for CVPixelBuffer → MTLTexture
        var cache: CVMetalTextureCache?
        CVMetalTextureCacheCreate(nil, nil, renderer.device, nil, &cache)
        guard let cache else { return }
        captureTextureCache = cache

        let tempURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension("mov")
        beginWriting(to: tempURL, resolution: resolution)
    }

    private func beginWriting(to url: URL, resolution: (width: Int, height: Int)) {
        do {
            let writer = try AVAssetWriter(url: url, fileType: .mov)

            let videoSettings: [String: Any] = [
                AVVideoCodecKey: AVVideoCodecType.h264,
                AVVideoWidthKey: resolution.width,
                AVVideoHeightKey: resolution.height
            ]
            let vInput = AVAssetWriterInput(mediaType: .video, outputSettings: videoSettings)
            vInput.expectsMediaDataInRealTime = true

            let sourceAttrs: [String: Any] = [
                kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
                kCVPixelBufferWidthKey as String: resolution.width,
                kCVPixelBufferHeightKey as String: resolution.height,
                kCVPixelBufferMetalCompatibilityKey as String: true
            ]
            let adaptor = AVAssetWriterInputPixelBufferAdaptor(
                assetWriterInput: vInput,
                sourcePixelBufferAttributes: sourceAttrs
            )

            let audioSettings: [String: Any] = [
                AVFormatIDKey: kAudioFormatMPEG4AAC,
                AVSampleRateKey: 48000,
                AVNumberOfChannelsKey: 2,
                AVEncoderBitRateKey: 128000
            ]
            let aInput = AVAssetWriterInput(mediaType: .audio, outputSettings: audioSettings)
            aInput.expectsMediaDataInRealTime = true

            writer.add(vInput)
            writer.add(aInput)
            writer.startWriting()
            writer.startSession(atSourceTime: .zero)

            self.assetWriter = writer
            self.videoInput = vInput
            self.audioInput = aInput
            self.pixelBufferAdaptor = adaptor
            self.recordingStartTime = CFAbsoluteTimeGetCurrent()
            self.audioSampleOffset = 0
            self.isRecording = true

            renderer?.isRecording = true
            renderer?.onFrameCaptured = { [weak self] _ in
                self?.appendVideoFrame()
            }
            audioPlayer?.onAudioDataForRecording = { [weak self] data in
                self?.appendAudioData(data)
            }

            // Create initial capture texture
            updateCaptureTexture(width: resolution.width, height: resolution.height)
        } catch {
            print("Failed to create asset writer: \(error)")
        }
    }

    private func updateCaptureTexture(width: Int, height: Int) {
        guard let cache = captureTextureCache else { return }

        var pb: CVPixelBuffer?
        CVPixelBufferCreate(nil, width, height, kCVPixelFormatType_32BGRA,
                            [kCVPixelBufferMetalCompatibilityKey: true] as CFDictionary, &pb)
        guard let pb else { return }

        var cvTexture: CVMetalTexture?
        CVMetalTextureCacheCreateTextureFromImage(
            nil, cache, pb, nil, .bgra8Unorm, width, height, 0, &cvTexture
        )
        guard let cvTexture, let mtlTexture = CVMetalTextureGetTexture(cvTexture) else { return }

        capturePixelBuffer = pb
        renderer?.captureTexture = mtlTexture
    }

    func stopRecording() {
        guard isRecording else { return }
        isRecording = false
        renderer?.isRecording = false
        renderer?.onFrameCaptured = nil
        renderer?.captureTexture = nil
        audioPlayer?.onAudioDataForRecording = nil
        capturePixelBuffer = nil
        captureTextureCache = nil

        let tempURL = assetWriter?.outputURL

        videoInput?.markAsFinished()
        audioInput?.markAsFinished()
        assetWriter?.finishWriting { [weak self] in
            if let error = self?.assetWriter?.error {
                print("Asset writer error: \(error)")
            }
            DispatchQueue.main.async {
                self?.assetWriter = nil
                self?.videoInput = nil
                self?.audioInput = nil
                self?.pixelBufferAdaptor = nil

                if let tempURL {
                    self?.promptToSaveRecording(tempURL: tempURL)
                }
            }
        }
    }

    private func promptToSaveRecording(tempURL: URL) {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.movie]
        panel.directoryURL = FileManager.default.urls(for: .desktopDirectory, in: .userDomainMask).first
        panel.nameFieldStringValue = "C64 Recording \(Self.timestamp()).mov"

        if panel.runModal() == .OK, let destURL = panel.url {
            try? FileManager.default.moveItem(at: tempURL, to: destURL)
        } else {
            try? FileManager.default.removeItem(at: tempURL)
        }
    }

    // MARK: - Frame Append

    private func appendVideoFrame() {
        guard isRecording,
              let adaptor = pixelBufferAdaptor,
              let input = videoInput,
              input.isReadyForMoreMediaData,
              let pb = capturePixelBuffer else { return }

        let elapsed = CFAbsoluteTimeGetCurrent() - recordingStartTime
        let time = CMTime(seconds: elapsed, preferredTimescale: 600)
        adaptor.append(pb, withPresentationTime: time)
    }

    private func appendAudioData(_ pcmData: Data) {
        guard isRecording,
              let input = audioInput,
              input.isReadyForMoreMediaData else { return }

        let sampleCount = pcmData.count / 4
        guard sampleCount > 0 else { return }

        var formatDesc: CMAudioFormatDescription?
        var asbd = AudioStreamBasicDescription(
            mSampleRate: 48000,
            mFormatID: kAudioFormatLinearPCM,
            mFormatFlags: kLinearPCMFormatFlagIsSignedInteger | kLinearPCMFormatFlagIsPacked,
            mBytesPerPacket: 4,
            mFramesPerPacket: 1,
            mBytesPerFrame: 4,
            mChannelsPerFrame: 2,
            mBitsPerChannel: 16,
            mReserved: 0
        )
        CMAudioFormatDescriptionCreate(
            allocator: kCFAllocatorDefault,
            asbd: &asbd,
            layoutSize: 0, layout: nil,
            magicCookieSize: 0, magicCookie: nil,
            extensions: nil,
            formatDescriptionOut: &formatDesc
        )
        guard let fmt = formatDesc else { return }

        let timestamp = CMTime(value: audioSampleOffset, timescale: 48000)

        var sampleBuffer: CMSampleBuffer?
        var timing = CMSampleTimingInfo(
            duration: CMTime(value: 1, timescale: 48000),
            presentationTimeStamp: timestamp,
            decodeTimeStamp: .invalid
        )

        pcmData.withUnsafeBytes { rawPtr in
            guard let baseAddress = rawPtr.baseAddress else { return }

            var blockBuffer: CMBlockBuffer?
            CMBlockBufferCreateWithMemoryBlock(
                allocator: kCFAllocatorDefault,
                memoryBlock: nil,
                blockLength: pcmData.count,
                blockAllocator: kCFAllocatorDefault,
                customBlockSource: nil,
                offsetToData: 0,
                dataLength: pcmData.count,
                flags: 0,
                blockBufferOut: &blockBuffer
            )
            guard let bb = blockBuffer else { return }

            CMBlockBufferReplaceDataBytes(
                with: baseAddress,
                blockBuffer: bb,
                offsetIntoDestination: 0,
                dataLength: pcmData.count
            )

            CMSampleBufferCreate(
                allocator: kCFAllocatorDefault,
                dataBuffer: bb,
                dataReady: true,
                makeDataReadyCallback: nil,
                refcon: nil,
                formatDescription: fmt,
                sampleCount: sampleCount,
                sampleTimingEntryCount: 1,
                sampleTimingArray: &timing,
                sampleSizeEntryCount: 0,
                sampleSizeArray: nil,
                sampleBufferOut: &sampleBuffer
            )
        }

        if let sb = sampleBuffer {
            input.append(sb)
        }

        audioSampleOffset += Int64(sampleCount)
    }

    // MARK: - Helpers

    private static func timestamp() -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd 'at' HH.mm.ss"
        return formatter.string(from: Date())
    }
}
