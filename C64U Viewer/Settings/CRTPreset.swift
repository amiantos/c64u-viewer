// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.

import Foundation

enum CRTRenderResolution: String, CaseIterable, Identifiable, Sendable, Codable {
    case x2 = "768x544 (2x)"
    case x3 = "1152x816 (3x)"
    case x4 = "1536x1088 (4x)"
    case x5 = "1920x1360 (5x)"

    var id: String { rawValue }

    var size: (width: Int, height: Int) {
        switch self {
        case .x2: return (768, 544)
        case .x3: return (1152, 816)
        case .x4: return (1536, 1088)
        case .x5: return (1920, 1360)
        }
    }
}

struct CRTSettings: Equatable, Sendable, Codable {
    var scanlineIntensity: Float = 0.0
    var scanlineWidth: Float = 0.5
    var blurRadius: Float = 0.0
    var bloomIntensity: Float = 0.0
    var bloomRadius: Float = 0.5
    var afterglowStrength: Float = 0.0
    var afterglowDecaySpeed: Float = 5.0
    var tintMode: Int = 0
    var tintStrength: Float = 1.0
    var maskType: Int = 0
    var maskIntensity: Float = 0.0
    var curvatureAmount: Float = 0.0
    var vignetteStrength: Float = 0.0
    var renderResolution: CRTRenderResolution = .x4

    private enum CodingKeys: String, CodingKey {
        case scanlineIntensity, scanlineWidth, blurRadius, bloomIntensity, bloomRadius
        case afterglowStrength, afterglowDecaySpeed, tintMode, tintStrength
        case maskType, maskIntensity, curvatureAmount, vignetteStrength
    }
}

enum CRTPreset: String, CaseIterable, Identifiable, Sendable, Codable {
    case clean = "Clean"
    case homeCRT = "Home CRT"
    case p3Amber = "P3 Amber"
    case p1Green = "P1 Green"
    case crisp = "Crisp"
    case warmGlow = "Warm Glow"
    case oldTV = "Old TV"
    case arcade = "Arcade"

    var id: String { rawValue }

    var settings: CRTSettings {
        switch self {
        case .clean:
            return CRTSettings()
        case .homeCRT:
            return CRTSettings(
                scanlineIntensity: 0.4, blurRadius: 0.3, bloomIntensity: 0.25, bloomRadius: 0.5,
                maskType: 2, maskIntensity: 0.3, curvatureAmount: 0.3, vignetteStrength: 0.2
            )
        case .p3Amber:
            return CRTSettings(
                scanlineIntensity: 0.35, blurRadius: 0.2, bloomIntensity: 0.3, bloomRadius: 0.5,
                afterglowStrength: 0.5, tintMode: 1,
                maskType: 1, maskIntensity: 0.15, curvatureAmount: 0.25, vignetteStrength: 0.3
            )
        case .p1Green:
            return CRTSettings(
                scanlineIntensity: 0.35, blurRadius: 0.2, bloomIntensity: 0.35, bloomRadius: 0.5,
                afterglowStrength: 0.6, tintMode: 2,
                maskType: 1, maskIntensity: 0.15, curvatureAmount: 0.25, vignetteStrength: 0.3
            )
        case .crisp:
            return CRTSettings(scanlineIntensity: 0.15)
        case .warmGlow:
            return CRTSettings(
                scanlineIntensity: 0.25, blurRadius: 0.3, bloomIntensity: 0.4, bloomRadius: 0.5,
                afterglowStrength: 0.7, afterglowDecaySpeed: 3.5,
                maskType: 2, maskIntensity: 0.2, vignetteStrength: 0.15
            )
        case .oldTV:
            return CRTSettings(
                scanlineIntensity: 0.5, scanlineWidth: 0.6, blurRadius: 0.4, bloomIntensity: 0.3, bloomRadius: 0.5,
                afterglowStrength: 0.3,
                maskType: 3, maskIntensity: 0.35, curvatureAmount: 0.5, vignetteStrength: 0.4
            )
        case .arcade:
            return CRTSettings(
                scanlineIntensity: 0.35, blurRadius: 0.2, bloomIntensity: 0.5, bloomRadius: 0.5,
                maskType: 1, maskIntensity: 0.25, curvatureAmount: 0.2, vignetteStrength: 0.15
            )
        }
    }
}
