// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.

@preconcurrency import MetalKit

struct CRTUniformsBuffer {
    var scanlineIntensity: Float
    var scanlineWidth: Float
    var blurRadius: Float
    var bloomIntensity: Float
    var bloomRadius: Float
    var afterglowStrength: Float
    var afterglowDecaySpeed: Float
    var tintMode: Int32
    var tintStrength: Float
    var maskType: Int32
    var maskIntensity: Float
    var curvatureAmount: Float
    var vignetteStrength: Float
    var dtMs: Float
    var outputWidth: Float
    var outputHeight: Float
    var sourceWidth: Float
    var sourceHeight: Float
}

@MainActor
final class MetalRenderer: NSObject, MTKViewDelegate {
    let device: MTLDevice
    private let commandQueue: MTLCommandQueue
    private var crtPipeline: MTLRenderPipelineState?
    private var blitPipeline: MTLRenderPipelineState?

    private var frameTexture: MTLTexture?
    private var accumTextures: [MTLTexture] = []
    private var accumIndex = 0

    private var currentWidth: Int = 0
    private var currentHeight: Int = 0
    private var currentDrawableWidth: Int = 0
    private var currentDrawableHeight: Int = 0
    private var lastFrameTime: CFAbsoluteTime = 0

    var captureNextFrame = false
    var isRecording = false
    var onFrameCaptured: ((MTLTexture) -> Void)?
    var captureTexture: MTLTexture?
    private var didUploadNewFrame = false

    var crtSettings = CRTSettings()
    var currentRenderSize: (width: Int, height: Int) { (currentDrawableWidth, currentDrawableHeight) }
    private var pendingFrameData: Data?
    private var pendingWidth: Int = 0
    private var pendingHeight: Int = 0

    override init() {
        guard let device = MTLCreateSystemDefaultDevice(),
              let commandQueue = device.makeCommandQueue() else {
            fatalError("Metal is not supported on this device")
        }
        self.device = device
        self.commandQueue = commandQueue

        super.init()

        buildPipelines()
    }

    private func buildPipelines() {
        guard let library = device.makeDefaultLibrary() else {
            print("Failed to create Metal library")
            return
        }

        let crtDesc = MTLRenderPipelineDescriptor()
        crtDesc.vertexFunction = library.makeFunction(name: "crtVertexShader")
        crtDesc.fragmentFunction = library.makeFunction(name: "crtFragmentShader")
        crtDesc.colorAttachments[0].pixelFormat = .rgba8Unorm

        do {
            crtPipeline = try device.makeRenderPipelineState(descriptor: crtDesc)
        } catch {
            print("Failed to create CRT pipeline: \(error)")
        }

        let blitDesc = MTLRenderPipelineDescriptor()
        blitDesc.vertexFunction = library.makeFunction(name: "crtVertexShader")
        blitDesc.fragmentFunction = library.makeFunction(name: "blitFragmentShader")
        blitDesc.colorAttachments[0].pixelFormat = .bgra8Unorm

        do {
            blitPipeline = try device.makeRenderPipelineState(descriptor: blitDesc)
        } catch {
            print("Failed to create blit pipeline: \(error)")
        }
    }

    func updateFrame(rgbaData: Data, width: Int, height: Int) {
        pendingFrameData = rgbaData
        pendingWidth = width
        pendingHeight = height
    }

    private func uploadFrame() {
        guard let data = pendingFrameData else {
            didUploadNewFrame = false
            return
        }
        let width = pendingWidth
        let height = pendingHeight
        pendingFrameData = nil
        didUploadNewFrame = true

        if frameTexture == nil || currentWidth != width || currentHeight != height {
            currentWidth = width
            currentHeight = height
            frameTexture = makeTexture(width: width, height: height, storageMode: .managed)
        }

        guard let texture = frameTexture else { return }
        let region = MTLRegion(origin: MTLOrigin(), size: MTLSize(width: width, height: height, depth: 1))
        data.withUnsafeBytes { ptr in
            texture.replace(region: region, mipmapLevel: 0, withBytes: ptr.baseAddress!, bytesPerRow: width * 4)
        }
    }

    private func makeTexture(width: Int, height: Int, storageMode: MTLStorageMode = .managed) -> MTLTexture? {
        let desc = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: .rgba8Unorm,
            width: width, height: height,
            mipmapped: false
        )
        desc.usage = [.shaderRead, .renderTarget]
        desc.storageMode = storageMode
        return device.makeTexture(descriptor: desc)
    }

    // MARK: - MTKViewDelegate

    nonisolated func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) {}

    nonisolated func draw(in view: MTKView) {
        MainActor.assumeIsolated {
            drawFrame(in: view)
        }
    }

    private func drawFrame(in view: MTKView) {
        uploadFrame()

        guard let crtPipeline, let blitPipeline,
              let frameTexture,
              let commandBuffer = commandQueue.makeCommandBuffer() else { return }

        let now = CFAbsoluteTimeGetCurrent()
        let dtMs = lastFrameTime > 0 ? Float((now - lastFrameTime) * 1000.0) : 16.67
        lastFrameTime = now

        // Use drawable size for CRT rendering
        let drawableSize = view.drawableSize
        let drawW = Int(drawableSize.width)
        let drawH = Int(drawableSize.height)

        if drawW != currentDrawableWidth || drawH != currentDrawableHeight || accumTextures.isEmpty {
            currentDrawableWidth = drawW
            currentDrawableHeight = drawH
            if drawW > 0 && drawH > 0 {
                guard let tex0 = makeTexture(width: drawW, height: drawH, storageMode: .private),
                      let tex1 = makeTexture(width: drawW, height: drawH, storageMode: .private) else { return }
                accumTextures = [tex0, tex1]
                accumIndex = 0
            }
        }

        var uniforms = CRTUniformsBuffer(
            scanlineIntensity: crtSettings.scanlineIntensity,
            scanlineWidth: crtSettings.scanlineWidth,
            blurRadius: crtSettings.blurRadius,
            bloomIntensity: crtSettings.bloomIntensity,
            bloomRadius: crtSettings.bloomRadius,
            afterglowStrength: crtSettings.afterglowStrength,
            afterglowDecaySpeed: crtSettings.afterglowDecaySpeed,
            tintMode: Int32(crtSettings.tintMode),
            tintStrength: crtSettings.tintStrength,
            maskType: Int32(crtSettings.maskType),
            maskIntensity: crtSettings.maskIntensity,
            curvatureAmount: crtSettings.curvatureAmount,
            vignetteStrength: crtSettings.vignetteStrength,
            dtMs: dtMs,
            outputWidth: Float(drawW),
            outputHeight: Float(drawH),
            sourceWidth: Float(currentWidth),
            sourceHeight: Float(currentHeight)
        )

        let hasCRTEffects = crtSettings.scanlineIntensity > 0 || crtSettings.blurRadius > 0 ||
                            crtSettings.bloomIntensity > 0 || crtSettings.tintMode > 0 ||
                            crtSettings.afterglowStrength > 0 || crtSettings.maskType > 0 ||
                            crtSettings.curvatureAmount > 0 || crtSettings.vignetteStrength > 0

        let needsCapture = (captureNextFrame || isRecording) && didUploadNewFrame
        let runCRT = hasCRTEffects || captureNextFrame || isRecording

        if runCRT, accumTextures.count == 2 {
            let readAccum = accumTextures[accumIndex]
            let writeAccum = accumTextures[1 - accumIndex]

            // Pass 1: CRT shader (source → accumWrite at CRT resolution)
            let accumDesc = MTLRenderPassDescriptor()
            accumDesc.colorAttachments[0].texture = writeAccum
            accumDesc.colorAttachments[0].loadAction = .dontCare
            accumDesc.colorAttachments[0].storeAction = .store

            if let encoder = commandBuffer.makeRenderCommandEncoder(descriptor: accumDesc) {
                encoder.setRenderPipelineState(crtPipeline)
                encoder.setFragmentTexture(frameTexture, index: 0)
                encoder.setFragmentTexture(readAccum, index: 1)
                encoder.setFragmentBytes(&uniforms, length: MemoryLayout<CRTUniformsBuffer>.size, index: 0)
                encoder.drawPrimitives(type: .triangleStrip, vertexStart: 0, vertexCount: 4)
                encoder.endEncoding()
            }

            // Blit to capture texture (GPU-direct, no CPU copy)
            if needsCapture, let captureTexture {
                let captureDesc = MTLRenderPassDescriptor()
                captureDesc.colorAttachments[0].texture = captureTexture
                captureDesc.colorAttachments[0].loadAction = .dontCare
                captureDesc.colorAttachments[0].storeAction = .store
                if let encoder = commandBuffer.makeRenderCommandEncoder(descriptor: captureDesc) {
                    encoder.setRenderPipelineState(blitPipeline)
                    encoder.setFragmentTexture(writeAccum, index: 0)
                    encoder.drawPrimitives(type: .triangleStrip, vertexStart: 0, vertexCount: 4)
                    encoder.endEncoding()
                }
            }

            // Pass 2: Blit CRT result to drawable (only if window is visible)
            if let drawableDesc = view.currentRenderPassDescriptor,
               let drawable = view.currentDrawable {
                if let encoder = commandBuffer.makeRenderCommandEncoder(descriptor: drawableDesc) {
                    encoder.setRenderPipelineState(blitPipeline)
                    encoder.setFragmentTexture(writeAccum, index: 0)
                    encoder.drawPrimitives(type: .triangleStrip, vertexStart: 0, vertexCount: 4)
                    encoder.endEncoding()
                }
                commandBuffer.present(drawable)
            }

            accumIndex = 1 - accumIndex
        } else {
            // No CRT effects: blit source directly to drawable
            if let drawableDesc = view.currentRenderPassDescriptor,
               let drawable = view.currentDrawable {
                if let encoder = commandBuffer.makeRenderCommandEncoder(descriptor: drawableDesc) {
                    encoder.setRenderPipelineState(blitPipeline)
                    encoder.setFragmentTexture(frameTexture, index: 0)
                    encoder.drawPrimitives(type: .triangleStrip, vertexStart: 0, vertexCount: 4)
                    encoder.endEncoding()
                }
                commandBuffer.present(drawable)
            }
        }

        // Fire capture callback after GPU completes
        if needsCapture, let captureTexture, let callback = onFrameCaptured {
            captureNextFrame = false
            commandBuffer.addCompletedHandler { _ in
                DispatchQueue.main.async {
                    callback(captureTexture)
                }
            }
        } else if captureNextFrame {
            captureNextFrame = false
        }

        commandBuffer.commit()
    }
}
