// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.

import Foundation

struct BASICTokenizer {

    // MARK: - BASIC V2 Token Table

    /// C64 BASIC V2 keywords mapped to their token byte values.
    /// Ordered longest-first so greedy matching works correctly.
    static let tokens: [(String, UInt8)] = [
        ("restore", 140), ("input#", 132), ("return", 142),
        ("verify", 149), ("print#", 152), ("right$", 201),
        ("input", 133), ("gosub", 141), ("print", 153),
        ("close", 160), ("left$", 200),
        ("next", 130), ("data", 131), ("read", 135),
        ("goto", 137), ("stop", 144), ("wait", 146),
        ("load", 147), ("save", 148), ("poke", 151),
        ("cont", 154), ("list", 155), ("open", 159),
        ("tab(", 163), ("spc(", 166), ("then", 167),
        ("step", 169), ("peek", 194), ("str$", 196),
        ("chr$", 199), ("mid$", 202),
        ("end", 128), ("for", 129), ("dim", 134),
        ("let", 136), ("run", 138), ("rem", 143),
        ("def", 150), ("clr", 156), ("cmd", 157),
        ("sys", 158), ("get", 161), ("new", 162),
        ("not", 168), ("and", 175), ("sgn", 180),
        ("int", 181), ("abs", 182), ("usr", 183),
        ("fre", 184), ("pos", 185), ("sqr", 186),
        ("rnd", 187), ("log", 188), ("exp", 189),
        ("cos", 190), ("sin", 191), ("tan", 192),
        ("atn", 193), ("len", 195), ("val", 197),
        ("asc", 198),
        ("if", 139), ("on", 145), ("to", 164),
        ("fn", 165), ("or", 176), ("go", 203),
        ("+", 170), ("-", 171), ("*", 172),
        ("/", 173), ("^", 174), (">", 177),
        ("=", 178), ("<", 179),
    ]

    // MARK: - PETSCII Special Escape Codes

    /// Curly-brace escape sequences for control characters and colors,
    /// matching the convention used by CBM prg Studio and Petcat.
    static let specialCodes: [(String, UInt8)] = [
        ("{rvs off}", 0x92), ("{rvs on}", 0x12),
        ("{up}", 0x91), ("{down}", 0x11),
        ("{left}", 0x9D), ("{rght}", 0x1D),
        ("{right}", 0x1D),
        ("{clr}", 0x93), ("{clear}", 0x93), ("{home}", 0x13),
        ("{blk}", 0x90), ("{wht}", 0x05),
        ("{red}", 0x1C), ("{cyn}", 0x9F),
        ("{pur}", 0x9C), ("{grn}", 0x1E),
        ("{blu}", 0x1F), ("{yel}", 0x9E),
        ("{org}", 0x81), ("{brn}", 0x95),
        ("{lred}", 0x96), ("{dgry}", 0x97),
        ("{mgry}", 0x98), ("{lgrn}", 0x99),
        ("{lblu}", 0x9A), ("{lgry}", 0x9B),
    ]

    /// All known special code names (without braces) for validation/highlighting.
    static let specialCodeNames: Set<String> = {
        Set(specialCodes.map { code in
            String(code.0.dropFirst().dropLast())
        })
    }()

    /// All known BASIC keyword strings for highlighting.
    static let keywordSet: Set<String> = {
        Set(tokens.filter { $0.0.count > 1 }.map { $0.0 })
    }()

    // MARK: - Tokenization

    struct TokenizeError: LocalizedError {
        let message: String
        var errorDescription: String? { message }
    }

    /// Tokenize a complete BASIC program and return the binary data
    /// ready to write to C64 memory at $0801.
    /// Returns `(programData, endAddress)` where endAddress is the
    /// value to write to $002D (BASIC variable start pointer).
    static func tokenize(program: String) throws -> (Data, UInt16) {
        let lines = program
            .split(separator: "\n", omittingEmptySubsequences: false)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
            .map { $0.lowercased() }

        guard !lines.isEmpty else {
            throw TokenizeError(message: "No BASIC lines to tokenize")
        }

        var addr: UInt16 = 2049 // $0801
        var tokenizedLines: [(lineNumber: UInt16, bytes: [UInt8], addr: UInt16)] = []

        for line in lines {
            let (lineNumber, bytes) = try tokenizeLine(line)
            tokenizedLines.append((lineNumber, bytes, addr))
            // Each line: 2 bytes next-addr + 2 bytes line number + bytes + 1 null terminator
            addr += UInt16(bytes.count + 5)
        }

        // Build binary output
        var data = Data()
        for i in 0..<tokenizedLines.count {
            let nextAddr: UInt16
            if i + 1 < tokenizedLines.count {
                nextAddr = tokenizedLines[i + 1].addr
            } else {
                // Last line: next pointer is addr of this line + length
                nextAddr = tokenizedLines[i].addr + UInt16(tokenizedLines[i].bytes.count + 5)
            }

            // Next line pointer (little-endian)
            data.append(UInt8(nextAddr & 0xFF))
            data.append(UInt8(nextAddr >> 8))
            // Line number (little-endian)
            data.append(UInt8(tokenizedLines[i].lineNumber & 0xFF))
            data.append(UInt8(tokenizedLines[i].lineNumber >> 8))
            // Tokenized bytes
            data.append(contentsOf: tokenizedLines[i].bytes)
            // Null terminator
            data.append(0x00)
        }

        // Program end marker (two zero bytes)
        data.append(0x00)
        data.append(0x00)

        let endAddr = addr + 2
        return (data, endAddr)
    }

    /// Tokenize a single BASIC line, returning (lineNumber, tokenizedBytes).
    private static func tokenizeLine(_ line: String) throws -> (UInt16, [UInt8]) {
        var remaining = line.trimmingCharacters(in: .whitespaces)

        // Parse line number
        var numberStr = ""
        while let first = remaining.first, first.isNumber {
            numberStr.append(first)
            remaining = String(remaining.dropFirst())
        }
        guard let lineNumber = UInt16(numberStr) else {
            throw TokenizeError(message: "Invalid or missing line number: \(line)")
        }
        remaining = remaining.trimmingCharacters(in: .whitespaces)

        // Tokenize the rest
        var bytes: [UInt8] = []
        var inQuotes = false
        var inRemark = false

        while !remaining.isEmpty {
            let (byte, rest) = try scanToken(remaining, tokenize: !(inQuotes || inRemark))
            bytes.append(byte)
            remaining = rest

            if byte == UInt8(ascii: "\"") {
                inQuotes.toggle()
            }
            if byte == 143 { // REM token
                inRemark = true
            }
        }

        return (lineNumber, bytes)
    }

    /// Scan one token or character from the front of the string.
    private static func scanToken(_ s: String, tokenize: Bool) throws -> (UInt8, String) {
        if tokenize {
            for (keyword, value) in tokens {
                if s.hasPrefix(keyword) {
                    return (value, String(s.dropFirst(keyword.count)))
                }
            }
        }

        // Check for {special} escape codes
        if s.first == "{" {
            for (code, value) in specialCodes {
                if s.hasPrefix(code) {
                    return (value, String(s.dropFirst(code.count)))
                }
            }
            throw TokenizeError(message: "Unknown escape code near: \(String(s.prefix(20)))")
        }

        // Regular character → PETSCII
        let char = s.first!
        let byte = asciiToPETSCII(char)
        return (byte, String(s.dropFirst()))
    }

    /// Convert an ASCII/Unicode character to its PETSCII equivalent.
    private static func asciiToPETSCII(_ char: Character) -> UInt8 {
        let o = char.asciiValue ?? 0

        // Characters at or below '@', plus '[' and ']' pass through
        if o <= 0x40 || o == 0x5B || o == 0x5D {
            return o
        }
        // Lowercase a-z
        if o >= 0x61 && o <= 0x7A {
            return o - 0x61 + 0x41
        }
        // Uppercase A-Z → shifted PETSCII
        if o >= 0x41 && o <= 0x5A {
            return o - 0x41 + 0xC1
        }

        return o
    }
}
