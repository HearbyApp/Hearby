import Foundation

/// Rewrites Markdown and code-heavy text — typically an AI assistant's reply —
/// into something that sounds right read aloud.
///
/// Plain prose passes through almost untouched. The work is in what a reader's
/// eye skips but a voice would otherwise pronounce: code fences, backticks,
/// asterisks, table pipes, URLs, file paths, camelCase identifiers, and the
/// glyphs terminal tools such as Claude Code print (⏺ ⎿ box drawing).
///
/// `SpeechController.speak(_:)` runs this once, before `TextChunker`, so every
/// engine hears the same text. The rules are conservative: anything ambiguous
/// is left for the voice to read rather than silently dropped. Arithmetic like
/// `5 * 3` or `a*b` survives because emphasis needs the marker to hug a word
/// on both sides and sit outside other word characters.
enum SpeechTextCleaner {

    static func clean(_ text: String) -> String {
        let normalized = replaceGlyphs(
            text.replacingOccurrences(of: "\r\n", with: "\n")
                .replacingOccurrences(of: "\r", with: "\n"))

        var output: [String] = []
        var lines = normalized.components(separatedBy: "\n")[...]
        while let line = lines.popFirst() {
            if let fence = Fence(line) {
                // An unclosed fence runs to the end of the text, the same way
                // Markdown renders it.
                var body: [String] = []
                while let next = lines.popFirst(), !fence.isClosed(by: next) {
                    body.append(next)
                }
                if let summary = fence.summary(of: body) { output.append(summary) }
            } else {
                output.append(cleanLine(line))
            }
        }
        return tidy(output.joined(separator: "\n"))
    }

    // MARK: - Block level

    /// A fenced code block is announced, never read: hearing forty lines of
    /// Swift spelled out symbol by symbol is useless, while "Code block: 40
    /// lines of Swift" tells the listener what they skipped.
    private struct Fence {
        let marker: String
        let language: String

        init?(_ line: String) {
            guard let groups = Pattern.fence.captures(in: line.trimmingCharacters(in: .whitespaces))
            else { return nil }
            marker = groups[1]
            language = groups[2].lowercased().trimmingCharacters(in: CharacterSet(charactersIn: "{}."))
        }

        func isClosed(by line: String) -> Bool {
            line.trimmingCharacters(in: .whitespaces).hasPrefix(marker)
        }

        func summary(of body: [String]) -> String? {
            let count = body.filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }.count
            guard count > 0 else { return nil }
            let lines = count == 1 ? "1 line" : "\(count) lines"
            let name = SpeechTextCleaner.languageNames[language]
                ?? (language.count <= 12 && language.allSatisfy(\.isLetter) ? language : "")
            return name.isEmpty ? "Code block: \(lines)." : "Code block: \(lines) of \(name)."
        }
    }

    private static let languageNames: [String: String] = [
        "swift": "Swift", "py": "Python", "python": "Python",
        "js": "JavaScript", "javascript": "JavaScript", "jsx": "JavaScript",
        "ts": "TypeScript", "typescript": "TypeScript", "tsx": "TypeScript",
        "sh": "shell", "bash": "shell", "zsh": "shell", "shell": "shell", "console": "shell",
        "json": "JSON", "yaml": "YAML", "yml": "YAML", "toml": "TOML", "xml": "XML",
        "html": "HTML", "css": "CSS", "sql": "SQL", "go": "Go", "rust": "Rust", "rs": "Rust",
        "rb": "Ruby", "ruby": "Ruby", "java": "Java", "kotlin": "Kotlin",
        "c": "C", "cpp": "C++", "c++": "C++", "cs": "C sharp", "csharp": "C sharp",
        "md": "Markdown", "markdown": "Markdown", "diff": "diff", "dockerfile": "Dockerfile",
    ]

    private static func cleanLine(_ line: String) -> String {
        var s = line.trimmingCharacters(in: .whitespaces)
        if s.isEmpty || Pattern.horizontalRule.isMatch(s) { return "" }

        // Table rows read as comma-separated cells; the |---| row is dropped.
        if s.hasPrefix("|") {
            if Pattern.tableSeparator.isMatch(s) { return "" }
            let cells = s.split(separator: "|")
                .map { $0.trimmingCharacters(in: .whitespaces) }
                .filter { !$0.isEmpty }
                .map { cleanInline($0) }
            return terminated(cells.joined(separator: ", "))
        }

        // Headings and list items get a terminal period so the voice pauses
        // between them instead of running every bullet into one sentence.
        var isBlock = false
        if let groups = Pattern.heading.captures(in: s) { s = groups[1]; isBlock = true }
        s = Pattern.blockquote.replacing(in: s, with: "")
        if let groups = Pattern.bullet.captures(in: s) {
            s = groups[1]; isBlock = true
        } else if let groups = Pattern.numbered.captures(in: s) {
            s = "\(groups[1]): \(groups[2])"; isBlock = true
        }
        let cleaned = cleanInline(s)
        return isBlock ? terminated(cleaned) : cleaned
    }

    // MARK: - Inline

    static func cleanInline(_ text: String) -> String {
        // Inline code is spoken by its own rules. Park it behind placeholders
        // so the emphasis and HTML rules below cannot reach inside it.
        var spans: [String] = []
        var s = Pattern.keyHint.replacing(in: text, with: "")
        s = Pattern.inlineCode.replacing(in: s) { groups in
            spans.append(speakableCode(groups[1]))
            return "\u{E000}\(spans.count - 1)\u{E001}"
        }

        s = Pattern.image.replacing(in: s, with: "$1")
        s = Pattern.link.replacing(in: s, with: "$1")
        s = Pattern.autolink.replacing(in: s, with: "$1")
        // A URL reads as its host: "github.com", not forty characters of path.
        s = Pattern.url.replacing(in: s) { groups in
            groups[1].hasPrefix("www.") ? String(groups[1].dropFirst(4)) : groups[1]
        }
        s = Pattern.html.replacing(in: s, with: " ")

        s = Pattern.strongEmphasis.replacing(in: s, with: "$2")
        s = Pattern.strong.replacing(in: s, with: "$2")
        s = Pattern.emphasisStar.replacing(in: s, with: "$1")
        s = Pattern.emphasisUnderscore.replacing(in: s, with: "$1")
        s = Pattern.strikethrough.replacing(in: s, with: "$1")

        s = Pattern.forExample.replacing(in: s, with: "for example")
        s = Pattern.thatIs.replacing(in: s, with: "that is")
        s = Pattern.versus.replacing(in: s, with: "versus")
        s = Pattern.arrow.replacing(in: s, with: " to ")
        s = Pattern.doubleAmpersand.replacing(in: s, with: " and ")
        s = Pattern.approximately.replacing(in: s, with: "about ")

        s = Pattern.path.replacing(in: s) { groups in lastPathComponent(groups[0]) }
        s = splitIdentifiers(s)
        s = Pattern.leftoverMarkup.replacing(in: s, with: "")

        return Pattern.placeholder.replacing(in: s) { groups in
            Int(groups[1]).flatMap { spans.indices.contains($0) ? spans[$0] : nil } ?? ""
        }
    }

    /// `SpeechController.swift` → "Speech Controller.swift";
    /// `speak(_:)` → "speak"; `--verbose` → "verbose"; a long one-liner →
    /// "a code snippet".
    static func speakableCode(_ raw: String) -> String {
        var s = raw.trimmingCharacters(in: .whitespaces)
        if s.count > 80 { return "a code snippet" }
        if !s.contains(" "), s.contains("/") { s = lastPathComponent(s) }
        s = Pattern.callArguments.replacing(in: s, with: "")
        s = Pattern.codePunctuation.replacing(in: s, with: " ")
        s = Pattern.commandFlag.replacing(in: s, with: "")
        s = splitIdentifiers(s)
        return Pattern.spaces.replacing(in: s, with: " ").trimmingCharacters(in: .whitespaces)
    }

    private static func lastPathComponent(_ path: String) -> String {
        path.split(separator: "/").last.map(String.init) ?? path
    }

    /// Splits snake_case and camelCase so the voice says the words.
    /// "iPhone" becoming "i Phone" sounds the same aloud, so brand names
    /// are left to the rule rather than special-cased.
    private static func splitIdentifiers(_ text: String) -> String {
        var s = Pattern.snakeUnderscore.replacing(in: text, with: " ")
        s = Pattern.lowerUpper.replacing(in: s, with: " ")
        return Pattern.acronymWord.replacing(in: s, with: " ")
    }

    // MARK: - Glyphs and tidying

    private static let keyNames: [Unicode.Scalar: String] = [
        "⌘": " Command ", "⌥": " Option ", "⌃": " Control ", "⇧": " Shift ", "⚠": " Warning: ",
    ]

    /// Mac key symbols become their names; emoji, box drawing and terminal
    /// markers (⏺ ⎿ ✻) are dropped, since a voice either skips them
    /// unpredictably or reads them by their Unicode names.
    private static func replaceGlyphs(_ text: String) -> String {
        var out = String.UnicodeScalarView()
        for scalar in text.unicodeScalars {
            if let name = keyNames[scalar] {
                out.append(contentsOf: name.unicodeScalars)
            } else if !isSpeechless(scalar.value) {
                out.append(scalar)
            }
        }
        return String(out)
    }

    private static func isSpeechless(_ v: UInt32) -> Bool {
        (0x2380...0x23FF).contains(v)        // ⏺ ⎿ and other terminal markers
            || (0x2500...0x25FF).contains(v)  // box drawing, blocks, geometric shapes
            || (0x2600...0x27BF).contains(v)  // misc symbols and dingbats (✅ ✻ ✓)
            || (0x1F000...0x1FAFF).contains(v) // emoji
            || v == 0xFE0F || v == 0x200D || v == 0x20E3
    }

    private static func tidy(_ text: String) -> String {
        var s = Pattern.spaces.replacing(in: text, with: " ")
        s = Pattern.spaceBeforePunctuation.replacing(in: s, with: "$1")
        s = s.components(separatedBy: "\n")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .joined(separator: "\n")
        return Pattern.extraBlankLines.replacing(in: s, with: "\n\n")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func terminated(_ text: String) -> String {
        let s = text.trimmingCharacters(in: .whitespaces)
        guard let last = s.last else { return "" }
        return ".!?:;,".contains(last) ? s : s + "."
    }
}

// MARK: - Patterns

/// Compiled once. A typo in a pattern traps at first use, which the unit
/// tests reach, so it can never ship silently.
private enum Pattern {
    static let fence = rx(#"^(`{3,}|~{3,})\s*([^\s`]*)"#)
    static let horizontalRule = rx(#"^([-*_])(\s*\1){2,}$"#)
    static let tableSeparator = rx(#"^\|?\s*:?-{2,}:?\s*(\|\s*:?-{2,}:?\s*)*\|?$"#)
    static let heading = rx(#"^#{1,6}\s+(.*?)\s*#*$"#)
    static let blockquote = rx(#"^(>\s?)+"#)
    static let bullet = rx(#"^[-*+•]\s+(?:\[[ xX]\]\s+)?(.*)$"#)
    static let numbered = rx(#"^(\d{1,3})[.)]\s+(.*)$"#)

    static let keyHint = rx(#"\s*\((?:ctrl|cmd|shift|alt|option)\+\w+ to [^)]*\)"#, .caseInsensitive)
    static let inlineCode = rx(#"`([^`\n]+)`"#)
    static let image = rx(#"!\[([^\]]*)\]\([^)]*\)"#)
    static let link = rx(#"\[([^\]]+)\]\([^)]*\)"#)
    static let autolink = rx(#"<(https?://[^>\s]+)>"#)
    static let url = rx(#"https?://([^\s/<>()\[\]]+)[^\s<>()\[\]]*?(?=[.,;:!?'"]*(?:\s|$))"#)
    static let html = rx(#"</?[A-Za-z][A-Za-z0-9-]*(?:\s[^<>]*)?/?>"#)

    static let strongEmphasis = rx(#"(\*\*\*|___)(?=\S)(.+?)(?<=\S)\1"#)
    static let strong = rx(#"(\*\*|__)(?=\S)(.+?)(?<=\S)\1"#)
    static let emphasisStar = rx(#"(?<![\w*])\*(?=\S)(.+?)(?<=\S)\*(?![\w*])"#)
    static let emphasisUnderscore = rx(#"(?<![\w_])_(?=\S)(.+?)(?<=\S)_(?![\w_])"#)
    static let strikethrough = rx(#"~~(?=\S)(.+?)(?<=\S)~~"#)

    static let forExample = rx(#"\be\.g\.,?"#, .caseInsensitive)
    static let thatIs = rx(#"\bi\.e\.,?"#, .caseInsensitive)
    static let versus = rx(#"\bvs\.?(?=\s)"#, .caseInsensitive)
    static let arrow = rx(#"\s*(?:->|=>|→|⇒|⟶)\s*"#)
    static let doubleAmpersand = rx(#"\s*&&\s*"#)
    static let approximately = rx(#"(?:~|≈)(?=\d)"#)

    static let path = rx(#"(?<![\w/.])(?:~|\.{1,2})?(?:/[\w.@+-]+){2,}/?"#)
    static let snakeUnderscore = rx(#"(?<=[A-Za-z0-9])_(?=[A-Za-z0-9])"#)
    static let lowerUpper = rx(#"(?<=[a-z])(?=[A-Z])"#)
    static let acronymWord = rx(#"(?<=[A-Z])(?=[A-Z][a-z])"#)
    static let callArguments = rx(#"\([^()\s]{0,30}\)"#)
    static let codePunctuation = rx(#"[{}\[\]<>;$\\|`"'*#]"#)
    static let commandFlag = rx(#"(?<!\S)-{1,2}(?=\w)"#)
    static let leftoverMarkup = rx(#"`+|\*{2,}"#)
    static let placeholder = rx("\u{E000}(\\d+)\u{E001}")

    static let spaces = rx(#"[ \t]{2,}"#)
    static let spaceBeforePunctuation = rx(#"[ \t]+([.,;:!?])"#)
    static let extraBlankLines = rx(#"\n{3,}"#)

    private static func rx(_ pattern: String, _ options: NSRegularExpression.Options = []) -> NSRegularExpression {
        try! NSRegularExpression(pattern: pattern, options: options)
    }
}

private extension NSRegularExpression {
    func isMatch(_ s: String) -> Bool {
        firstMatch(in: s, range: NSRange(s.startIndex..., in: s)) != nil
    }

    func captures(in s: String) -> [String]? {
        guard let match = firstMatch(in: s, range: NSRange(s.startIndex..., in: s)) else { return nil }
        return groups(of: match, in: s as NSString)
    }

    func replacing(in s: String, with template: String) -> String {
        stringByReplacingMatches(in: s, range: NSRange(s.startIndex..., in: s), withTemplate: template)
    }

    func replacing(in s: String, _ transform: ([String]) -> String) -> String {
        let ns = s as NSString
        var result = ""
        var cursor = 0
        for match in matches(in: s, range: NSRange(location: 0, length: ns.length)) {
            result += ns.substring(with: NSRange(location: cursor, length: match.range.location - cursor))
            result += transform(groups(of: match, in: ns))
            cursor = match.range.location + match.range.length
        }
        return result + ns.substring(from: cursor)
    }

    private func groups(of match: NSTextCheckingResult, in ns: NSString) -> [String] {
        (0..<match.numberOfRanges).map { i in
            let range = match.range(at: i)
            return range.location == NSNotFound ? "" : ns.substring(with: range)
        }
    }
}
