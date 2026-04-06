import Foundation
#if canImport(FoundationXML)
import FoundationXML
#endif

enum WordImportFormat: String, Codable, CaseIterable {
    case iyunoTable = "iyuno_table"
    case classicTabs = "classic_tabs"
    case unknown = "unknown"

    var displayName: String {
        switch self {
        case .iyunoTable:
            return "IYUNO (tabulka)"
        case .classicTabs:
            return "Klasicky (tabulatory)"
        case .unknown:
            return "Neznamy"
        }
    }
}

struct WordImportInspection {
    let sourceURL: URL
    let detectedFormat: WordImportFormat
    let documentXML: String
    let convertedFromLegacyDoc: Bool
}

struct WordImportResult {
    let sourceURL: URL
    let detectedFormat: WordImportFormat
    let convertedFromLegacyDoc: Bool
    let lines: [DialogueLine]
    let skippedRowCount: Int
}

enum WordImportServiceError: LocalizedError {
    case inputFileNotFound(URL)
    case unsupportedExtension(String)
    case conversionFailed(String)
    case failedToLaunchTool(String)
    case failedToReadDocxPackage(String)
    case documentXMLNotFound
    case documentXMLDecodingFailed
    case xmlParsingFailed(String)
    case processTimedOut(command: String, timeoutSeconds: TimeInterval)

    var errorDescription: String? {
        switch self {
        case .inputFileNotFound(let url):
            return "Vstupni soubor nebyl nalezen: \(url.lastPathComponent)"
        case .unsupportedExtension(let ext):
            return "Nepodporovana pripona souboru: .\(ext)"
        case .conversionFailed(let details):
            return "Nepodarilo se prevest .doc na .docx. \(details)"
        case .failedToLaunchTool(let details):
            return "Nepodarilo se spustit systemovy nastroj. \(details)"
        case .failedToReadDocxPackage(let details):
            return "Nepodarilo se nacist DOCX balicek. \(details)"
        case .documentXMLNotFound:
            return "V DOCX chybi soubor word/document.xml"
        case .documentXMLDecodingFailed:
            return "Nepodarilo se dekodovat XML obsah Word dokumentu."
        case .xmlParsingFailed(let details):
            return "Nepodarilo se naparsovat XML dokumentu. \(details)"
        case .processTimedOut(let command, let timeoutSeconds):
            return "Import se zasekl pri prikazu '\(command)' a byl ukoncen po \(Int(timeoutSeconds))s."
        }
    }
}

protocol DocInputNormalizing {
    func normalize(sourceURL: URL) throws -> DocInputNormalizationResult
}

protocol DocxPackageReading {
    func readDocumentXML(from docxURL: URL) throws -> Data
}

protocol ImportFormatDetecting {
    func detectFormat(inDocumentXML xml: String) -> WordImportFormat
}

struct WordImportService {
    private let inputNormalizer: DocInputNormalizing
    private let docxPackageReader: DocxPackageReading
    private let formatDetector: ImportFormatDetecting

    init(
        inputNormalizer: DocInputNormalizing = DocInputNormalizer(),
        docxPackageReader: DocxPackageReading = DocxPackageReader(),
        formatDetector: ImportFormatDetecting = ImportFormatDetector()
    ) {
        self.inputNormalizer = inputNormalizer
        self.docxPackageReader = docxPackageReader
        self.formatDetector = formatDetector
    }

    func inspect(sourceURL: URL) throws -> WordImportInspection {
        let normalized = try inputNormalizer.normalize(sourceURL: sourceURL)
        defer {
            normalized.cleanupTemporaryArtifacts()
        }

        let xmlData = try docxPackageReader.readDocumentXML(from: normalized.docxURL)
        guard let xml = decodeDocumentXML(xmlData) else {
            throw WordImportServiceError.documentXMLDecodingFailed
        }

        let format = formatDetector.detectFormat(inDocumentXML: xml)
        return WordImportInspection(
            sourceURL: sourceURL,
            detectedFormat: format,
            documentXML: xml,
            convertedFromLegacyDoc: normalized.convertedFromLegacyDoc
        )
    }

    func importLines(sourceURL: URL, fps: Double) throws -> WordImportResult {
        let inspection = try inspect(sourceURL: sourceURL)
        let xmlDocument = try WordXMLExtractor.extract(from: inspection.documentXML)

        var drafts: [ImportedLineDraft]
        var detectedFormat = inspection.detectedFormat
        switch inspection.detectedFormat {
        case .iyunoTable:
            let iyuno = parseIyunoDrafts(from: xmlDocument, fps: fps)
            drafts = iyuno.isEmpty ? parseClassicDrafts(from: xmlDocument, fps: fps) : iyuno
        case .classicTabs:
            let classic = parseClassicDrafts(from: xmlDocument, fps: fps)
            drafts = classic.isEmpty ? parseIyunoDrafts(from: xmlDocument, fps: fps) : classic
        case .unknown:
            let classic = parseClassicDrafts(from: xmlDocument, fps: fps)
            let iyuno = parseIyunoDrafts(from: xmlDocument, fps: fps)
            if qualityScore(for: iyuno) > qualityScore(for: classic) {
                drafts = iyuno
            } else if !classic.isEmpty {
                drafts = classic
            } else {
                drafts = xmlDocument.paragraphs
                    .map { ImportedLineDraft(speaker: "", text: normalizeWhitespace($0), startTimecode: "", endTimecode: "") }
            }
        }

        // Legacy .doc files: prefer HTML extraction first because textutil often
        // preserves table structure in HTML better than in DOCX XML.
        if inspection.convertedFromLegacyDoc,
           let htmlDrafts = try? parseLegacyDocHTMLDrafts(sourceURL: sourceURL, fps: fps),
           !htmlDrafts.isEmpty {
            let htmlScore = qualityScore(for: htmlDrafts)
            let xmlScore = qualityScore(for: drafts)
            if htmlScore >= xmlScore {
                drafts = htmlDrafts
                detectedFormat = .iyunoTable
            }
        }

        let trimmedDrafts = trimLeadingPreamble(from: drafts)
        let meaningfulDrafts = trimmedDrafts.filter(\.isMeaningful)
        let lines: [DialogueLine] = meaningfulDrafts.enumerated().map { idx, draft in
            DialogueLine(
                index: idx + 1,
                speaker: draft.speaker,
                text: draft.text,
                startTimecode: draft.startTimecode,
                endTimecode: draft.endTimecode
            )
        }

        return WordImportResult(
            sourceURL: sourceURL,
            detectedFormat: detectedFormat,
            convertedFromLegacyDoc: inspection.convertedFromLegacyDoc,
            lines: lines,
            skippedRowCount: max(0, drafts.count - meaningfulDrafts.count)
        )
    }

    private func decodeDocumentXML(_ data: Data) -> String? {
        if let utf8 = String(data: data, encoding: .utf8) {
            return utf8
        }
        if let utf16 = String(data: data, encoding: .utf16) {
            return utf16
        }
        if let utf16Little = String(data: data, encoding: .utf16LittleEndian) {
            return utf16Little
        }
        if let utf16Big = String(data: data, encoding: .utf16BigEndian) {
            return utf16Big
        }
        return nil
    }

    private func parseLegacyDocHTMLDrafts(sourceURL: URL, fps: Double) throws -> [ImportedLineDraft] {
        let tempRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent("DubbingEditor-WordImport-HTML-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempRoot, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempRoot) }

        let outputURL = tempRoot
            .appendingPathComponent(sourceURL.deletingPathExtension().lastPathComponent)
            .appendingPathExtension("html")

        let output = try ImportProcessRunner.run(
            executablePath: "/usr/bin/textutil",
            arguments: ["-convert", "html", "-output", outputURL.path, sourceURL.path]
        )
        guard output.status == 0 else {
            return []
        }
        guard let data = try? Data(contentsOf: outputURL), let html = decodeDocumentXML(data) else {
            return []
        }
        return parseHTMLTableDrafts(from: html, fps: fps)
    }

    private func parseHTMLTableDrafts(from html: String, fps: Double) -> [ImportedLineDraft] {
        guard let rowRegex = try? NSRegularExpression(pattern: #"(?is)<tr\b[^>]*>(.*?)</tr>"#) else {
            return []
        }
        guard let cellRegex = try? NSRegularExpression(pattern: #"(?is)<td\b[^>]*>(.*?)</td>"#) else {
            return []
        }

        let fullRange = NSRange(html.startIndex..<html.endIndex, in: html)
        let rowMatches = rowRegex.matches(in: html, range: fullRange)
        var rows: [ImportedLineDraft] = []
        rows.reserveCapacity(rowMatches.count)

        for rowMatch in rowMatches {
            guard rowMatch.numberOfRanges > 1, let rowRange = Range(rowMatch.range(at: 1), in: html) else {
                continue
            }
            let rowHTML = String(html[rowRange])
            let rowRangeInRow = NSRange(rowHTML.startIndex..<rowHTML.endIndex, in: rowHTML)
            let cellMatches = cellRegex.matches(in: rowHTML, range: rowRangeInRow)
            if cellMatches.isEmpty {
                continue
            }

            let cells = cellMatches.compactMap { match -> String? in
                guard match.numberOfRanges > 1, let range = Range(match.range(at: 1), in: rowHTML) else {
                    return nil
                }
                let stripped = stripHTML(String(rowHTML[range]))
                return normalizeWhitespace(stripped)
            }

            if cells.allSatisfy(\.isEmpty) {
                continue
            }

            var startTC = ""
            var endTC = ""
            var nonTimeCells: [String] = []
            nonTimeCells.reserveCapacity(cells.count)

            for cell in cells where !cell.isEmpty {
                if isLikelyTimecodeField(cell) {
                    let (start, end) = extractStartEndTimecodes(from: cell, fps: fps)
                    if let start, startTC.isEmpty {
                        startTC = start
                    }
                    if let end, endTC.isEmpty {
                        endTC = end
                    }
                    if start == nil, end == nil {
                        nonTimeCells.append(cell)
                    }
                } else {
                    nonTimeCells.append(cell)
                }
            }

            var speaker = ""
            if let explicit = nonTimeCells.first(where: isSpeakerLikeLabel) {
                speaker = explicit
            }

            var text = ""
            for value in nonTimeCells where value != speaker {
                if isLikelyIndexCell(value) {
                    continue
                }
                if value.count >= text.count {
                    text = value
                }
            }
            if text.isEmpty, let fallback = nonTimeCells.last, fallback != speaker {
                text = fallback
            }

            let draft = ImportedLineDraft(
                speaker: speaker,
                text: text,
                startTimecode: startTC,
                endTimecode: endTC
            )
            if draft.isMeaningful, !isLikelyHeaderDraft(draft) {
                rows.append(draft)
            }
        }

        return rows
    }

    private func stripHTML(_ input: String) -> String {
        let withBreaks = input.replacingOccurrences(
            of: #"(?is)<br\s*/?>"#,
            with: "\n",
            options: .regularExpression
        )
        let withoutTags = withBreaks.replacingOccurrences(
            of: #"(?is)<[^>]+>"#,
            with: " ",
            options: .regularExpression
        )
        return decodeHTMLEntities(withoutTags)
    }

    private func decodeHTMLEntities(_ input: String) -> String {
        var output = input
        let entities: [(String, String)] = [
            ("&nbsp;", " "),
            ("&amp;", "&"),
            ("&lt;", "<"),
            ("&gt;", ">"),
            ("&quot;", "\""),
            ("&#39;", "'")
        ]
        for (entity, value) in entities {
            output = output.replacingOccurrences(of: entity, with: value)
        }
        return output
    }

    private func parseClassicDrafts(from document: WordXMLDocument, fps: Double) -> [ImportedLineDraft] {
        var rows: [ImportedLineDraft] = []
        rows.reserveCapacity(document.paragraphs.count)

        for paragraph in document.paragraphs {
            let trimmed = normalizeWhitespace(paragraph)
            guard !trimmed.isEmpty else { continue }

            let columns = paragraph
                .components(separatedBy: "\t")
                .map { normalizeWhitespace($0) }

            let draft: ImportedLineDraft
            if columns.count >= 3 {
                let speaker = columns[0]
                let tcChunk = columns[1]
                let (start, end) = extractStartEndTimecodes(from: tcChunk, fps: fps)
                let text = normalizeWhitespace(columns.dropFirst(2).joined(separator: " "))
                draft = ImportedLineDraft(
                    speaker: speaker,
                    text: text,
                    startTimecode: start ?? "",
                    endTimecode: end ?? ""
                )
            } else if columns.count == 2 {
                let first = columns[0]
                let second = columns[1]
                let firstPair = extractStartEndTimecodes(from: first, fps: fps)
                let secondPair = extractStartEndTimecodes(from: second, fps: fps)

                if firstPair.0 != nil || firstPair.1 != nil {
                    draft = ImportedLineDraft(
                        speaker: "",
                        text: second,
                        startTimecode: firstPair.0 ?? "",
                        endTimecode: firstPair.1 ?? ""
                    )
                } else if secondPair.0 != nil || secondPair.1 != nil {
                    draft = ImportedLineDraft(
                        speaker: first,
                        text: "",
                        startTimecode: secondPair.0 ?? "",
                        endTimecode: secondPair.1 ?? ""
                    )
                } else {
                    draft = ImportedLineDraft(speaker: first, text: second, startTimecode: "", endTimecode: "")
                }
            } else {
                draft = parseSingleClassicField(trimmed, fps: fps)
            }

            if draft.isMeaningful {
                rows.append(draft)
            }
        }

        return rows
    }

    private func parseSingleClassicField(_ value: String, fps: Double) -> ImportedLineDraft {
        let trimmed = normalizeWhitespace(value)
        if trimmed.isEmpty {
            return ImportedLineDraft(speaker: "", text: "", startTimecode: "", endTimecode: "")
        }

        if
            let speakerMatch = firstRegexMatch(
                pattern: #"^\s*(.+?)\s*:\s*(\d{2}:\d{2}(?::\d{2}(?::\d{2}|[\.,]\d{3})?)?)\s+(.+)$"#,
                in: trimmed
            ),
            speakerMatch.count == 3
        {
            let start = normalizeTimecodeToken(speakerMatch[1], fps: fps) ?? ""
            return ImportedLineDraft(
                speaker: normalizeWhitespace(speakerMatch[0]),
                text: normalizeWhitespace(speakerMatch[2]),
                startTimecode: start,
                endTimecode: ""
            )
        }

        if
            let leadingTCMatch = firstRegexMatch(
                pattern: #"^\s*(\d{2}:\d{2}(?::\d{2}(?::\d{2}|[\.,]\d{3})?)?)\s+(.+)$"#,
                in: trimmed
            ),
            leadingTCMatch.count == 2
        {
            let start = normalizeTimecodeToken(leadingTCMatch[0], fps: fps) ?? ""
            return ImportedLineDraft(
                speaker: "",
                text: normalizeWhitespace(leadingTCMatch[1]),
                startTimecode: start,
                endTimecode: ""
            )
        }

        if isSpeakerLikeLabel(trimmed) {
            return ImportedLineDraft(speaker: trimmed, text: "", startTimecode: "", endTimecode: "")
        }

        return ImportedLineDraft(speaker: "", text: trimmed, startTimecode: "", endTimecode: "")
    }

    private func parseIyunoDrafts(from document: WordXMLDocument, fps: Double) -> [ImportedLineDraft] {
        let tableRows = parseIyunoTableDrafts(from: document, fps: fps)
        let paragraphRows = parseIyunoParagraphDrafts(from: document, fps: fps)
        let tableScore = qualityScore(for: tableRows)
        let paragraphScore = qualityScore(for: paragraphRows)
        if paragraphScore > tableScore {
            return paragraphRows
        }
        return tableRows
    }

    private func parseIyunoTableDrafts(from document: WordXMLDocument, fps: Double) -> [ImportedLineDraft] {
        var rows: [ImportedLineDraft] = []
        let flattenedRows = document.tables.flatMap(\.rows)
        rows.reserveCapacity(flattenedRows.count)

        for row in flattenedRows {
            let cells = row.map { normalizeWhitespace($0) }
            if cells.allSatisfy({ $0.isEmpty }) {
                continue
            }

            var usedCellIndexes: Set<Int> = []
            var startTC: String = ""
            var endTC: String = ""
            var foundStandaloneTCs: [String] = []

            for (idx, cell) in cells.enumerated() {
                guard !cell.isEmpty else { continue }
                guard isLikelyTimecodeField(cell) else {
                    continue
                }
                let (start, end) = extractStartEndTimecodes(from: cell, fps: fps)
                if start != nil || end != nil {
                    usedCellIndexes.insert(idx)
                    if startTC.isEmpty, let start {
                        startTC = start
                    }
                    if endTC.isEmpty, let end {
                        endTC = end
                    }

                    if end == nil, let start {
                        foundStandaloneTCs.append(start)
                    }
                }
            }

            if endTC.isEmpty, foundStandaloneTCs.count >= 2 {
                endTC = foundStandaloneTCs[1]
            }

            var textCellIndex: Int?
            var textValue = ""
            for (idx, cell) in cells.enumerated() {
                guard !usedCellIndexes.contains(idx) else { continue }
                guard !cell.isEmpty else { continue }
                guard !isLikelyIndexCell(cell) else { continue }
                if cell.count >= textValue.count {
                    textValue = cell
                    textCellIndex = idx
                }
            }

            if textValue.isEmpty, let fallbackText = cells.last(where: { !$0.isEmpty }) {
                textValue = fallbackText
            }

            var speakerValue = ""
            for (idx, cell) in cells.enumerated() {
                guard !cell.isEmpty else { continue }
                if textCellIndex == idx {
                    continue
                }
                if usedCellIndexes.contains(idx) {
                    continue
                }
                if isLikelyIndexCell(cell) {
                    continue
                }

                speakerValue = cell
                break
            }

            let draft = ImportedLineDraft(
                speaker: speakerValue,
                text: textValue,
                startTimecode: startTC,
                endTimecode: endTC
            )
            if draft.isMeaningful, !isLikelyHeaderDraft(draft) {
                rows.append(draft)
            }
        }

        return rows
    }

    private func parseIyunoParagraphDrafts(from document: WordXMLDocument, fps: Double) -> [ImportedLineDraft] {
        let paragraphs = document.paragraphs.map(normalizeWhitespace)
        guard !paragraphs.isEmpty else { return [] }

        var usedParagraphIndexes: Set<Int> = []
        var rows: [ImportedLineDraft] = []
        rows.reserveCapacity(paragraphs.count / 3)

        let speakerLookbackLimit = 3
        let textLookbackLimit = 2
        let textLookaheadLimit = 3

        for idx in paragraphs.indices {
            if usedParagraphIndexes.contains(idx) {
                continue
            }
            let paragraph = paragraphs[idx]
            guard let timecode = extractSingleTimecodeIfStandalone(from: paragraph, fps: fps) else {
                continue
            }

            var speaker = ""
            var text = ""
            var beforeTextIdx: Int?
            var afterTextIdx: Int?

            if let prev = nearestNonEmptyParagraphIndex(
                before: idx,
                in: paragraphs,
                excluding: usedParagraphIndexes,
                maxDistance: speakerLookbackLimit
            ),
               isSpeakerLikeLabel(paragraphs[prev]) {
                speaker = paragraphs[prev]
                usedParagraphIndexes.insert(prev)
                beforeTextIdx = nearestTextParagraphIndex(
                    before: prev,
                    in: paragraphs,
                    excluding: usedParagraphIndexes,
                    maxDistance: textLookbackLimit
                )
            } else {
                beforeTextIdx = nearestTextParagraphIndex(
                    before: idx,
                    in: paragraphs,
                    excluding: usedParagraphIndexes,
                    maxDistance: 1
                )
            }

            afterTextIdx = nearestTextParagraphIndex(
                after: idx,
                in: paragraphs,
                excluding: usedParagraphIndexes,
                maxDistance: textLookaheadLimit
            )

            let chosenTextIdx: Int?
            if let beforeTextIdx, let afterTextIdx {
                let beforeDistance = idx - beforeTextIdx
                let afterDistance = afterTextIdx - idx
                chosenTextIdx = beforeDistance <= afterDistance ? beforeTextIdx : afterTextIdx
            } else {
                chosenTextIdx = beforeTextIdx ?? afterTextIdx
            }

            if let chosenTextIdx {
                text = paragraphs[chosenTextIdx]
                usedParagraphIndexes.insert(chosenTextIdx)
            }

            let draft = ImportedLineDraft(
                speaker: speaker,
                text: text,
                startTimecode: timecode,
                endTimecode: ""
            )
            if draft.isMeaningful, !isLikelyHeaderDraft(draft) {
                rows.append(draft)
                usedParagraphIndexes.insert(idx)
            }
        }

        return rows
    }

    private func normalizeWhitespace(_ value: String) -> String {
        value
            .replacingOccurrences(of: "\u{00A0}", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func extractStartEndTimecodes(from value: String, fps: Double) -> (String?, String?) {
        let tokens = extractTimecodeTokens(from: value)
        guard !tokens.isEmpty else {
            return (nil, nil)
        }

        let normalized = tokens.compactMap { normalizeTimecodeToken($0, fps: fps) }
        guard !normalized.isEmpty else {
            return (nil, nil)
        }

        if normalized.count >= 2 {
            return (normalized[0], normalized[1])
        }
        return (normalized[0], nil)
    }

    private func isLikelyTimecodeField(_ value: String) -> Bool {
        let trimmed = normalizeWhitespace(value)
        guard !trimmed.isEmpty else {
            return false
        }
        if trimmed.unicodeScalars.contains(where: CharacterSet.letters.contains) {
            return false
        }
        return !extractTimecodeTokens(from: trimmed).isEmpty
    }

    private func extractTimecodeTokens(from value: String) -> [String] {
        guard let regex = try? NSRegularExpression(pattern: #"(?<!\d)(\d{2}:\d{2}(?::\d{2}(?::\d{2}|[\.,]\d{3})?)?)(?!\d)"#) else {
            return []
        }
        let range = NSRange(value.startIndex..<value.endIndex, in: value)
        return regex.matches(in: value, range: range).compactMap { match in
            guard match.numberOfRanges > 1 else { return nil }
            let tokenRange = match.range(at: 1)
            guard
                tokenRange.location != NSNotFound,
                let swiftRange = Range(tokenRange, in: value)
            else {
                return nil
            }
            return String(value[swiftRange])
        }
    }

    private func normalizeTimecodeToken(_ token: String, fps: Double) -> String? {
        guard let seconds = TimecodeService.seconds(from: token, fps: fps) else {
            return nil
        }
        return TimecodeService.timecode(from: seconds, fps: fps)
    }

    private func extractSingleTimecodeIfStandalone(from value: String, fps: Double) -> String? {
        let trimmed = normalizeWhitespace(value)
        guard !trimmed.isEmpty else { return nil }
        let tokens = extractTimecodeTokens(from: trimmed)
        guard tokens.count == 1 else { return nil }
        guard normalizeWhitespace(tokens[0]) == trimmed else { return nil }
        return normalizeTimecodeToken(trimmed, fps: fps)
    }

    private func nearestNonEmptyParagraphIndex(
        before index: Int,
        in paragraphs: [String],
        excluding used: Set<Int>,
        maxDistance: Int
    ) -> Int? {
        var cursor = index - 1
        var traversed = 0
        while cursor >= 0 {
            if traversed >= maxDistance {
                return nil
            }
            if !used.contains(cursor), !paragraphs[cursor].isEmpty {
                return cursor
            }
            cursor -= 1
            traversed += 1
        }
        return nil
    }

    private func nearestTextParagraphIndex(
        before index: Int,
        in paragraphs: [String],
        excluding used: Set<Int>,
        maxDistance: Int
    ) -> Int? {
        var cursor = index - 1
        var traversed = 0
        while cursor >= 0 {
            if traversed >= maxDistance {
                return nil
            }
            let value = paragraphs[cursor]
            if !used.contains(cursor), isLikelyDialogueText(value) {
                return cursor
            }
            cursor -= 1
            traversed += 1
        }
        return nil
    }

    private func nearestTextParagraphIndex(
        after index: Int,
        in paragraphs: [String],
        excluding used: Set<Int>,
        maxDistance: Int
    ) -> Int? {
        var cursor = index + 1
        var traversed = 0
        while cursor < paragraphs.count {
            if traversed >= maxDistance {
                return nil
            }
            let value = paragraphs[cursor]
            if !used.contains(cursor), isLikelyDialogueText(value) {
                return cursor
            }
            cursor += 1
            traversed += 1
        }
        return nil
    }

    private func trimLeadingPreamble(from drafts: [ImportedLineDraft]) -> [ImportedLineDraft] {
        guard drafts.count > 6 else { return drafts }

        if let anchoredByTimecode = findFirstDialogueAnchorIndexByTimecode(in: drafts) {
            return Array(drafts[anchoredByTimecode...])
        }

        if let anchoredBySpeakerText = findFirstDialogueAnchorIndexBySpeakerText(in: drafts) {
            return Array(drafts[anchoredBySpeakerText...])
        }

        return drafts
    }

    private func findFirstDialogueAnchorIndexByTimecode(in drafts: [ImportedLineDraft]) -> Int? {
        let anchorWindow = 24
        for idx in drafts.indices {
            guard hasValidStartTimecode(drafts[idx]) else { continue }
            let upperBound = min(drafts.count, idx + anchorWindow)
            let window = drafts[idx..<upperBound]
            let strongCount = window.reduce(into: 0) { acc, draft in
                if hasValidStartTimecode(draft), isLikelyDialogueText(draft.text) {
                    acc += 1
                }
            }
            if strongCount >= 3 {
                return idx
            }
        }

        for idx in drafts.indices where hasValidStartTimecode(drafts[idx]) {
            if isLikelyDialogueText(drafts[idx].text) || !drafts[idx].speaker.isEmpty {
                return idx
            }
        }
        return nil
    }

    private func findFirstDialogueAnchorIndexBySpeakerText(in drafts: [ImportedLineDraft]) -> Int? {
        let anchorWindow = 16
        for idx in drafts.indices {
            let upperBound = min(drafts.count, idx + anchorWindow)
            let window = drafts[idx..<upperBound]
            let speakerTextCount = window.reduce(into: 0) { acc, draft in
                if !draft.speaker.isEmpty, isLikelyDialogueText(draft.text) {
                    acc += 1
                }
            }
            if speakerTextCount >= 4 {
                return idx
            }
        }
        return nil
    }

    private func hasValidStartTimecode(_ draft: ImportedLineDraft) -> Bool {
        !draft.startTimecode.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private func isLikelyDialogueText(_ value: String) -> Bool {
        let trimmed = normalizeWhitespace(value)
        if trimmed.count < 2 {
            return false
        }
        if isLikelyMetadataLine(trimmed) {
            return false
        }
        let hasLetter = trimmed.unicodeScalars.contains(where: CharacterSet.letters.contains)
        return hasLetter
    }

    private func isLikelyHeaderDraft(_ draft: ImportedLineDraft) -> Bool {
        if hasValidStartTimecode(draft) {
            return false
        }
        let speaker = normalizeWhitespace(draft.speaker).lowercased()
        let text = normalizeWhitespace(draft.text).lowercased()
        let forbiddenSpeakerTokens: Set<String> = ["postava", "vstupy", "character", "entries", "script name", "original name", "gender", "actor"]
        if forbiddenSpeakerTokens.contains(speaker) {
            return true
        }
        if forbiddenSpeakerTokens.contains(text) {
            return true
        }
        return isLikelyMetadataLine(speaker) || isLikelyMetadataLine(text)
    }

    private func isLikelyMetadataLine(_ value: String) -> Bool {
        let trimmed = normalizeWhitespace(value)
        guard !trimmed.isEmpty else { return false }
        let lowered = trimmed.lowercased()
        let metadataPrefixTokens = [
            "original title", "translated title", "series title", "season #", "episode #",
            "language", "date", "translated by", "notes", "poznamky", "synopse",
            "statistics", "script name", "main title", "page:"
        ]
        if metadataPrefixTokens.contains(where: { lowered == $0 || lowered.hasPrefix($0 + ":") || lowered.hasPrefix($0 + " ") }) {
            return true
        }
        if lowered == "konec" || lowered == "the end" {
            return true
        }
        return false
    }

    private func qualityScore(for drafts: [ImportedLineDraft]) -> Int {
        guard !drafts.isEmpty else { return 0 }
        var score = 0
        for draft in drafts {
            if hasValidStartTimecode(draft) {
                score += 3
            }
            if !draft.speaker.isEmpty, isLikelyDialogueText(draft.text) {
                score += 2
            }
            if isLikelyDialogueText(draft.text) {
                score += 1
            }
            if isLikelyHeaderDraft(draft) {
                score -= 2
            }
        }
        return score
    }

    private func isLikelyIndexCell(_ value: String) -> Bool {
        let trimmed = normalizeWhitespace(value)
        guard !trimmed.isEmpty else { return false }
        return trimmed.unicodeScalars.allSatisfy(CharacterSet.decimalDigits.contains) && trimmed.count <= 6
    }

    private func isSpeakerLikeLabel(_ value: String) -> Bool {
        let trimmed = normalizeWhitespace(value)
        guard !trimmed.isEmpty, trimmed.count <= 42 else { return false }
        if trimmed.range(of: #"(?i)^insert\s+\d+[a-z]?$"#, options: .regularExpression) != nil {
            return true
        }
        let hasLetter = trimmed.unicodeScalars.contains(where: CharacterSet.letters.contains)
        guard hasLetter else { return false }
        let hasLower = trimmed.unicodeScalars.contains(where: CharacterSet.lowercaseLetters.contains)
        if hasLower {
            return false
        }
        let allowed = CharacterSet.alphanumerics
            .union(CharacterSet.whitespaces)
            .union(CharacterSet(charactersIn: "-_/&().,'#:+"))
        return trimmed.unicodeScalars.allSatisfy { allowed.contains($0) }
    }

    private func firstRegexMatch(pattern: String, in value: String) -> [String]? {
        guard let regex = try? NSRegularExpression(pattern: pattern) else {
            return nil
        }
        let range = NSRange(value.startIndex..<value.endIndex, in: value)
        guard let match = regex.firstMatch(in: value, range: range) else {
            return nil
        }

        var groups: [String] = []
        for idx in 1..<match.numberOfRanges {
            let itemRange = match.range(at: idx)
            guard
                itemRange.location != NSNotFound,
                let swiftRange = Range(itemRange, in: value)
            else {
                groups.append("")
                continue
            }
            groups.append(String(value[swiftRange]))
        }
        return groups
    }
}

struct DocInputNormalizationResult {
    let docxURL: URL
    let convertedFromLegacyDoc: Bool
    let temporaryCleanupURL: URL?

    func cleanupTemporaryArtifacts() {
        guard let temporaryCleanupURL else { return }
        try? FileManager.default.removeItem(at: temporaryCleanupURL)
    }
}

struct DocInputNormalizer: DocInputNormalizing {
    func normalize(sourceURL: URL) throws -> DocInputNormalizationResult {
        let fileManager = FileManager.default
        guard fileManager.fileExists(atPath: sourceURL.path) else {
            throw WordImportServiceError.inputFileNotFound(sourceURL)
        }

        let ext = sourceURL.pathExtension.lowercased()
        switch ext {
        case "docx":
            return DocInputNormalizationResult(
                docxURL: sourceURL,
                convertedFromLegacyDoc: false,
                temporaryCleanupURL: nil
            )
        case "doc":
            return try convertDocToDocx(sourceURL: sourceURL)
        default:
            throw WordImportServiceError.unsupportedExtension(ext)
        }
    }

    private func convertDocToDocx(sourceURL: URL) throws -> DocInputNormalizationResult {
        let tempRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent("DubbingEditor-WordImport-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempRoot, withIntermediateDirectories: true)

        let outputURL = tempRoot
            .appendingPathComponent(sourceURL.deletingPathExtension().lastPathComponent)
            .appendingPathExtension("docx")

        let output = try ImportProcessRunner.run(
            executablePath: "/usr/bin/textutil",
            arguments: ["-convert", "docx", "-output", outputURL.path, sourceURL.path]
        )

        guard output.status == 0 else {
            let stderr = output.stderrString.trimmingCharacters(in: .whitespacesAndNewlines)
            throw WordImportServiceError.conversionFailed(stderr.isEmpty ? "textutil vratil chybu." : stderr)
        }

        guard FileManager.default.fileExists(atPath: outputURL.path) else {
            throw WordImportServiceError.conversionFailed("Vystupni .docx nebyl vytvoren.")
        }

        return DocInputNormalizationResult(
            docxURL: outputURL,
            convertedFromLegacyDoc: true,
            temporaryCleanupURL: tempRoot
        )
    }
}

struct DocxPackageReader: DocxPackageReading {
    func readDocumentXML(from docxURL: URL) throws -> Data {
        guard FileManager.default.fileExists(atPath: docxURL.path) else {
            throw WordImportServiceError.inputFileNotFound(docxURL)
        }

        let output = try ImportProcessRunner.run(
            executablePath: "/usr/bin/unzip",
            arguments: ["-p", docxURL.path, "word/document.xml"]
        )

        guard output.status == 0 else {
            let stderr = output.stderrString.trimmingCharacters(in: .whitespacesAndNewlines)
            throw WordImportServiceError.failedToReadDocxPackage(stderr.isEmpty ? "unzip vratil chybu." : stderr)
        }

        guard !output.stdout.isEmpty else {
            throw WordImportServiceError.documentXMLNotFound
        }
        return output.stdout
    }
}

struct ImportFormatDetector: ImportFormatDetecting {
    func detectFormat(inDocumentXML xml: String) -> WordImportFormat {
        let tableCount = occurrenceCount(of: "<w:tbl", in: xml)
        let rowCount = occurrenceCount(of: "<w:tr", in: xml)
        let tabCount = occurrenceCount(of: "<w:tab", in: xml)
        let paragraphCount = occurrenceCount(of: "<w:p", in: xml)

        if tableCount > 0, rowCount >= 2, rowCount * 2 >= max(1, tabCount) {
            return .iyunoTable
        }

        // "Classic tabs" should have tabs at significant density relative to paragraphs.
        if tabCount >= max(20, paragraphCount / 4) {
            return .classicTabs
        }
        if tabCount >= 2, paragraphCount <= 40 {
            return .classicTabs
        }

        return .unknown
    }

    private func occurrenceCount(of token: String, in text: String) -> Int {
        guard !token.isEmpty, !text.isEmpty else { return 0 }
        return text.components(separatedBy: token).count - 1
    }
}

private struct ImportProcessOutput {
    let status: Int32
    let stdout: Data
    let stderr: Data

    var stderrString: String {
        String(data: stderr, encoding: .utf8) ?? ""
    }
}

private enum ImportProcessRunner {
    static func run(
        executablePath: String,
        arguments: [String],
        timeoutSeconds: TimeInterval = 45
    ) throws -> ImportProcessOutput {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executablePath)
        process.arguments = arguments

        let stdoutPipe = Pipe()
        let stderrPipe = Pipe()
        process.standardOutput = stdoutPipe
        process.standardError = stderrPipe

        var stdoutData = Data()
        var stderrData = Data()
        let ioLock = NSLock()
        let ioGroup = DispatchGroup()

        ioGroup.enter()
        DispatchQueue.global(qos: .utility).async {
            let data = stdoutPipe.fileHandleForReading.readDataToEndOfFile()
            ioLock.lock()
            stdoutData = data
            ioLock.unlock()
            ioGroup.leave()
        }

        ioGroup.enter()
        DispatchQueue.global(qos: .utility).async {
            let data = stderrPipe.fileHandleForReading.readDataToEndOfFile()
            ioLock.lock()
            stderrData = data
            ioLock.unlock()
            ioGroup.leave()
        }

        do {
            try process.run()
        } catch {
            throw WordImportServiceError.failedToLaunchTool(error.localizedDescription)
        }

        let deadline = Date().addingTimeInterval(timeoutSeconds)
        while process.isRunning, Date() < deadline {
            Thread.sleep(forTimeInterval: 0.05)
        }

        if process.isRunning {
            process.terminate()
            process.waitUntilExit()
            _ = ioGroup.wait(timeout: .now() + 2)
            let command = ([URL(fileURLWithPath: executablePath).lastPathComponent] + arguments).joined(separator: " ")
            throw WordImportServiceError.processTimedOut(command: command, timeoutSeconds: timeoutSeconds)
        }

        process.waitUntilExit()
        ioGroup.wait()

        return ImportProcessOutput(
            status: process.terminationStatus,
            stdout: stdoutData,
            stderr: stderrData
        )
    }
}

private struct ImportedLineDraft {
    var speaker: String
    var text: String
    var startTimecode: String
    var endTimecode: String

    var isMeaningful: Bool {
        !speaker.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ||
            !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ||
            !startTimecode.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ||
            !endTimecode.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
}

private struct WordXMLTable {
    var rows: [[String]] = []
}

private struct WordXMLDocument {
    var paragraphs: [String] = []
    var tables: [WordXMLTable] = []
}

private enum WordXMLExtractor {
    static func extract(from xml: String) throws -> WordXMLDocument {
        guard let data = xml.data(using: .utf8) else {
            throw WordImportServiceError.documentXMLDecodingFailed
        }
        let parser = XMLParser(data: data)
        let delegate = Delegate()
        parser.delegate = delegate
        parser.shouldResolveExternalEntities = false
        parser.shouldProcessNamespaces = false
        parser.shouldReportNamespacePrefixes = false
        let ok = parser.parse()
        guard ok else {
            throw WordImportServiceError.xmlParsingFailed(parser.parserError?.localizedDescription ?? "Neznama chyba.")
        }
        return delegate.document
    }

    private final class Delegate: NSObject, XMLParserDelegate {
        private(set) var document = WordXMLDocument()

        private var tableDepth = 0
        private var currentTable = WordXMLTable()
        private var currentRowCells: [String]?
        private var currentCellParagraphs: [String]?
        private var currentParagraphText: String?
        private var paragraphIsInsideTable = false
        private var isCollectingTextNode = false

        func parser(_: XMLParser, didStartElement elementName: String, namespaceURI _: String?, qualifiedName _: String?, attributes _: [String: String] = [:]) {
            switch elementName {
            case "w:tbl":
                if tableDepth == 0 {
                    currentTable = WordXMLTable()
                }
                tableDepth += 1
            case "w:tr":
                if tableDepth > 0 {
                    currentRowCells = []
                }
            case "w:tc":
                if tableDepth > 0 {
                    currentCellParagraphs = []
                }
            case "w:p":
                currentParagraphText = ""
                paragraphIsInsideTable = tableDepth > 0
            case "w:t":
                isCollectingTextNode = true
            case "w:tab":
                if currentParagraphText != nil {
                    currentParagraphText?.append("\t")
                }
            case "w:br", "w:cr":
                if currentParagraphText != nil {
                    currentParagraphText?.append("\n")
                }
            default:
                break
            }
        }

        func parser(_: XMLParser, foundCharacters string: String) {
            guard isCollectingTextNode else { return }
            currentParagraphText?.append(string)
        }

        func parser(_: XMLParser, didEndElement elementName: String, namespaceURI _: String?, qualifiedName _: String?) {
            switch elementName {
            case "w:t":
                isCollectingTextNode = false
            case "w:p":
                let value = currentParagraphText ?? ""
                let normalized = value
                    .replacingOccurrences(of: "\u{00A0}", with: " ")
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                if !normalized.isEmpty {
                    if paragraphIsInsideTable {
                        currentCellParagraphs?.append(normalized)
                    } else {
                        document.paragraphs.append(normalized)
                    }
                }
                currentParagraphText = nil
                paragraphIsInsideTable = false
            case "w:tc":
                if var row = currentRowCells {
                    let cellText = (currentCellParagraphs ?? [])
                        .filter { !$0.isEmpty }
                        .joined(separator: "\n")
                    row.append(cellText)
                    currentRowCells = row
                }
                currentCellParagraphs = nil
            case "w:tr":
                if let row = currentRowCells {
                    currentTable.rows.append(row)
                }
                currentRowCells = nil
            case "w:tbl":
                if tableDepth > 0 {
                    tableDepth -= 1
                }
                if tableDepth == 0 {
                    document.tables.append(currentTable)
                    currentTable = WordXMLTable()
                }
            default:
                break
            }
        }
    }
}
