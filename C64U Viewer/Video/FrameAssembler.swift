// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.

import Foundation

struct VideoPacketHeader {
    let sequenceNum: UInt16
    let frameNum: UInt16
    let lineNum: UInt16    // Actual line number (bit 15 stripped)
    let isLastPacket: Bool // Bit 15 of raw line field
}

final class FrameAssembler: @unchecked Sendable {
    static let pixelsPerLine = 384
    static let bytesPerLine = 192
    static let linesPerPacket = 4
    static let videoHeaderSize = 12
    static let videoPacketSize = 780
    static let palHeight = 272
    static let ntscHeight = 240

    private let lock = NSLock()
    private var currentFrameNum: UInt16 = 0
    private var receivedLines: [UInt16: Data] = [:] // lineNum -> 4 lines of pixel data
    private var lastPacketReceived = false
    private var frameStartTime: CFAbsoluteTime = 0
    private var maxLineReceived: UInt16 = 0

    private let pairLUT = ColorPalette.default.buildPairLUT()

    var onFrameReady: ((_ rgbaData: Data, _ width: Int, _ height: Int) -> Void)?

    func processPacket(_ data: Data) {
        guard data.count == Self.videoPacketSize else { return }

        let header = parseHeader(data)
        let payload = data.subdata(in: Self.videoHeaderSize..<data.count)

        lock.lock()
        defer { lock.unlock() }

        if header.frameNum != currentFrameNum {
            if !receivedLines.isEmpty {
                assembleAndEmitFrame()
            }
            currentFrameNum = header.frameNum
            receivedLines.removeAll(keepingCapacity: true)
            lastPacketReceived = false
            frameStartTime = CFAbsoluteTimeGetCurrent()
            maxLineReceived = 0
        }

        receivedLines[header.lineNum] = payload
        maxLineReceived = max(maxLineReceived, header.lineNum)

        if header.isLastPacket {
            lastPacketReceived = true
        }

        if lastPacketReceived {
            assembleAndEmitFrame()
        }
    }

    func checkTimeout() {
        lock.lock()
        defer { lock.unlock() }

        if !receivedLines.isEmpty && CFAbsoluteTimeGetCurrent() - frameStartTime > 0.1 {
            assembleAndEmitFrame()
        }
    }

    private func parseHeader(_ data: Data) -> VideoPacketHeader {
        data.withUnsafeBytes { buf in
            let ptr = buf.baseAddress!
            let seq = ptr.loadUnaligned(fromByteOffset: 0, as: UInt16.self)
            let frame = ptr.loadUnaligned(fromByteOffset: 2, as: UInt16.self)
            let rawLine = ptr.loadUnaligned(fromByteOffset: 4, as: UInt16.self)
            return VideoPacketHeader(
                sequenceNum: UInt16(littleEndian: seq),
                frameNum: UInt16(littleEndian: frame),
                lineNum: UInt16(littleEndian: rawLine) & 0x7FFF,
                isLastPacket: (UInt16(littleEndian: rawLine) & 0x8000) != 0
            )
        }
    }

    // Must be called with lock held
    private func assembleAndEmitFrame() {
        let totalLines = Int(maxLineReceived) + Self.linesPerPacket
        let height = totalLines <= Self.ntscHeight ? Self.ntscHeight : Self.palHeight
        let width = Self.pixelsPerLine

        // Build 4-bit indexed buffer
        var indexedBuffer = Data(count: Self.bytesPerLine * height)

        for (lineNum, payload) in receivedLines {
            let startLine = Int(lineNum)
            for lineOffset in 0..<Self.linesPerPacket {
                let destLine = startLine + lineOffset
                guard destLine < height else { break }
                let srcOffset = lineOffset * Self.bytesPerLine
                let destOffset = destLine * Self.bytesPerLine
                guard srcOffset + Self.bytesPerLine <= payload.count else { break }
                indexedBuffer.replaceSubrange(destOffset..<destOffset + Self.bytesPerLine,
                                              with: payload.subdata(in: srcOffset..<srcOffset + Self.bytesPerLine))
            }
        }

        // Interpolate missing lines (duplicate nearest valid line above)
        interpolateMissingLines(&indexedBuffer, height: height)

        // Convert to RGBA
        let lut = pairLUT
        let rgbaData = convertToRGBA(indexedBuffer, width: width, height: height, lut: lut)

        receivedLines.removeAll(keepingCapacity: true)
        lastPacketReceived = false

        onFrameReady?(rgbaData, width, height)
    }

    private func interpolateMissingLines(_ buffer: inout Data, height: Int) {
        // Build set of lines we have data for
        var hasLine = [Bool](repeating: false, count: height)
        for lineNum in receivedLines.keys {
            for offset in 0..<Self.linesPerPacket {
                let line = Int(lineNum) + offset
                if line < height { hasLine[line] = true }
            }
        }

        // Fill missing lines by duplicating nearest valid line above
        var lastValidLine = 0
        buffer.withUnsafeMutableBytes { ptr in
            let base = ptr.baseAddress!
            for line in 0..<height {
                if hasLine[line] {
                    lastValidLine = line
                } else {
                    let src = base + lastValidLine * Self.bytesPerLine
                    let dst = base + line * Self.bytesPerLine
                    memcpy(dst, src, Self.bytesPerLine)
                }
            }
        }
    }

    private nonisolated func convertToRGBA(_ indexed: Data, width: Int, height: Int, lut: [(UInt32, UInt32)]) -> Data {
        var rgba = Data(count: width * height * 4)
        rgba.withUnsafeMutableBytes { rgbaPtr in
            indexed.withUnsafeBytes { idxPtr in
                let rgbaBase = rgbaPtr.baseAddress!.assumingMemoryBound(to: UInt32.self)
                let idxBase = idxPtr.baseAddress!.assumingMemoryBound(to: UInt8.self)

                for line in 0..<height {
                    let srcLineOffset = line * Self.bytesPerLine
                    let dstLineOffset = line * width
                    for byteIdx in 0..<Self.bytesPerLine {
                        let byte = idxBase[srcLineOffset + byteIdx]
                        let pair = lut[Int(byte)]
                        let pixIdx = dstLineOffset + byteIdx * 2
                        rgbaBase[pixIdx] = pair.0
                        rgbaBase[pixIdx + 1] = pair.1
                    }
                }
            }
        }
        return rgba
    }
}
