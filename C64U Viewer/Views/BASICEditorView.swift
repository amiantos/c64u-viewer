// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.

import AppKit

// MARK: - Syntax Highlighting

struct BASICSyntaxHighlighter {
    static let defaultFont = NSFont.monospacedSystemFont(ofSize: 13, weight: .regular)

    static let defaultColor = NSColor.textColor
    static let keywordColor = NSColor.systemBlue
    static let stringColor = NSColor.systemGreen
    static let numberColor = NSColor.systemOrange
    static let lineNumberColor = NSColor.systemYellow
    static let commentColor = NSColor.systemGray
    static let specialCodeColor = NSColor.systemPink
    static let errorColor = NSColor.systemRed

    static func highlight(_ text: String) -> NSAttributedString {
        let result = NSMutableAttributedString()

        let lines = text.split(separator: "\n", omittingEmptySubsequences: false)
        for (index, line) in lines.enumerated() {
            if index > 0 {
                result.append(NSAttributedString(string: "\n", attributes: defaultAttributes))
            }
            result.append(highlightLine(String(line)))
        }

        return result
    }

    private static var defaultAttributes: [NSAttributedString.Key: Any] {
        [.font: defaultFont, .foregroundColor: defaultColor]
    }

    private static func highlightLine(_ line: String) -> NSAttributedString {
        let result = NSMutableAttributedString()
        var remaining = line[line.startIndex...]

        // Skip leading whitespace
        let whitespace = remaining.prefix(while: { $0 == " " || $0 == "\t" })
        if !whitespace.isEmpty {
            result.append(styled(String(whitespace), color: defaultColor))
            remaining = remaining[whitespace.endIndex...]
        }

        // Parse line number
        let digits = remaining.prefix(while: { $0.isNumber })
        if !digits.isEmpty {
            result.append(styled(String(digits), color: lineNumberColor))
            remaining = remaining[digits.endIndex...]
        }

        // Skip space after line number
        let space = remaining.prefix(while: { $0 == " " })
        if !space.isEmpty {
            result.append(styled(String(space), color: defaultColor))
            remaining = remaining[space.endIndex...]
        }

        // Tokenize the rest
        var inQuotes = false
        var inRemark = false
        let lowered = remaining.lowercased()
        var lowIdx = lowered.startIndex

        while remaining.startIndex < remaining.endIndex {
            if inRemark {
                result.append(styled(String(remaining), color: commentColor))
                break
            }

            if inQuotes {
                let char = remaining[remaining.startIndex]
                if char == "\"" {
                    result.append(styled("\"", color: stringColor))
                    remaining = remaining[remaining.index(after: remaining.startIndex)...]
                    lowIdx = lowered.index(after: lowIdx)
                    inQuotes = false
                } else if char == "{" {
                    if let (match, len) = matchSpecialCode(lowered[lowIdx...]) {
                        let origText = String(remaining[remaining.startIndex..<remaining.index(remaining.startIndex, offsetBy: len)])
                        result.append(styled(origText, color: specialCodeColor))
                        remaining = remaining[remaining.index(remaining.startIndex, offsetBy: len)...]
                        lowIdx = lowered.index(lowIdx, offsetBy: len)
                        _ = match
                    } else {
                        if let closeIdx = remaining[remaining.index(after: remaining.startIndex)...].firstIndex(of: "}") {
                            let endIdx = remaining.index(after: closeIdx)
                            result.append(styled(String(remaining[remaining.startIndex..<endIdx]), color: errorColor))
                            let len = remaining.distance(from: remaining.startIndex, to: endIdx)
                            remaining = remaining[endIdx...]
                            lowIdx = lowered.index(lowIdx, offsetBy: len)
                        } else {
                            result.append(styled(String(remaining[remaining.startIndex...remaining.startIndex]), color: stringColor))
                            remaining = remaining[remaining.index(after: remaining.startIndex)...]
                            lowIdx = lowered.index(after: lowIdx)
                        }
                    }
                } else {
                    result.append(styled(String(char), color: stringColor))
                    remaining = remaining[remaining.index(after: remaining.startIndex)...]
                    lowIdx = lowered.index(after: lowIdx)
                }
                continue
            }

            // Not in quotes — try to match keyword
            let lowRemaining = lowered[lowIdx...]
            if let (keyword, _) = matchKeyword(lowRemaining) {
                let len = keyword.count
                let origText = String(remaining[remaining.startIndex..<remaining.index(remaining.startIndex, offsetBy: len)])
                if keyword == "rem" {
                    result.append(styled(origText, color: commentColor))
                    remaining = remaining[remaining.index(remaining.startIndex, offsetBy: len)...]
                    lowIdx = lowered.index(lowIdx, offsetBy: len)
                    inRemark = true
                } else {
                    result.append(styled(origText, color: keywordColor))
                    remaining = remaining[remaining.index(remaining.startIndex, offsetBy: len)...]
                    lowIdx = lowered.index(lowIdx, offsetBy: len)
                }
                continue
            }

            let char = remaining[remaining.startIndex]

            if char == "\"" {
                inQuotes = true
                result.append(styled("\"", color: stringColor))
                remaining = remaining[remaining.index(after: remaining.startIndex)...]
                lowIdx = lowered.index(after: lowIdx)
                continue
            }

            if char.isNumber {
                let numChars = remaining.prefix(while: { $0.isNumber || $0 == "." })
                result.append(styled(String(numChars), color: numberColor))
                let len = numChars.count
                remaining = remaining[remaining.index(remaining.startIndex, offsetBy: len)...]
                lowIdx = lowered.index(lowIdx, offsetBy: len)
                continue
            }

            result.append(styled(String(char), color: defaultColor))
            remaining = remaining[remaining.index(after: remaining.startIndex)...]
            lowIdx = lowered.index(after: lowIdx)
        }

        return result
    }

    private static func styled(_ text: String, color: NSColor) -> NSAttributedString {
        NSAttributedString(string: text, attributes: [
            .font: defaultFont,
            .foregroundColor: color,
        ])
    }

    private static func matchKeyword(_ s: Substring) -> (String, UInt8)? {
        for (keyword, token) in BASICTokenizer.tokens where keyword.count > 1 {
            if s.hasPrefix(keyword) {
                let afterIdx = s.index(s.startIndex, offsetBy: keyword.count)
                if afterIdx < s.endIndex {
                    let next = s[afterIdx]
                    if keyword.hasSuffix("$") || keyword.hasSuffix("(") {
                        return (keyword, token)
                    }
                    if next.isLetter {
                        continue
                    }
                }
                return (keyword, token)
            }
        }
        return nil
    }

    private static func matchSpecialCode(_ s: Substring) -> (String, Int)? {
        for (code, _) in BASICTokenizer.specialCodes {
            if s.hasPrefix(code) {
                return (code, code.count)
            }
        }
        return nil
    }
}

// MARK: - BASIC Editor NSTextView Helper

final class BASICEditorTextViewManager: NSObject, NSTextViewDelegate {
    var onTextChange: ((String) -> Void)?
    private(set) var textView: NSTextView!
    private var isUpdating = false

    func createScrollView() -> NSScrollView {
        let scrollView = NSTextView.scrollableTextView()
        let tv = scrollView.documentView as! NSTextView

        tv.isRichText = false
        tv.allowsUndo = true
        tv.isAutomaticQuoteSubstitutionEnabled = false
        tv.isAutomaticDashSubstitutionEnabled = false
        tv.isAutomaticTextReplacementEnabled = false
        tv.isAutomaticSpellingCorrectionEnabled = false
        tv.isAutomaticTextCompletionEnabled = false
        tv.font = BASICSyntaxHighlighter.defaultFont
        tv.backgroundColor = NSColor(white: 0.1, alpha: 1.0)
        tv.insertionPointColor = .white
        tv.textContainerInset = NSSize(width: 8, height: 8)
        tv.delegate = self

        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = false
        scrollView.drawsBackground = true
        scrollView.backgroundColor = NSColor(white: 0.1, alpha: 1.0)
        scrollView.borderType = .noBorder

        textView = tv
        return scrollView
    }

    func setText(_ text: String) {
        guard let textView, textView.string != text else { return }
        isUpdating = true
        let selectedRanges = textView.selectedRanges
        textView.string = text
        applyHighlighting()
        textView.selectedRanges = selectedRanges
        isUpdating = false
    }

    func textDidChange(_ notification: Notification) {
        guard let textView = notification.object as? NSTextView, !isUpdating else { return }
        onTextChange?(textView.string)
        applyHighlighting()
    }

    private func applyHighlighting() {
        guard let textView else { return }
        let highlighted = BASICSyntaxHighlighter.highlight(textView.string)

        isUpdating = true
        let selectedRanges = textView.selectedRanges
        textView.textStorage?.beginEditing()
        textView.textStorage?.setAttributedString(highlighted)
        textView.textStorage?.endEditing()
        textView.selectedRanges = selectedRanges
        isUpdating = false
    }
}
