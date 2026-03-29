// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.

import Foundation

final class C64KeyboardForwarder {
    var isEnabled = false {
        didSet {
            if isEnabled {
                startPolling()
            } else {
                stopPolling()
                keyQueue.removeAll()
            }
        }
    }

    private let client: C64APIClient
    private var keyQueue: [UInt8] = []
    private var pollTimer: DispatchSourceTimer?
    private var isSending = false

    // C64 KERNAL keyboard buffer: $0277-$0280 (10 bytes max)
    // Buffer counter: $00C6
    private let bufferAddress = 0x0277
    private let counterAddress = 0x00C6

    init(client: C64APIClient) {
        self.client = client
    }

    deinit {
        stopPolling()
    }

    func sendKey(_ petscii: UInt8) {
        keyQueue.append(petscii)
    }

    func handleKeyPress(_ characters: String) {
        for char in characters {
            if let petscii = charToPETSCII(char) {
                sendKey(petscii)
            }
        }
    }

    func handleSpecialKey(_ key: SpecialKey) {
        sendKey(key.petscii)
    }

    // MARK: - Polling

    private func startPolling() {
        guard pollTimer == nil else { return }
        let timer = DispatchSource.makeTimerSource(queue: .main)
        timer.schedule(deadline: .now(), repeating: .milliseconds(50))
        timer.setEventHandler { [weak self] in
            self?.pollAndInject()
        }
        timer.resume()
        pollTimer = timer
    }

    private func stopPolling() {
        pollTimer?.cancel()
        pollTimer = nil
    }

    private func pollAndInject() {
        guard isEnabled, !keyQueue.isEmpty, !isSending else { return }
        isSending = true

        Task {
            do {
                // Read buffer counter
                let counterData = try await client.readMem(address: counterAddress, length: 1)
                guard let countByte = counterData.first else {
                    isSending = false
                    return
                }
                let count = Int(countByte)

                // Only inject if buffer has space (max 10)
                if count < 10, let petscii = keyQueue.first {
                    keyQueue.removeFirst()

                    // Write PETSCII byte to buffer at position
                    let writeAddress = bufferAddress + count
                    try await client.writeMem(address: writeAddress, data: Data([petscii]))

                    // Increment buffer counter
                    try await client.writeMem(address: counterAddress, data: Data([UInt8(count + 1)]))
                }
            } catch {
                print("Keyboard inject error: \(error.localizedDescription)")
            }
            isSending = false
        }
    }

    // MARK: - Character Mapping

    private func charToPETSCII(_ char: Character) -> UInt8? {
        // Uppercase letters → PETSCII uppercase ($C1-$DA)
        if char.isUppercase, let ascii = char.asciiValue {
            return ascii - 0x41 + 0xC1
        }

        // Lowercase letters → PETSCII lowercase ($41-$5A, which displays as uppercase in default mode)
        if char.isLetter, let ascii = char.lowercased().first?.asciiValue {
            return ascii - 0x61 + 0x41
        }

        // Numbers and common symbols map directly
        if let ascii = char.asciiValue {
            switch ascii {
            case 0x20...0x3F: return ascii // space, digits, punctuation
            case 0x5B: return 0x5B // [
            case 0x5D: return 0x5D // ]
            case 0x40: return 0x40 // @
            default: break
            }
        }

        // Special character mappings
        switch char {
        case "\r", "\n": return 0x0D // RETURN
        default: return nil
        }
    }
}

// MARK: - Special Keys

enum SpecialKey: String, CaseIterable, Identifiable {
    case runStop = "RUN/STOP"
    case home = "HOME"
    case clr = "CLR"
    case instDel = "DEL"
    case inst = "INST"
    case f1 = "F1"
    case f2 = "F2"
    case f3 = "F3"
    case f4 = "F4"
    case f5 = "F5"
    case f6 = "F6"
    case f7 = "F7"
    case f8 = "F8"
    case cursorUp = "▲"
    case cursorDown = "▼"
    case cursorLeft = "◀"
    case cursorRight = "▶"
    case pound = "£"
    case upArrow = "↑"
    case leftArrow = "←"
    case shiftReturn = "SH+RET"

    var id: String { rawValue }

    var petscii: UInt8 {
        switch self {
        case .runStop: return 0x03
        case .home: return 0x13
        case .clr: return 0x93
        case .instDel: return 0x14
        case .inst: return 0x94
        case .f1: return 0x85
        case .f2: return 0x89
        case .f3: return 0x86
        case .f4: return 0x8A
        case .f5: return 0x87
        case .f6: return 0x8B
        case .f7: return 0x88
        case .f8: return 0x8C
        case .cursorUp: return 0x91
        case .cursorDown: return 0x11
        case .cursorLeft: return 0x9D
        case .cursorRight: return 0x1D
        case .pound: return 0x1C
        case .upArrow: return 0x5E
        case .leftArrow: return 0x5F
        case .shiftReturn: return 0x8D
        }
    }
}
