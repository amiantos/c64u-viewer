// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.

import AppKit

final class DebugMonitorViewController: NSViewController, NSTextViewDelegate {
    let connection: C64Connection
    private var textView: NSTextView!
    private var commandHistory: [String] = []
    private var historyIndex: Int = -1
    private var inputStart: Int = 0  // Character index where current input begins

    private let monoFont = NSFont.monospacedSystemFont(ofSize: 12, weight: .regular)
    private let promptString = "> "

    init(connection: C64Connection) {
        self.connection = connection
        super.init(nibName: nil, bundle: nil)
        self.title = "6510 Monitor"
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    override func loadView() {
        let container = BackgroundView()
        container.backgroundColor = .textBackgroundColor

        let scrollView = NSTextView.scrollableTextView()
        textView = scrollView.documentView as? NSTextView
        textView.isEditable = true
        textView.isSelectable = true
        textView.font = monoFont
        textView.backgroundColor = .textBackgroundColor
        textView.textColor = .textColor
        textView.insertionPointColor = .textColor
        textView.textContainerInset = NSSize(width: 8, height: 8)
        textView.isAutomaticQuoteSubstitutionEnabled = false
        textView.isAutomaticDashSubstitutionEnabled = false
        textView.isAutomaticTextReplacementEnabled = false
        textView.isAutomaticSpellingCorrectionEnabled = false
        textView.delegate = self
        scrollView.drawsBackground = false
        scrollView.hasVerticalScroller = true
        scrollView.translatesAutoresizingMaskIntoConstraints = false

        container.addSubview(scrollView)
        NSLayoutConstraint.activate([
            scrollView.topAnchor.constraint(equalTo: container.topAnchor),
            scrollView.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            scrollView.bottomAnchor.constraint(equalTo: container.bottomAnchor),
        ])

        self.view = container

        appendOutput("Ultimate Toolbox Remote Monitor\nType 'help' for a list of commands.\n")
        showPrompt()
    }

    override func viewDidAppear() {
        super.viewDidAppear()
        view.window?.makeFirstResponder(textView)
    }

    // MARK: - Prompt & Output

    private func showPrompt() {
        let prompt = NSAttributedString(string: promptString, attributes: [
            .font: monoFont,
            .foregroundColor: NSColor.secondaryLabelColor,
        ])
        textView.textStorage?.append(prompt)
        inputStart = textView.string.count
        textView.setSelectedRange(NSRange(location: inputStart, length: 0))
        textView.scrollToEndOfDocument(nil)
    }

    private func appendOutput(_ text: String) {
        let attributed = NSAttributedString(string: text + "\n", attributes: [
            .font: monoFont,
            .foregroundColor: NSColor.textColor,
        ])
        textView.textStorage?.append(attributed)
    }

    private var currentInput: String {
        let fullText = textView.string
        guard inputStart <= fullText.count else { return "" }
        let startIndex = fullText.index(fullText.startIndex, offsetBy: inputStart)
        return String(fullText[startIndex...]).trimmingCharacters(in: .newlines)
    }

    // MARK: - NSTextViewDelegate

    func textView(_ textView: NSTextView, shouldChangeTextIn affectedCharRange: NSRange, replacementString: String?) -> Bool {
        // Don't allow editing output area (before input start)
        if affectedCharRange.location < inputStart {
            // Allow if it's a selection that starts before but extends into input area
            if affectedCharRange.location + affectedCharRange.length > inputStart {
                return false
            }
            return false
        }
        return true
    }

    func textView(_ textView: NSTextView, doCommandBy commandSelector: Selector) -> Bool {
        if commandSelector == #selector(insertNewline(_:)) {
            let input = currentInput
            // Add newline after the input
            textView.textStorage?.append(NSAttributedString(string: "\n"))

            if !input.isEmpty {
                commandHistory.append(input)
                historyIndex = commandHistory.count
                executeCommand(input)
            } else {
                showPrompt()
            }
            return true
        }

        if commandSelector == #selector(moveUp(_:)) {
            if historyIndex > 0 {
                historyIndex -= 1
                replaceInput(commandHistory[historyIndex])
            }
            return true
        }

        if commandSelector == #selector(moveDown(_:)) {
            if historyIndex < commandHistory.count - 1 {
                historyIndex += 1
                replaceInput(commandHistory[historyIndex])
            } else {
                historyIndex = commandHistory.count
                replaceInput("")
            }
            return true
        }

        // Prevent backspace from going past the prompt
        if commandSelector == #selector(deleteBackward(_:)) {
            let selectedRange = textView.selectedRange()
            if selectedRange.location <= inputStart && selectedRange.length == 0 {
                return true // eat the event
            }
        }

        return false
    }

    private func replaceInput(_ text: String) {
        let fullText = textView.string
        let range = NSRange(location: inputStart, length: fullText.count - inputStart)
        textView.textStorage?.replaceCharacters(in: range, with: NSAttributedString(string: text, attributes: [
            .font: monoFont,
            .foregroundColor: NSColor.textColor,
        ]))
        textView.setSelectedRange(NSRange(location: textView.string.count, length: 0))
    }

    // MARK: - Command Execution

    private func executeCommand(_ input: String) {
        let parts = input.trimmingCharacters(in: .whitespaces).split(separator: " ").map(String.init)
        guard let command = parts.first?.lowercased() else {
            showPrompt()
            return
        }

        switch command {
        case "help", "?":
            showHelp()
            showPrompt()
        case "m":
            commandMemoryDump(args: Array(parts.dropFirst()))
        case "d":
            commandDisassemble(args: Array(parts.dropFirst()))
        case "h":
            commandHunt(args: Array(parts.dropFirst()))
        case "f":
            commandFill(args: Array(parts.dropFirst()))
        case "r":
            commandReadByte(args: Array(parts.dropFirst()))
        case "w":
            commandWriteByte(args: Array(parts.dropFirst()))
        case "clear", "cls":
            textView.string = ""
            showPrompt()
        default:
            appendOutput("Unknown command: \(command). Type 'help' for commands.")
            showPrompt()
        }
    }

    // MARK: - Commands

    private func showHelp() {
        appendOutput("""
        Available commands:
          m <addr>             Memory dump, 256 bytes
          m <start> <end>      Memory dump, range
          d <addr>             Disassemble from address
          d <start> <end>      Disassemble range
          h <start> <end> <b>  Hunt for byte pattern
          f <start> <end> <b>  Fill range with byte
          r <addr>             Read single byte
          w <addr> <byte>      Write single byte
          clear                Clear screen
          help                 This help text
        All values in hexadecimal.
        """)
    }

    private func commandMemoryDump(args: [String]) {
        guard let startAddr = parseHex(args.first) else {
            appendOutput("Usage: m <addr> [end_addr]")
            showPrompt()
            return
        }
        let endAddr = args.count > 1 ? (parseHex(args[1]) ?? startAddr + 0xFF) : startAddr + 0xFF
        let length = min(endAddr - startAddr + 1, 0x1000)

        guard let client = connection.apiClient else {
            appendOutput("Error: Not connected")
            showPrompt()
            return
        }

        Task {
            do {
                let data = try await client.readMem(address: startAddr, length: length)
                var output = ""
                for row in stride(from: 0, to: data.count, by: 16) {
                    let addr = startAddr + row
                    var hex = String(format: "%04X: ", addr)
                    var ascii = ""
                    for col in 0..<16 {
                        let offset = row + col
                        if offset < data.count {
                            hex += String(format: "%02X ", data[offset])
                            let byte = data[offset]
                            ascii += (byte >= 0x20 && byte <= 0x7E) ? String(UnicodeScalar(byte)) : "."
                        }
                    }
                    output += hex + " " + ascii + "\n"
                }
                appendOutput(output)
            } catch {
                appendOutput("Error: \(error.localizedDescription)")
            }
            showPrompt()
        }
    }

    private func commandDisassemble(args: [String]) {
        guard let startAddr = parseHex(args.first) else {
            appendOutput("Usage: d <addr> [end_addr]")
            showPrompt()
            return
        }
        let endAddr = args.count > 1 ? (parseHex(args[1]) ?? startAddr + 0x3F) : startAddr + 0x3F
        let length = min(endAddr - startAddr + 1, 0x1000)

        guard let client = connection.apiClient else {
            appendOutput("Error: Not connected")
            showPrompt()
            return
        }

        Task {
            do {
                let data = try await client.readMem(address: startAddr, length: length)
                let output = Disassembler6502.disassemble(data: data, startAddress: startAddr)
                appendOutput(output)
            } catch {
                appendOutput("Error: \(error.localizedDescription)")
            }
            showPrompt()
        }
    }

    private func commandHunt(args: [String]) {
        guard args.count >= 3,
              let startAddr = parseHex(args[0]),
              let endAddr = parseHex(args[1]) else {
            appendOutput("Usage: h <start> <end> <byte1> [byte2] ...")
            showPrompt()
            return
        }

        let pattern = args[2...].compactMap { UInt8($0, radix: 16) }
        guard !pattern.isEmpty else {
            appendOutput("Error: Invalid byte pattern")
            showPrompt()
            return
        }

        guard let client = connection.apiClient else {
            appendOutput("Error: Not connected")
            showPrompt()
            return
        }

        let length = endAddr - startAddr + 1
        Task {
            do {
                let data = try await client.readMem(address: startAddr, length: length)
                var found: [Int] = []
                if data.count >= pattern.count {
                    for i in 0...(data.count - pattern.count) {
                        var match = true
                        for j in 0..<pattern.count {
                            if data[i + j] != pattern[j] { match = false; break }
                        }
                        if match { found.append(startAddr + i) }
                    }
                }

                if found.isEmpty {
                    appendOutput("Pattern not found.")
                } else {
                    let addrs = found.map { String(format: "$%04X", $0) }.joined(separator: " ")
                    appendOutput("Found at: \(addrs)")
                }
            } catch {
                appendOutput("Error: \(error.localizedDescription)")
            }
            showPrompt()
        }
    }

    private func commandFill(args: [String]) {
        guard args.count >= 3,
              let startAddr = parseHex(args[0]),
              let endAddr = parseHex(args[1]),
              let fillByte = UInt8(args[2], radix: 16) else {
            appendOutput("Usage: f <start> <end> <byte>")
            showPrompt()
            return
        }

        guard let client = connection.apiClient else {
            appendOutput("Error: Not connected")
            showPrompt()
            return
        }

        let length = endAddr - startAddr + 1
        let data = Data(repeating: fillByte, count: length)

        Task {
            do {
                try await client.writeMem(address: startAddr, data: data)
                appendOutput("Filled \(String(format: "$%04X-$%04X", startAddr, endAddr)) with \(String(format: "$%02X", fillByte))")
            } catch {
                appendOutput("Error: \(error.localizedDescription)")
            }
            showPrompt()
        }
    }

    private func commandReadByte(args: [String]) {
        guard let addr = parseHex(args.first) else {
            appendOutput("Usage: r <addr>")
            showPrompt()
            return
        }

        guard let client = connection.apiClient else {
            appendOutput("Error: Not connected")
            showPrompt()
            return
        }

        Task {
            do {
                let data = try await client.readMem(address: addr, length: 1)
                if let byte = data.first {
                    appendOutput(String(format: "$%04X = $%02X (%d)", addr, byte, byte))
                }
            } catch {
                appendOutput("Error: \(error.localizedDescription)")
            }
            showPrompt()
        }
    }

    private func commandWriteByte(args: [String]) {
        guard args.count >= 2,
              let addr = parseHex(args[0]),
              let byte = UInt8(args[1], radix: 16) else {
            appendOutput("Usage: w <addr> <byte>")
            showPrompt()
            return
        }

        guard let client = connection.apiClient else {
            appendOutput("Error: Not connected")
            showPrompt()
            return
        }

        Task {
            do {
                try await client.writeMemHex(address: addr, dataHex: String(format: "%02X", byte))
                appendOutput(String(format: "Wrote $%02X to $%04X", byte, addr))
            } catch {
                appendOutput("Error: \(error.localizedDescription)")
            }
            showPrompt()
        }
    }

    // MARK: - Helpers

    private func parseHex(_ str: String?) -> Int? {
        guard let str, !str.isEmpty else { return nil }
        let cleaned = str.hasPrefix("$") ? String(str.dropFirst()) : str
        return Int(cleaned, radix: 16)
    }
}

// MARK: - 6502 Disassembler

enum Disassembler6502 {
    static func disassemble(data: Data, startAddress: Int) -> String {
        var output = ""
        var pc = 0

        while pc < data.count {
            let addr = startAddress + pc
            let opcode = data[pc]
            let (mnemonic, mode, bytes) = decode(opcode)

            var line = String(format: "%04X: ", addr)
            for i in 0..<bytes {
                if pc + i < data.count {
                    line += String(format: "%02X ", data[pc + i])
                }
            }
            line = line.padding(toLength: 18, withPad: " ", startingAt: 0)
            line += mnemonic

            if bytes > 1 && pc + 1 < data.count {
                let lo = data[pc + 1]
                let hi = (bytes == 3 && pc + 2 < data.count) ? data[pc + 2] : 0
                line += " " + formatOperand(mode: mode, lo: lo, hi: hi, pc: addr)
            }

            output += line + "\n"
            pc += bytes
        }
        return output
    }

    private enum Mode {
        case imp, acc, imm, zp, zpx, zpy, abs, abx, aby, ind, izx, izy, rel
    }

    private static func formatOperand(mode: Mode, lo: UInt8, hi: UInt8, pc: Int) -> String {
        let word = UInt16(hi) << 8 | UInt16(lo)
        switch mode {
        case .imm: return String(format: "#$%02X", lo)
        case .zp:  return String(format: "$%02X", lo)
        case .zpx: return String(format: "$%02X,X", lo)
        case .zpy: return String(format: "$%02X,Y", lo)
        case .abs: return String(format: "$%04X", word)
        case .abx: return String(format: "$%04X,X", word)
        case .aby: return String(format: "$%04X,Y", word)
        case .ind: return String(format: "($%04X)", word)
        case .izx: return String(format: "($%02X,X)", lo)
        case .izy: return String(format: "($%02X),Y", lo)
        case .rel:
            let target = pc + 2 + Int(Int8(bitPattern: lo))
            return String(format: "$%04X", target & 0xFFFF)
        case .imp, .acc: return ""
        }
    }

    private static func decode(_ op: UInt8) -> (String, Mode, Int) {
        switch op {
        case 0x00: return ("BRK", .imp, 1); case 0xEA: return ("NOP", .imp, 1)
        case 0xA9: return ("LDA", .imm, 2); case 0xA5: return ("LDA", .zp, 2)
        case 0xB5: return ("LDA", .zpx, 2); case 0xAD: return ("LDA", .abs, 3)
        case 0xBD: return ("LDA", .abx, 3); case 0xB9: return ("LDA", .aby, 3)
        case 0xA1: return ("LDA", .izx, 2); case 0xB1: return ("LDA", .izy, 2)
        case 0xA2: return ("LDX", .imm, 2); case 0xA6: return ("LDX", .zp, 2)
        case 0xB6: return ("LDX", .zpy, 2); case 0xAE: return ("LDX", .abs, 3)
        case 0xBE: return ("LDX", .aby, 3)
        case 0xA0: return ("LDY", .imm, 2); case 0xA4: return ("LDY", .zp, 2)
        case 0xB4: return ("LDY", .zpx, 2); case 0xAC: return ("LDY", .abs, 3)
        case 0xBC: return ("LDY", .abx, 3)
        case 0x85: return ("STA", .zp, 2); case 0x95: return ("STA", .zpx, 2)
        case 0x8D: return ("STA", .abs, 3); case 0x9D: return ("STA", .abx, 3)
        case 0x99: return ("STA", .aby, 3); case 0x81: return ("STA", .izx, 2)
        case 0x91: return ("STA", .izy, 2)
        case 0x86: return ("STX", .zp, 2); case 0x96: return ("STX", .zpy, 2)
        case 0x8E: return ("STX", .abs, 3)
        case 0x84: return ("STY", .zp, 2); case 0x94: return ("STY", .zpx, 2)
        case 0x8C: return ("STY", .abs, 3)
        case 0xAA: return ("TAX", .imp, 1); case 0xA8: return ("TAY", .imp, 1)
        case 0x8A: return ("TXA", .imp, 1); case 0x98: return ("TYA", .imp, 1)
        case 0xBA: return ("TSX", .imp, 1); case 0x9A: return ("TXS", .imp, 1)
        case 0x48: return ("PHA", .imp, 1); case 0x68: return ("PLA", .imp, 1)
        case 0x08: return ("PHP", .imp, 1); case 0x28: return ("PLP", .imp, 1)
        case 0x69: return ("ADC", .imm, 2); case 0x65: return ("ADC", .zp, 2)
        case 0x75: return ("ADC", .zpx, 2); case 0x6D: return ("ADC", .abs, 3)
        case 0x7D: return ("ADC", .abx, 3); case 0x79: return ("ADC", .aby, 3)
        case 0x61: return ("ADC", .izx, 2); case 0x71: return ("ADC", .izy, 2)
        case 0xE9: return ("SBC", .imm, 2); case 0xE5: return ("SBC", .zp, 2)
        case 0xF5: return ("SBC", .zpx, 2); case 0xED: return ("SBC", .abs, 3)
        case 0xFD: return ("SBC", .abx, 3); case 0xF9: return ("SBC", .aby, 3)
        case 0xE1: return ("SBC", .izx, 2); case 0xF1: return ("SBC", .izy, 2)
        case 0xC9: return ("CMP", .imm, 2); case 0xC5: return ("CMP", .zp, 2)
        case 0xD5: return ("CMP", .zpx, 2); case 0xCD: return ("CMP", .abs, 3)
        case 0xDD: return ("CMP", .abx, 3); case 0xD9: return ("CMP", .aby, 3)
        case 0xC1: return ("CMP", .izx, 2); case 0xD1: return ("CMP", .izy, 2)
        case 0xE0: return ("CPX", .imm, 2); case 0xE4: return ("CPX", .zp, 2)
        case 0xEC: return ("CPX", .abs, 3)
        case 0xC0: return ("CPY", .imm, 2); case 0xC4: return ("CPY", .zp, 2)
        case 0xCC: return ("CPY", .abs, 3)
        case 0xE6: return ("INC", .zp, 2); case 0xF6: return ("INC", .zpx, 2)
        case 0xEE: return ("INC", .abs, 3); case 0xFE: return ("INC", .abx, 3)
        case 0xC6: return ("DEC", .zp, 2); case 0xD6: return ("DEC", .zpx, 2)
        case 0xCE: return ("DEC", .abs, 3); case 0xDE: return ("DEC", .abx, 3)
        case 0xE8: return ("INX", .imp, 1); case 0xC8: return ("INY", .imp, 1)
        case 0xCA: return ("DEX", .imp, 1); case 0x88: return ("DEY", .imp, 1)
        case 0x29: return ("AND", .imm, 2); case 0x25: return ("AND", .zp, 2)
        case 0x35: return ("AND", .zpx, 2); case 0x2D: return ("AND", .abs, 3)
        case 0x3D: return ("AND", .abx, 3); case 0x39: return ("AND", .aby, 3)
        case 0x21: return ("AND", .izx, 2); case 0x31: return ("AND", .izy, 2)
        case 0x09: return ("ORA", .imm, 2); case 0x05: return ("ORA", .zp, 2)
        case 0x15: return ("ORA", .zpx, 2); case 0x0D: return ("ORA", .abs, 3)
        case 0x1D: return ("ORA", .abx, 3); case 0x19: return ("ORA", .aby, 3)
        case 0x01: return ("ORA", .izx, 2); case 0x11: return ("ORA", .izy, 2)
        case 0x49: return ("EOR", .imm, 2); case 0x45: return ("EOR", .zp, 2)
        case 0x55: return ("EOR", .zpx, 2); case 0x4D: return ("EOR", .abs, 3)
        case 0x5D: return ("EOR", .abx, 3); case 0x59: return ("EOR", .aby, 3)
        case 0x41: return ("EOR", .izx, 2); case 0x51: return ("EOR", .izy, 2)
        case 0x0A: return ("ASL", .acc, 1); case 0x06: return ("ASL", .zp, 2)
        case 0x16: return ("ASL", .zpx, 2); case 0x0E: return ("ASL", .abs, 3)
        case 0x1E: return ("ASL", .abx, 3)
        case 0x4A: return ("LSR", .acc, 1); case 0x46: return ("LSR", .zp, 2)
        case 0x56: return ("LSR", .zpx, 2); case 0x4E: return ("LSR", .abs, 3)
        case 0x5E: return ("LSR", .abx, 3)
        case 0x2A: return ("ROL", .acc, 1); case 0x26: return ("ROL", .zp, 2)
        case 0x36: return ("ROL", .zpx, 2); case 0x2E: return ("ROL", .abs, 3)
        case 0x3E: return ("ROL", .abx, 3)
        case 0x6A: return ("ROR", .acc, 1); case 0x66: return ("ROR", .zp, 2)
        case 0x76: return ("ROR", .zpx, 2); case 0x6E: return ("ROR", .abs, 3)
        case 0x7E: return ("ROR", .abx, 3)
        case 0x10: return ("BPL", .rel, 2); case 0x30: return ("BMI", .rel, 2)
        case 0x50: return ("BVC", .rel, 2); case 0x70: return ("BVS", .rel, 2)
        case 0x90: return ("BCC", .rel, 2); case 0xB0: return ("BCS", .rel, 2)
        case 0xD0: return ("BNE", .rel, 2); case 0xF0: return ("BEQ", .rel, 2)
        case 0x4C: return ("JMP", .abs, 3); case 0x6C: return ("JMP", .ind, 3)
        case 0x20: return ("JSR", .abs, 3); case 0x60: return ("RTS", .imp, 1)
        case 0x40: return ("RTI", .imp, 1)
        case 0x18: return ("CLC", .imp, 1); case 0x38: return ("SEC", .imp, 1)
        case 0x58: return ("CLI", .imp, 1); case 0x78: return ("SEI", .imp, 1)
        case 0xB8: return ("CLV", .imp, 1); case 0xD8: return ("CLD", .imp, 1)
        case 0xF8: return ("SED", .imp, 1)
        case 0x24: return ("BIT", .zp, 2); case 0x2C: return ("BIT", .abs, 3)
        default: return ("???", .imp, 1)
        }
    }
}
