// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.

import Foundation

struct ColorPalette: Sendable {
    let colors: [SIMD4<UInt8>] // 16 RGBA colors

    var rgbaLookup: [UInt32] {
        colors.map { c in
            UInt32(c.x) | (UInt32(c.y) << 8) | (UInt32(c.z) << 16) | (UInt32(c.w) << 24)
        }
    }

    // Pre-computed LUT: maps a byte (two 4-bit pixels) to two RGBA UInt32 values
    func buildPairLUT() -> [(UInt32, UInt32)] {
        let rgba = rgbaLookup
        return (0..<256).map { byte in
            let lo = Int(byte & 0x0F)
            let hi = Int((byte >> 4) & 0x0F)
            return (rgba[lo], rgba[hi])
        }
    }

    static let `default` = ColorPalette(
        colors: [
            SIMD4<UInt8>(0x00, 0x00, 0x00, 0xFF), // 0:  Black
            SIMD4<UInt8>(0xF7, 0xF7, 0xF7, 0xFF), // 1:  White
            SIMD4<UInt8>(0x8D, 0x2F, 0x34, 0xFF), // 2:  Red
            SIMD4<UInt8>(0x6A, 0xD4, 0xCD, 0xFF), // 3:  Cyan
            SIMD4<UInt8>(0x98, 0x35, 0xA4, 0xFF), // 4:  Purple
            SIMD4<UInt8>(0x4C, 0xB4, 0x42, 0xFF), // 5:  Green
            SIMD4<UInt8>(0x2C, 0x29, 0xB1, 0xFF), // 6:  Blue
            SIMD4<UInt8>(0xEF, 0xEF, 0x5D, 0xFF), // 7:  Yellow
            SIMD4<UInt8>(0x98, 0x4E, 0x20, 0xFF), // 8:  Orange
            SIMD4<UInt8>(0x5B, 0x38, 0x00, 0xFF), // 9:  Brown
            SIMD4<UInt8>(0xD1, 0x67, 0x6D, 0xFF), // 10: Pink
            SIMD4<UInt8>(0x4A, 0x4A, 0x4A, 0xFF), // 11: Dark Grey
            SIMD4<UInt8>(0x7B, 0x7B, 0x7B, 0xFF), // 12: Medium Grey
            SIMD4<UInt8>(0x9F, 0xEF, 0x93, 0xFF), // 13: Light Green
            SIMD4<UInt8>(0x6D, 0x6A, 0xEF, 0xFF), // 14: Light Blue
            SIMD4<UInt8>(0xB2, 0xB2, 0xB2, 0xFF), // 15: Light Grey
        ]
    )

}
