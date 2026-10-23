import Foundation

/// Rewrites digits as English words before Kokoro sees them.
///
/// The multilingual bundle's only number handling is its Chinese
/// text-normalization FSTs, which turn "2026" into Chinese numerals that are
/// then spoken in Mandarin by whatever English voice is selected. Spelling the
/// numbers out here leaves the model nothing to interpret. System voices do
/// their own number reading and never go through this.
enum NumberSpeller {

    static func spellOut(_ text: String) -> String {
        let withTimes = replace(time, in: text) { groups in
            guard let hour = Int(groups[1]), let minute = Int(groups[2]) else { return groups[0] }
            if minute == 0 { return "\(cardinal(hour)) o'clock" }
            return "\(cardinal(hour)) \(minute < 10 ? "oh " : "")\(cardinal(minute))"
        }
        return replace(number, in: withTimes) { groups in
            spell(
                whole: groups[2].replacingOccurrences(of: ",", with: ""),
                grouped: groups[2].contains(","),
                fraction: groups[3], scale: groups[4], ordinal: !groups[5].isEmpty,
                dollars: !groups[1].isEmpty, percent: !groups[6].isEmpty)
        }
    }

    // MARK: - Patterns

    /// 3:30, 14:05. Digits on both sides, so `file.swift:89` is left alone.
    private static let time = try! NSRegularExpression(
        pattern: #"(?<![\d:.])(\d{1,2}):([0-5]\d)(?![\d:])"#)

    /// 1 `$`, 2 whole part, 3 decimals, 4 scale word after a dollar amount,
    /// 5 ordinal suffix, 6 `%`.
    private static let number = try! NSRegularExpression(
        pattern: #"(\$)?(\d{1,3}(?:,\d{3})+|\d+)(?:\.(\d+))?"#
            + #"(?:(?<=\d) (hundred|thousand|million|billion|trillion)\b)?"#
            + #"(?:(st|nd|rd|th)(?![A-Za-z]))?(%)?"#)

    private static func replace(
        _ regex: NSRegularExpression, in text: String, with transform: ([String]) -> String
    ) -> String {
        let source = text as NSString
        var result = ""
        var cursor = 0
        for match in regex.matches(in: text, range: NSRange(location: 0, length: source.length)) {
            result += source.substring(with: NSRange(location: cursor, length: match.range.location - cursor))
            let groups = (0..<match.numberOfRanges).map { index -> String in
                let range = match.range(at: index)
                return range.location == NSNotFound ? "" : source.substring(with: range)
            }
            result += transform(groups)
            cursor = match.range.location + match.range.length
        }
        return result + source.substring(from: cursor)
    }

    // MARK: - Spelling

    private static func spell(
        whole: String, grouped: Bool, fraction: String, scale: String, ordinal: Bool,
        dollars: Bool, percent: Bool
    ) -> String {
        // The scale word is only captured to move "dollars" after it:
        // "$5 million" is "five million dollars". Without a `$` it is put back.
        let scaleSuffix = scale.isEmpty ? "" : " \(scale)"
        // Commas or a `$` mark an amount, however long: "$1,000,000,000".
        let wholeWords = { (digits: String) in Self.wholeWords(digits, isAmount: grouped || dollars) }

        if dollars {
            if fraction.count == 2, scale.isEmpty, let cents = Int(fraction) {
                let amount = "\(wholeWords(whole)) \(whole == "1" ? "dollar" : "dollars")"
                return cents == 0 ? amount : "\(amount) and \(cardinal(cents)) \(cents == 1 ? "cent" : "cents")"
            }
            let singular = whole == "1" && fraction.isEmpty && scale.isEmpty
            return wholeWords(whole) + point(fraction) + scaleSuffix + (singular ? " dollar" : " dollars")
        }

        var words: String
        if ordinal, fraction.isEmpty, let value = Int(whole), whole.count <= 9 {
            words = ordinalWords(value)
        } else if !grouped, fraction.isEmpty, !percent, let year = yearWords(whole) {
            words = year
        } else {
            words = wholeWords(whole) + point(fraction)
        }
        words += scaleSuffix
        return percent ? words + " percent" : words
    }

    /// Otherwise, leading zeros and anything past nine digits are identifiers,
    /// not quantities: zip codes, phone numbers, order ids. Read digit by
    /// digit. Amounts past fifteen digits (quadrillions) are too.
    private static func wholeWords(_ digits: String, isAmount: Bool) -> String {
        let isIdentifier = isAmount
            ? digits.count > 15
            : digits.count > 9 || (digits.count > 1 && digits.hasPrefix("0"))
        guard !isIdentifier, let value = Int(digits) else { return digitByDigit(digits) }
        return cardinal(value)
    }

    private static func point(_ fraction: String) -> String {
        fraction.isEmpty ? "" : " point " + digitByDigit(fraction)
    }

    private static func digitByDigit(_ digits: String) -> String {
        digits.compactMap { $0.wholeNumberValue.map(cardinal) }.joined(separator: " ")
    }

    /// A bare four-digit number from 1100 to 2099 is read the way a year is:
    /// "twenty twenty-six", "nineteen oh five". Counts in that range sound
    /// natural this way too ("fifteen hundred"), which is why it is safe to
    /// apply without knowing which one it is.
    private static func yearWords(_ digits: String) -> String? {
        guard digits.count == 4, let value = Int(digits), (1100...2099).contains(value) else { return nil }
        let (century, rest) = (value / 100, value % 100)
        if (2000...2009).contains(value) { return cardinal(value) }
        if rest == 0 { return "\(cardinal(century)) hundred" }
        return "\(cardinal(century)) \(rest < 10 ? "oh " : "")\(cardinal(rest))"
    }

    private static func ordinalWords(_ value: Int) -> String {
        let words = cardinal(value)
        let lastStart = words.lastIndex(of: " ").map(words.index(after:)) ?? words.startIndex
        let last = String(words[lastStart...])
        let irregular = [
            "one": "first", "two": "second", "three": "third", "five": "fifth",
            "eight": "eighth", "nine": "ninth", "twelve": "twelfth",
        ]
        let ending = irregular[last]
            ?? (last.hasSuffix("y") ? last.dropLast() + "ieth" : last + "th")
        return words[..<lastStart] + ending
    }

    private static let formatter: NumberFormatter = {
        let formatter = NumberFormatter()
        formatter.numberStyle = .spellOut
        formatter.locale = Locale(identifier: "en_US")
        return formatter
    }()

    /// Hyphens become spaces: "twenty-six" as one token can miss the lexicon
    /// and fall to espeak, while "twenty" and "six" are always in it.
    private static func cardinal(_ value: Int) -> String {
        (formatter.string(from: NSNumber(value: value)) ?? String(value))
            .replacingOccurrences(of: "-", with: " ")
    }
}
