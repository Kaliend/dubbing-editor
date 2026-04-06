import Foundation

enum WordExportProfile: String, Codable, CaseIterable {
    case classic
    case sdi

    var displayName: String {
        switch self {
        case .classic:
            return "Klasicky"
        case .sdi:
            return "IYUNO"
        }
    }
}

enum WordExportTimecodeSource: String, Codable {
    case start
    case end
}

struct WordExportTimecodeFormat: Codable, Equatable {
    var includeHours: Bool
    var includeMinutes: Bool
    var includeSeconds: Bool
    var includeFrames: Bool

    static let hmsf = WordExportTimecodeFormat(
        includeHours: true,
        includeMinutes: true,
        includeSeconds: true,
        includeFrames: true
    )
}

struct WordExportOptions: Codable, Equatable {
    var profile: WordExportProfile
    var timecodeSource: WordExportTimecodeSource
    var timecodeFormat: WordExportTimecodeFormat
    var includeEmptyRows: Bool

    static let defaultClassic = WordExportOptions(
        profile: .classic,
        timecodeSource: .start,
        timecodeFormat: .hmsf,
        includeEmptyRows: false
    )
}

struct WordExportRow: Equatable {
    let lineID: DialogueLine.ID
    let lineIndex: Int
    let speaker: String
    let timecode: String
    let text: String

    var tabSeparated: String {
        [speaker, timecode, text].joined(separator: "\t")
    }
}

struct WordExportDraft: Equatable {
    let profile: WordExportProfile
    let rows: [WordExportRow]
    let skippedLineCount: Int
}

struct WordExportPipelineService {
    func buildDraft(
        from lines: [DialogueLine],
        options: WordExportOptions,
        fps: Double
    ) -> WordExportDraft {
        var rows: [WordExportRow] = []
        rows.reserveCapacity(lines.count)

        for line in lines {
            let speaker = sanitizeCellValue(line.speaker)
            let text = sanitizeCellValue(line.text)
            let rawTimecode = options.timecodeSource == .start ? line.startTimecode : line.endTimecode
            let timecode = formatTimecode(rawTimecode, format: options.timecodeFormat, fps: fps)

            if !options.includeEmptyRows, speaker.isEmpty, timecode.isEmpty, text.isEmpty {
                continue
            }

            rows.append(
                WordExportRow(
                    lineID: line.id,
                    lineIndex: line.index,
                    speaker: speaker,
                    timecode: timecode,
                    text: text
                )
            )
        }

        return WordExportDraft(
            profile: options.profile,
            rows: rows,
            skippedLineCount: max(0, lines.count - rows.count)
        )
    }

    private func sanitizeCellValue(_ value: String) -> String {
        let normalized = value
            .replacingOccurrences(of: "\t", with: " ")
            .replacingOccurrences(of: "\r\n", with: " ")
            .replacingOccurrences(of: "\n", with: " ")
            .replacingOccurrences(of: "\r", with: " ")
        return normalized
            .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func formatTimecode(
        _ value: String,
        format: WordExportTimecodeFormat,
        fps: Double
    ) -> String {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return ""
        }
        guard format.includeHours || format.includeMinutes || format.includeSeconds || format.includeFrames else {
            return ""
        }

        guard let seconds = TimecodeService.seconds(from: trimmed, fps: fps) else {
            return sanitizeCellValue(trimmed)
        }
        return formatTimecodeFromSeconds(seconds, format: format, fps: fps)
    }

    private func formatTimecodeFromSeconds(
        _ seconds: Double,
        format: WordExportTimecodeFormat,
        fps: Double
    ) -> String {
        let clamped = max(0, seconds)
        let wholeSeconds = Int(floor(clamped))
        let hours = wholeSeconds / 3600
        let minuteComponent = (wholeSeconds % 3600) / 60
        let totalMinutes = wholeSeconds / 60
        let secondComponent = wholeSeconds % 60
        let frameComponent = max(0, Int(((clamped - floor(clamped)) * fps).rounded(.down)))

        var parts: [String] = []
        if format.includeHours {
            parts.append(String(format: "%02d", hours))
        }
        if format.includeMinutes {
            let minuteValue = format.includeHours ? minuteComponent : totalMinutes
            parts.append(String(format: "%02d", minuteValue))
        }
        if format.includeSeconds {
            let secondValue = (format.includeHours || format.includeMinutes) ? secondComponent : wholeSeconds
            parts.append(String(format: "%02d", secondValue))
        }
        if format.includeFrames {
            parts.append(String(format: "%02d", frameComponent))
        }
        return parts.joined(separator: ":")
    }
}
