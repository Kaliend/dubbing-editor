import Foundation

enum TimecodeService {
    static func seconds(from timecode: String, fps: Double) -> Double? {
        let trimmed = timecode.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        let components = trimmed.split(separator: ":", omittingEmptySubsequences: false)
        switch components.count {
        case 4:
            guard fps > 0 else { return nil }
            guard
                let h = parseFixedWidthNumber(components[0], digits: 2),
                let m = parseFixedWidthNumber(components[1], digits: 2),
                let s = parseFixedWidthNumber(components[2], digits: 2),
                let f = parseFixedWidthNumber(components[3], digits: 2)
            else {
                return nil
            }
            return Double(h) * 3600 + Double(m) * 60 + Double(s) + Double(f) / fps

        case 3:
            guard
                let h = parseFixedWidthNumber(components[0], digits: 2),
                let m = parseFixedWidthNumber(components[1], digits: 2)
            else {
                return nil
            }

            if let s = parseFixedWidthNumber(components[2], digits: 2) {
                return Double(h) * 3600 + Double(m) * 60 + Double(s)
            }

            if let secondWithMilliseconds = parseSecondsWithMilliseconds(components[2]) {
                return Double(h) * 3600 + Double(m) * 60 + secondWithMilliseconds
            }

            return nil

        case 2:
            guard
                let m = parseFixedWidthNumber(components[0], digits: 2),
                let s = parseFixedWidthNumber(components[1], digits: 2)
            else {
                return nil
            }
            return Double(m) * 60 + Double(s)

        default:
            return nil
        }
    }

    static func displayTimecode(_ raw: String, fps: Double, hideFrames: Bool) -> String {
        if !hideFrames {
            return raw
        }

        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return "" }

        if isClockTimecode(trimmed) {
            return trimmed
        }

        if isFrameTimecode(trimmed) {
            return String(trimmed.prefix(8))
        }

        guard let seconds = seconds(from: trimmed, fps: fps) else {
            return raw
        }
        return timecodeWithoutFrames(from: seconds)
    }

    static func timecode(from seconds: Double, fps: Double) -> String {
        let clamped = max(0, seconds)
        let hh = Int(clamped / 3600)
        let mm = Int((clamped.truncatingRemainder(dividingBy: 3600)) / 60)
        let ss = Int(clamped.truncatingRemainder(dividingBy: 60))
        let ff = Int(((clamped - floor(clamped)) * fps).rounded(.down))

        return String(format: "%02d:%02d:%02d:%02d", hh, mm, ss, max(0, ff))
    }

    static func timecodeWithoutFrames(from seconds: Double) -> String {
        let clamped = max(0, seconds)
        let hh = Int(clamped / 3600)
        let mm = Int((clamped.truncatingRemainder(dividingBy: 3600)) / 60)
        let ss = Int(clamped.truncatingRemainder(dividingBy: 60))
        return String(format: "%02d:%02d:%02d", hh, mm, ss)
    }

    static func offsetSeconds(from value: String, fps: Double) -> Double? {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        var sign: Double = 1
        var core = trimmed
        if core.hasPrefix("+") {
            core.removeFirst()
        } else if core.hasPrefix("-") {
            core.removeFirst()
            sign = -1
        }

        let normalized = core.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalized.isEmpty else { return nil }

        if normalized.contains(":") {
            guard let tcSeconds = seconds(from: normalized, fps: fps) else {
                return nil
            }
            return sign * tcSeconds
        }

        let decimalNormalized = normalized.replacingOccurrences(of: ",", with: ".")
        guard let plainSeconds = Double(decimalNormalized) else {
            return nil
        }
        return sign * plainSeconds
    }

    // Timecode parsing sits on the row render path, so keep it allocation-light and avoid regex compilation.
    private static func parseFixedWidthNumber(_ text: Substring, digits: Int) -> Int? {
        guard text.count == digits else { return nil }

        var value = 0
        for character in text {
            guard let digit = character.wholeNumberValue else { return nil }
            value = value * 10 + digit
        }
        return value
    }

    private static func parseSecondsWithMilliseconds(_ text: Substring) -> Double? {
        guard text.count == 6 else { return nil }

        let separatorIndex = text.index(text.startIndex, offsetBy: 2)
        let millisecondsIndex = text.index(after: separatorIndex)
        let separator = text[separatorIndex]
        guard separator == "." || separator == "," else { return nil }

        guard
            let seconds = parseFixedWidthNumber(text[..<separatorIndex], digits: 2),
            let milliseconds = parseFixedWidthNumber(text[millisecondsIndex...], digits: 3)
        else {
            return nil
        }

        return Double(seconds) + Double(milliseconds) / 1000
    }

    private static func isClockTimecode(_ text: String) -> Bool {
        matchesDelimitedFixedWidthNumbers(text, separator: ":", componentLengths: [2, 2, 2])
    }

    private static func isFrameTimecode(_ text: String) -> Bool {
        matchesDelimitedFixedWidthNumbers(text, separator: ":", componentLengths: [2, 2, 2, 2])
    }

    private static func matchesDelimitedFixedWidthNumbers(
        _ text: String,
        separator: Character,
        componentLengths: [Int]
    ) -> Bool {
        let components = text.split(separator: separator, omittingEmptySubsequences: false)
        guard components.count == componentLengths.count else { return false }

        for (component, expectedLength) in zip(components, componentLengths) {
            guard parseFixedWidthNumber(component, digits: expectedLength) != nil else {
                return false
            }
        }

        return true
    }
}
