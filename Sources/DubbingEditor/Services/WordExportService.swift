import Foundation

enum WordExportServiceError: LocalizedError {
    case noRowsToExport
    case unsupportedOutputURL(URL)
    case failedToLaunchTool(String)
    case conversionFailed(String)
    case processTimedOut(command: String, timeoutSeconds: TimeInterval)

    var errorDescription: String? {
        switch self {
        case .noRowsToExport:
            return "Export nema zadna data."
        case .unsupportedOutputURL(let url):
            return "Nepodporovana cilova cesta pro export: \(url.path)"
        case .failedToLaunchTool(let details):
            return "Nepodarilo se spustit systemovy nastroj. \(details)"
        case .conversionFailed(let details):
            return "Nepodarilo se vytvorit DOCX. \(details)"
        case .processTimedOut(let command, let timeoutSeconds):
            return "Export se zasekl pri prikazu '\(command)' a byl ukoncen po \(Int(timeoutSeconds))s."
        }
    }
}

struct WordExportService {
    private static let classicTemplatePathDefaultsKey = "word_export_classic_template_path"
    private static let classicLockedTemplatePathDefaultsKey = "word_export_classic_locked_template_path"
    private static let classicLockedTemplateSourcePathDefaultsKey = "word_export_classic_locked_template_source_path"
    private static let iyunoTemplatePathDefaultsKey = "word_export_iyuno_template_path"
    private static let iyunoLockedTemplatePathDefaultsKey = "word_export_iyuno_locked_template_path"
    private static let iyunoLockedTemplateSourcePathDefaultsKey = "word_export_iyuno_locked_template_source_path"
    private static let defaultClassicTemplatePath = "/Users/philipkiulpekidis/Dropbox/Dabing/BabiDabi/Veronika/VeronikaS03/Klasicky-format.docx"
    private static let defaultIyunoTemplatePath = "/Users/philipkiulpekidis/Dropbox/Dabing/SDi/MIA/IYUNO-table-docx.docx"

    private enum IyunoTableLayout {
        // Widths copied from IYUNO template proportions (95.3 / 63.8 / 56.7 / 269.4 px).
        static let speakerWidth = 1_430
        static let timecodeWidth = 957
        static let blankWidth = 851
        static let textWidth = 4_041
        static let tableWidth = speakerWidth + timecodeWidth + blankWidth + textWidth
        static let borderColor = "BFBFBF"
        static let bodyBorderColor = "808080"
        static let speakerFontSizeHalfPoints = 24 // 12 pt
        static let timecodeFontSizeHalfPoints = 22 // 11 pt
        static let textFontSizeHalfPoints = 22 // 11 pt
        static let blankFontSizeHalfPoints = 22 // 11 pt
        static let cellPaddingDxa = 75 // approx 5px
    }

    func exportDocx(
        draft: WordExportDraft,
        to destinationURL: URL
    ) throws {
        guard !draft.rows.isEmpty else {
            throw WordExportServiceError.noRowsToExport
        }
        guard destinationURL.isFileURL else {
            throw WordExportServiceError.unsupportedOutputURL(destinationURL)
        }

        let finalDestinationURL = normalizedDocxDestinationURL(destinationURL)
        let tempRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent("DubbingEditor-WordExport-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempRoot, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempRoot) }

        switch draft.profile {
        case .classic:
            try exportClassicDocx(draft: draft, destinationURL: finalDestinationURL, in: tempRoot)
        case .sdi:
            try exportIyunoDocx(draft: draft, destinationURL: finalDestinationURL, tempRoot: tempRoot)
        }

        guard FileManager.default.fileExists(atPath: finalDestinationURL.path) else {
            throw WordExportServiceError.conversionFailed("Vystupni soubor nebyl vytvoren.")
        }
    }

    func makePlainTextDocument(from draft: WordExportDraft) -> String {
        let lines = draft.rows.map(\.tabSeparated)
        return lines.joined(separator: "\n") + "\n"
    }

    func makeIyunoDocumentXML(from draft: WordExportDraft) -> String {
        let headerRowXML = makeIyunoHeaderRowXML()
        let rowsXML = draft.rows.map(makeIyunoTableRowXML(_:)).joined()
        return """
        <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
        <w:document xmlns:ve="http://schemas.openxmlformats.org/markup-compatibility/2006" xmlns:o="urn:schemas-microsoft-com:office:office" xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships" xmlns:v="urn:schemas-microsoft-com:vml" xmlns:wp="http://schemas.openxmlformats.org/drawingml/2006/wordprocessingDrawing" xmlns:w10="urn:schemas-microsoft-com:office:word" xmlns:w="http://schemas.openxmlformats.org/wordprocessingml/2006/main">
          <w:body>
            <w:tbl>
              <w:tblPr>
                <w:tblW w:w="\(IyunoTableLayout.tableWidth)" w:type="dxa"/>
                <w:tblLayout w:type="fixed"/>
                <w:jc w:val="center"/>
                <w:tblCellMar>
                  <w:left w:w="\(IyunoTableLayout.cellPaddingDxa)" w:type="dxa"/>
                  <w:right w:w="\(IyunoTableLayout.cellPaddingDxa)" w:type="dxa"/>
                </w:tblCellMar>
                <w:tblBorders>
                  <w:top w:val="single" w:sz="4" w:space="0" w:color="\(IyunoTableLayout.borderColor)"/>
                  <w:left w:val="single" w:sz="4" w:space="0" w:color="\(IyunoTableLayout.borderColor)"/>
                  <w:bottom w:val="single" w:sz="4" w:space="0" w:color="\(IyunoTableLayout.borderColor)"/>
                  <w:right w:val="single" w:sz="4" w:space="0" w:color="\(IyunoTableLayout.borderColor)"/>
                  <w:insideH w:val="single" w:sz="4" w:space="0" w:color="\(IyunoTableLayout.borderColor)"/>
                  <w:insideV w:val="single" w:sz="4" w:space="0" w:color="\(IyunoTableLayout.borderColor)"/>
                </w:tblBorders>
              </w:tblPr>
              <w:tblGrid>
                <w:gridCol w:w="\(IyunoTableLayout.speakerWidth)"/>
                <w:gridCol w:w="\(IyunoTableLayout.timecodeWidth)"/>
                <w:gridCol w:w="\(IyunoTableLayout.blankWidth)"/>
                <w:gridCol w:w="\(IyunoTableLayout.textWidth)"/>
              </w:tblGrid>
              \(headerRowXML)
              \(rowsXML)
            </w:tbl>
            <w:sectPr>
              <w:pgSz w:w="12240" w:h="15840"/>
              <w:pgMar w:top="1440" w:right="1800" w:bottom="1440" w:left="1800"/>
            </w:sectPr>
          </w:body>
        </w:document>
        """
    }

    private func normalizedDocxDestinationURL(_ url: URL) -> URL {
        if url.pathExtension.lowercased() == "docx" {
            return url
        }
        return url.appendingPathExtension("docx")
    }

    private func exportClassicDocx(
        draft: WordExportDraft,
        destinationURL: URL,
        in tempRoot: URL
    ) throws {
        let templateURL = try prepareLockedClassicTemplateURL(tempRoot: tempRoot)
        let sourceDocxURL: URL
        if let templateURL {
            sourceDocxURL = try makeTemplateDocxURL(from: templateURL, tempRoot: tempRoot)
        } else {
            let sourceTextURL = tempRoot.appendingPathComponent("export.txt")
            let plainText = makePlainTextDocument(from: draft)
            try plainText.write(to: sourceTextURL, atomically: true, encoding: .utf8)

            let fallbackDocxURL = tempRoot.appendingPathComponent("classic-fallback.docx")
            let output = try ExportProcessRunner.run(
                executablePath: "/usr/bin/textutil",
                arguments: [
                    "-convert", "docx",
                    "-format", "txt",
                    "-inputencoding", "UTF-8",
                    "-output", fallbackDocxURL.path,
                    sourceTextURL.path
                ]
            )
            guard output.status == 0 else {
                let details = output.stderrString.trimmingCharacters(in: .whitespacesAndNewlines)
                throw WordExportServiceError.conversionFailed(details.isEmpty ? "textutil vratil chybu." : details)
            }
            sourceDocxURL = fallbackDocxURL
        }

        let unpackURL = tempRoot.appendingPathComponent("classic-unpacked", isDirectory: true)
        try FileManager.default.createDirectory(at: unpackURL, withIntermediateDirectories: true)

        let unzipOutput = try ExportProcessRunner.run(
            executablePath: "/usr/bin/unzip",
            arguments: ["-q", sourceDocxURL.path, "-d", unpackURL.path]
        )
        guard unzipOutput.status == 0 else {
            let details = unzipOutput.stderrString.trimmingCharacters(in: .whitespacesAndNewlines)
            throw WordExportServiceError.conversionFailed(details.isEmpty ? "Nepodarilo se rozbalit DOCX." : details)
        }

        if templateURL != nil {
            let documentXMLURL = unpackURL.appendingPathComponent("word/document.xml")
            let sourceXML = try String(contentsOf: documentXMLURL, encoding: .utf8)
            let xml = try applyClassicTemplate(to: sourceXML, rows: draft.rows)
            try xml.write(to: documentXMLURL, atomically: true, encoding: .utf8)
        }

        if FileManager.default.fileExists(atPath: destinationURL.path) {
            try FileManager.default.removeItem(at: destinationURL)
        }

        let zipOutput = try ExportProcessRunner.run(
            executablePath: "/usr/bin/ditto",
            arguments: ["-c", "-k", "--norsrc", unpackURL.path, destinationURL.path]
        )
        guard zipOutput.status == 0 else {
            let details = zipOutput.stderrString.trimmingCharacters(in: .whitespacesAndNewlines)
            throw WordExportServiceError.conversionFailed(details.isEmpty ? "Nepodarilo se zabalit DOCX." : details)
        }
    }

    private func exportIyunoDocx(
        draft: WordExportDraft,
        destinationURL: URL,
        tempRoot: URL
    ) throws {
        let templateURL = try prepareLockedIyunoTemplateURL(tempRoot: tempRoot)
        let sourceDocxURL: URL
        if let templateURL {
            sourceDocxURL = try makeTemplateDocxURL(from: templateURL, tempRoot: tempRoot)
        } else {
            // Fallback to generated minimal DOCX container.
            let baseTextURL = tempRoot.appendingPathComponent("base.txt")
            try "base".write(to: baseTextURL, atomically: true, encoding: .utf8)

            let baseDocxURL = tempRoot.appendingPathComponent("base.docx")
            let conversionOutput = try ExportProcessRunner.run(
                executablePath: "/usr/bin/textutil",
                arguments: [
                    "-convert", "docx",
                    "-format", "txt",
                    "-inputencoding", "UTF-8",
                    "-output", baseDocxURL.path,
                    baseTextURL.path
                ]
            )
            guard conversionOutput.status == 0 else {
                let details = conversionOutput.stderrString.trimmingCharacters(in: .whitespacesAndNewlines)
                throw WordExportServiceError.conversionFailed(details.isEmpty ? "textutil vratil chybu." : details)
            }
            sourceDocxURL = baseDocxURL
        }

        let unpackURL = tempRoot.appendingPathComponent("unpacked", isDirectory: true)
        try FileManager.default.createDirectory(at: unpackURL, withIntermediateDirectories: true)

        let unzipOutput = try ExportProcessRunner.run(
            executablePath: "/usr/bin/unzip",
            arguments: ["-q", sourceDocxURL.path, "-d", unpackURL.path]
        )
        guard unzipOutput.status == 0 else {
            let details = unzipOutput.stderrString.trimmingCharacters(in: .whitespacesAndNewlines)
            throw WordExportServiceError.conversionFailed(details.isEmpty ? "Nepodarilo se rozbalit DOCX." : details)
        }

        let documentXMLURL = unpackURL.appendingPathComponent("word/document.xml")
        let sourceXML = try String(contentsOf: documentXMLURL, encoding: .utf8)
        let xml: String
        if templateURL != nil {
            xml = try applyIyunoTemplate(to: sourceXML, rows: draft.rows)
        } else {
            xml = makeIyunoDocumentXML(from: draft)
        }
        try xml.write(to: documentXMLURL, atomically: true, encoding: .utf8)

        if FileManager.default.fileExists(atPath: destinationURL.path) {
            try FileManager.default.removeItem(at: destinationURL)
        }

        let zipOutput = try ExportProcessRunner.run(
            executablePath: "/usr/bin/ditto",
            arguments: ["-c", "-k", "--norsrc", unpackURL.path, destinationURL.path]
        )
        guard zipOutput.status == 0 else {
            let details = zipOutput.stderrString.trimmingCharacters(in: .whitespacesAndNewlines)
            throw WordExportServiceError.conversionFailed(details.isEmpty ? "Nepodarilo se zabalit DOCX." : details)
        }
    }

    private func resolveClassicTemplateSourceURL() -> URL? {
        let defaults = UserDefaults.standard
        if
            let customPath = defaults.string(forKey: Self.classicTemplatePathDefaultsKey),
            !customPath.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        {
            let customURL = URL(fileURLWithPath: customPath)
            if FileManager.default.fileExists(atPath: customURL.path) {
                return customURL
            }
        }

        let defaultURL = URL(fileURLWithPath: Self.defaultClassicTemplatePath)
        if FileManager.default.fileExists(atPath: defaultURL.path) {
            return defaultURL
        }
        return nil
    }

    private func resolveIyunoTemplateSourceURL() -> URL? {
        let defaults = UserDefaults.standard
        if
            let customPath = defaults.string(forKey: Self.iyunoTemplatePathDefaultsKey),
            !customPath.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        {
            let customURL = URL(fileURLWithPath: customPath)
            if FileManager.default.fileExists(atPath: customURL.path) {
                return customURL
            }
        }

        let defaultURL = URL(fileURLWithPath: Self.defaultIyunoTemplatePath)
        if FileManager.default.fileExists(atPath: defaultURL.path) {
            return defaultURL
        }
        return nil
    }

    private func lockedIyunoTemplateURL() throws -> URL {
        let fm = FileManager.default
        let appSupportRoot = try fm.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )
        let appFolder = appSupportRoot.appendingPathComponent("DubbingEditor", isDirectory: true)
        let templatesFolder = appFolder.appendingPathComponent("Templates", isDirectory: true)
        try fm.createDirectory(at: templatesFolder, withIntermediateDirectories: true)
        return templatesFolder.appendingPathComponent("iyuno-template-locked.docx")
    }

    private func lockedClassicTemplateURL() throws -> URL {
        let fm = FileManager.default
        let appSupportRoot = try fm.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )
        let appFolder = appSupportRoot.appendingPathComponent("DubbingEditor", isDirectory: true)
        let templatesFolder = appFolder.appendingPathComponent("Templates", isDirectory: true)
        try fm.createDirectory(at: templatesFolder, withIntermediateDirectories: true)
        return templatesFolder.appendingPathComponent("classic-template-locked.docx")
    }

    private func prepareLockedClassicTemplateURL(tempRoot: URL) throws -> URL? {
        let defaults = UserDefaults.standard
        let fm = FileManager.default

        let sourceURL = resolveClassicTemplateSourceURL()
        let sourcePath = sourceURL?.standardizedFileURL.path
        let previouslyLockedPath = defaults.string(forKey: Self.classicLockedTemplatePathDefaultsKey)
        let previouslyLockedSourcePath = defaults.string(forKey: Self.classicLockedTemplateSourcePathDefaultsKey)

        if
            let previouslyLockedPath,
            !previouslyLockedPath.isEmpty,
            fm.fileExists(atPath: previouslyLockedPath)
        {
            if sourcePath == nil || sourcePath == previouslyLockedSourcePath {
                return URL(fileURLWithPath: previouslyLockedPath)
            }
        }

        let lockedURL = try lockedClassicTemplateURL()
        if
            sourcePath == nil,
            fm.fileExists(atPath: lockedURL.path)
        {
            defaults.set(lockedURL.path, forKey: Self.classicLockedTemplatePathDefaultsKey)
            return lockedURL
        }

        guard let sourceURL else {
            return nil
        }

        let docxSourceURL = try makeTemplateDocxURL(from: sourceURL, tempRoot: tempRoot)
        if lockedURL.path != docxSourceURL.path {
            if fm.fileExists(atPath: lockedURL.path) {
                try fm.removeItem(at: lockedURL)
            }
            try fm.copyItem(at: docxSourceURL, to: lockedURL)
        }

        defaults.set(lockedURL.path, forKey: Self.classicLockedTemplatePathDefaultsKey)
        if let sourcePath {
            defaults.set(sourcePath, forKey: Self.classicLockedTemplateSourcePathDefaultsKey)
        }
        return lockedURL
    }

    private func prepareLockedIyunoTemplateURL(tempRoot: URL) throws -> URL? {
        let defaults = UserDefaults.standard
        let fm = FileManager.default

        let sourceURL = resolveIyunoTemplateSourceURL()
        let sourcePath = sourceURL?.standardizedFileURL.path
        let previouslyLockedPath = defaults.string(forKey: Self.iyunoLockedTemplatePathDefaultsKey)
        let previouslyLockedSourcePath = defaults.string(forKey: Self.iyunoLockedTemplateSourcePathDefaultsKey)

        if
            let previouslyLockedPath,
            !previouslyLockedPath.isEmpty,
            fm.fileExists(atPath: previouslyLockedPath)
        {
            // Keep the locked template unless the user changed source template path.
            if sourcePath == nil || sourcePath == previouslyLockedSourcePath {
                return URL(fileURLWithPath: previouslyLockedPath)
            }
        }

        let lockedURL = try lockedIyunoTemplateURL()
        if
            sourcePath == nil,
            fm.fileExists(atPath: lockedURL.path)
        {
            defaults.set(lockedURL.path, forKey: Self.iyunoLockedTemplatePathDefaultsKey)
            return lockedURL
        }

        guard let sourceURL else {
            return nil
        }

        let docxSourceURL = try makeTemplateDocxURL(from: sourceURL, tempRoot: tempRoot)
        if lockedURL.path != docxSourceURL.path {
            if fm.fileExists(atPath: lockedURL.path) {
                try fm.removeItem(at: lockedURL)
            }
            try fm.copyItem(at: docxSourceURL, to: lockedURL)
        }

        defaults.set(lockedURL.path, forKey: Self.iyunoLockedTemplatePathDefaultsKey)
        if let sourcePath {
            defaults.set(sourcePath, forKey: Self.iyunoLockedTemplateSourcePathDefaultsKey)
        }
        return lockedURL
    }

    private func makeTemplateDocxURL(from sourceURL: URL, tempRoot: URL) throws -> URL {
        let ext = sourceURL.pathExtension.lowercased()
        if ext == "docx" {
            return sourceURL
        }

        let outputURL = tempRoot.appendingPathComponent("iyuno-template.docx")
        let conversionOutput = try ExportProcessRunner.run(
            executablePath: "/usr/bin/textutil",
            arguments: [
                "-convert", "docx",
                "-output", outputURL.path,
                sourceURL.path
            ]
        )
        guard conversionOutput.status == 0 else {
            let details = conversionOutput.stderrString.trimmingCharacters(in: .whitespacesAndNewlines)
            throw WordExportServiceError.conversionFailed(
                details.isEmpty
                    ? "Nepodarilo se prevest IYUNO sablonu na DOCX."
                    : details
            )
        }
        return outputURL
    }

    private func makeIyunoHTMLDocument(draft: WordExportDraft, tempRoot: URL) throws -> String {
        if
            let templateURL = resolveIyunoTemplateSourceURL(),
            let templateHTML = try? loadIyunoTemplateHTML(from: templateURL, tempRoot: tempRoot),
            let patchedHTML = try? applyIyunoTemplateHTML(to: templateHTML, rows: draft.rows)
        {
            return patchedHTML
        }
        return makeFallbackIyunoHTML(rows: draft.rows)
    }

    private func loadIyunoTemplateHTML(from sourceURL: URL, tempRoot: URL) throws -> String {
        let ext = sourceURL.pathExtension.lowercased()
        if ext == "html" || ext == "htm" {
            return try String(contentsOf: sourceURL, encoding: .utf8)
        }

        let htmlURL = tempRoot.appendingPathComponent("iyuno-template.html")
        let output = try ExportProcessRunner.run(
            executablePath: "/usr/bin/textutil",
            arguments: [
                "-convert", "html",
                "-output", htmlURL.path,
                sourceURL.path
            ]
        )
        guard output.status == 0 else {
            let details = output.stderrString.trimmingCharacters(in: .whitespacesAndNewlines)
            throw WordExportServiceError.conversionFailed(details.isEmpty ? "Nepodarilo se prevest IYUNO sablonu do HTML." : details)
        }
        return try String(contentsOf: htmlURL, encoding: .utf8)
    }

    private func applyIyunoTemplateHTML(to templateHTML: String, rows: [WordExportRow]) throws -> String {
        guard let tableRange = firstRegexRange(pattern: #"(?is)<table\b.*?</table>"#, in: templateHTML) else {
            throw WordExportServiceError.conversionFailed("IYUNO sablona neobsahuje HTML tabulku.")
        }

        let tableHTML = String(templateHTML[tableRange])
        let rowRanges = regexRanges(pattern: #"(?is)<tr\b.*?</tr>"#, in: tableHTML)
        guard !rowRanges.isEmpty else {
            throw WordExportServiceError.conversionFailed("IYUNO sablona neobsahuje radky tabulky.")
        }

        let headerRowHTML = String(tableHTML[rowRanges[0]])
        let bodyTemplateRowHTML = rowRanges.count > 1 ? String(tableHTML[rowRanges[1]]) : headerRowHTML
        let bodyRowsHTML = rows.compactMap { makeIyunoBodyHTMLRow(from: bodyTemplateRowHTML, row: $0) }
        if bodyRowsHTML.count != rows.count {
            throw WordExportServiceError.conversionFailed("IYUNO sablona ma neplatnou strukturu bunek.")
        }

        guard let patchedTableHTML = replaceHTMLRows(in: tableHTML, with: [headerRowHTML] + bodyRowsHTML) else {
            throw WordExportServiceError.conversionFailed("Nepodarilo se aktualizovat HTML tabulku.")
        }

        var result = templateHTML
        result.replaceSubrange(tableRange, with: patchedTableHTML)
        return result
    }

    private func makeIyunoBodyHTMLRow(from templateRowHTML: String, row: WordExportRow) -> String? {
        let cellRanges = regexRanges(pattern: #"(?is)<(?:td|th)\b.*?</(?:td|th)>"#, in: templateRowHTML)
        guard cellRanges.count >= 4 else { return nil }
        let templateCells = cellRanges.map { String(templateRowHTML[$0]) }
        guard
            let speakerCell = replacedHTMLCellText(templateCellHTML: templateCells[0], with: row.speaker),
            let tcCell = replacedHTMLCellText(templateCellHTML: templateCells[1], with: row.timecode),
            let noteCell = replacedHTMLCellText(templateCellHTML: templateCells[2], with: ""),
            let textCell = replacedHTMLCellText(templateCellHTML: templateCells[3], with: row.text)
        else {
            return nil
        }
        return "<tr>\(speakerCell)\(tcCell)\(noteCell)\(textCell)</tr>"
    }

    private func replacedHTMLCellText(templateCellHTML: String, with text: String) -> String? {
        guard
            let openingTagRange = firstRegexRange(pattern: #"(?is)^<(?:td|th)\b[^>]*>"#, in: templateCellHTML),
            let closingTagRange = firstRegexRange(pattern: #"(?is)</(?:td|th)>\s*$"#, in: templateCellHTML)
        else {
            return nil
        }

        let openingTag = String(templateCellHTML[openingTagRange])
        let closingTag = String(templateCellHTML[closingTagRange])
        let paragraphOpen = firstRegexSubstring(pattern: #"(?is)<p\b[^>]*>"#, in: templateCellHTML)
        let escaped = htmlEscaped(text).replacingOccurrences(of: "\n", with: "<br>")
        let bodyText = escaped.isEmpty ? "&nbsp;" : escaped

        let content: String
        if let paragraphOpen {
            content = "\(paragraphOpen)\(bodyText)</p>"
        } else {
            content = bodyText
        }

        return "\(openingTag)\(content)\(closingTag)"
    }

    private func replaceHTMLRows(in tableHTML: String, with rowsHTML: [String]) -> String? {
        let rowRanges = regexRanges(pattern: #"(?is)<tr\b.*?</tr>"#, in: tableHTML)
        guard let first = rowRanges.first, let last = rowRanges.last else { return nil }
        var updated = tableHTML
        updated.replaceSubrange(first.lowerBound..<last.upperBound, with: rowsHTML.joined())
        return updated
    }

    private func makeFallbackIyunoHTML(rows: [WordExportRow]) -> String {
        let header = """
        <tr><th>Character</th><th>TC</th><th>Note</th><th>TEXT</th></tr>
        """
        let body = rows.map { row in
            """
            <tr><td>\(htmlEscaped(row.speaker))</td><td>\(htmlEscaped(row.timecode))</td><td>&nbsp;</td><td>\(htmlEscaped(row.text).replacingOccurrences(of: "\n", with: "<br>"))</td></tr>
            """
        }.joined()

        return """
        <!DOCTYPE html>
        <html><head><meta charset="utf-8"><style>
        body { font-family: 'Times New Roman', serif; }
        table { border-collapse: collapse; width: 100%; }
        th, td { border: 1px solid #A0A0A0; padding: 6px 8px; vertical-align: top; font-size: 16px; }
        th { text-align: center; font-weight: bold; }
        td:nth-child(2) { text-align: center; vertical-align: middle; }
        </style></head><body><table>\(header)\(body)</table></body></html>
        """
    }

    private func applyIyunoTemplate(to documentXML: String, rows: [WordExportRow]) throws -> String {
        guard
            let tableRange = findIyunoTableRange(in: documentXML)
                ?? firstRegexRange(pattern: #"(?s)<w:tbl\b.*?</w:tbl>"#, in: documentXML)
                ?? firstTableRange(in: documentXML)
        else {
            throw WordExportServiceError.conversionFailed("IYUNO sablona neobsahuje tabulku.")
        }
        let tableXML = String(documentXML[tableRange])

        let rowRanges = regexRanges(pattern: #"(?s)<w:tr\b.*?</w:tr>"#, in: tableXML)
        guard !rowRanges.isEmpty else {
            throw WordExportServiceError.conversionFailed("IYUNO sablona neobsahuje radky tabulky.")
        }

        let headerRowXML = String(tableXML[rowRanges[0]])
        let bodyTemplateRowXML = rowRanges.count > 1 ? String(tableXML[rowRanges[1]]) : headerRowXML
        let bodyRowsXML = rows.compactMap { makeIyunoBodyRowXML(from: bodyTemplateRowXML, row: $0) }
        if bodyRowsXML.count != rows.count {
            throw WordExportServiceError.conversionFailed("IYUNO sablona ma neplatnou strukturu bunek.")
        }

        let replacementRows = [headerRowXML] + bodyRowsXML
        guard let patchedTableXML = replaceRows(in: tableXML, with: replacementRows) else {
            throw WordExportServiceError.conversionFailed("Nepodarilo se aktualizovat radky IYUNO tabulky.")
        }

        var xml = documentXML
        xml.replaceSubrange(tableRange, with: patchedTableXML)
        return xml
    }

    private func applyClassicTemplate(to documentXML: String, rows: [WordExportRow]) throws -> String {
        let paragraphRanges = regexRanges(pattern: #"(?s)<w:p\b.*?</w:p>"#, in: documentXML)
        guard !paragraphRanges.isEmpty else {
            throw WordExportServiceError.conversionFailed("Klasicka sablona neobsahuje odstavce.")
        }

        let candidateIndices = paragraphRanges.enumerated().compactMap { index, range in
            let paragraph = String(documentXML[range])
            return paragraphHasClassicColumns(paragraph) ? index : nil
        }
        guard let firstIndex = candidateIndices.first, let lastIndex = candidateIndices.last else {
            throw WordExportServiceError.conversionFailed("Klasicka sablona neobsahuje radky s tabulatory.")
        }

        let templateParagraph = String(documentXML[paragraphRanges[firstIndex]])
        let replacementParagraphs = rows.map { makeClassicParagraph(from: templateParagraph, row: $0) }.joined()

        var xml = documentXML
        let firstRange = paragraphRanges[firstIndex]
        let lastRange = paragraphRanges[lastIndex]
        xml.replaceSubrange(firstRange.lowerBound..<lastRange.upperBound, with: replacementParagraphs)
        return xml
    }

    private func paragraphHasClassicColumns(_ paragraphXML: String) -> Bool {
        let tabMarkers = paragraphXML.components(separatedBy: "<w:tab").count - 1
        if tabMarkers >= 2 {
            return true
        }
        return paragraphXML.contains("\t")
    }

    private func makeClassicParagraph(from templateParagraphXML: String, row: WordExportRow) -> String {
        let pOpen = firstRegexSubstring(pattern: #"(?s)^<w:p\b[^>]*>"#, in: templateParagraphXML) ?? "<w:p>"
        let pPr = firstRegexSubstring(pattern: #"(?s)<w:pPr>.*?</w:pPr>"#, in: templateParagraphXML) ?? "<w:pPr/>"
        let rPr = firstRegexSubstring(pattern: #"(?s)<w:rPr>.*?</w:rPr>"#, in: templateParagraphXML) ?? "<w:rPr/>"

        let speaker = xmlEscaped(row.speaker)
        let timecode = xmlEscaped(row.timecode)
        let text = xmlEscaped(row.text)
        let speakerText = speaker.isEmpty ? " " : speaker
        let timecodeText = timecode.isEmpty ? " " : timecode
        let valueText = text.isEmpty ? " " : text

        let runs = """
        <w:r>\(rPr)<w:t xml:space="preserve">\(speakerText)</w:t></w:r><w:r>\(rPr)<w:tab/></w:r><w:r>\(rPr)<w:t xml:space="preserve">\(timecodeText)</w:t></w:r><w:r>\(rPr)<w:tab/></w:r><w:r>\(rPr)<w:t xml:space="preserve">\(valueText)</w:t></w:r>
        """
        return "\(pOpen)\(pPr)\(runs)</w:p>"
    }

    private func findIyunoTableRange(in documentXML: String) -> Range<String.Index>? {
        let tableRanges = regexRanges(pattern: #"(?s)<w:tbl\b.*?</w:tbl>"#, in: documentXML)
        for range in tableRanges {
            let tableXML = String(documentXML[range]).lowercased()
            if
                tableXML.contains("character"),
                tableXML.contains(">tc<"),
                tableXML.contains("note"),
                tableXML.contains(">text<")
            {
                return range
            }
        }
        return nil
    }

    private func firstTableRange(in text: String) -> Range<String.Index>? {
        var searchStart = text.startIndex
        while searchStart < text.endIndex {
            guard let markerRange = text.range(of: "<w:tbl", range: searchStart..<text.endIndex) else {
                return nil
            }

            let suffixIndex = text.index(markerRange.lowerBound, offsetBy: "<w:tbl".count)
            let isTableTag: Bool
            if suffixIndex < text.endIndex {
                let next = text[suffixIndex]
                isTableTag = next == ">" || next.isWhitespace
            } else {
                isTableTag = true
            }

            if isTableTag {
                guard let tableEnd = text.range(of: "</w:tbl>", range: markerRange.lowerBound..<text.endIndex) else {
                    return nil
                }
                return markerRange.lowerBound..<tableEnd.upperBound
            }

            searchStart = markerRange.upperBound
        }
        return nil
    }

    private func makeIyunoBodyRowXML(from templateRowXML: String, row: WordExportRow) -> String? {
        let cellRanges = regexRanges(pattern: #"(?s)<w:tc\b.*?</w:tc>"#, in: templateRowXML)
        guard cellRanges.count >= 4 else { return nil }

        let templateCells = cellRanges.map { String(templateRowXML[$0]) }
        guard
            let speakerCell = replacedCellText(templateCellXML: templateCells[0], with: row.speaker),
            let tcCell = replacedCellText(templateCellXML: templateCells[1], with: row.timecode),
            let noteCell = replacedCellText(templateCellXML: templateCells[2], with: ""),
            let textCell = replacedCellText(templateCellXML: templateCells[3], with: row.text)
        else {
            return nil
        }

        let trOpening = firstRegexSubstring(pattern: #"(?s)^<w:tr\b[^>]*>"#, in: templateRowXML) ?? "<w:tr>"
        let trPr = firstRegexSubstring(pattern: #"(?s)<w:trPr>.*?</w:trPr>"#, in: templateRowXML) ?? ""
        return "\(trOpening)\(trPr)\(speakerCell)\(tcCell)\(noteCell)\(textCell)</w:tr>"
    }

    private func replacedCellText(templateCellXML: String, with text: String) -> String? {
        guard
            let tcOpening = firstRegexRange(pattern: #"(?s)^<w:tc\b[^>]*>"#, in: templateCellXML),
            let tcClosing = firstRegexRange(pattern: #"(?s)</w:tc>\s*$"#, in: templateCellXML),
            let tcPrRange = firstRegexRange(pattern: #"(?s)<w:tcPr>.*?</w:tcPr>"#, in: templateCellXML),
            let pRange = firstRegexRange(pattern: #"(?s)<w:p\b.*?</w:p>"#, in: templateCellXML)
        else {
            return nil
        }
        let tcOpen = String(templateCellXML[tcOpening])
        let tcClose = String(templateCellXML[tcClosing])
        let tcPr = String(templateCellXML[tcPrRange])
        let firstParagraph = String(templateCellXML[pRange])
        let pPr = firstRegexSubstring(pattern: #"(?s)<w:pPr>.*?</w:pPr>"#, in: firstParagraph) ?? "<w:pPr/>"
        let rPr = firstRegexSubstring(pattern: #"(?s)<w:rPr>.*?</w:rPr>"#, in: firstParagraph) ?? "<w:rPr/>"
        let textRuns = makeWordTextRuns(text)
        return "\(tcOpen)\(tcPr)<w:p>\(pPr)<w:r>\(rPr)\(textRuns)</w:r></w:p>\(tcClose)"
    }

    private func replaceRows(in tableXML: String, with rowsXML: [String]) -> String? {
        let rowRanges = regexRanges(pattern: #"(?s)<w:tr\b.*?</w:tr>"#, in: tableXML)
        guard let first = rowRanges.first, let last = rowRanges.last else { return nil }
        var updated = tableXML
        updated.replaceSubrange(first.lowerBound..<last.upperBound, with: rowsXML.joined())
        return updated
    }

    private func makeWordTextRuns(_ value: String) -> String {
        let escaped = xmlEscaped(value)
        if escaped.isEmpty {
            return "<w:t xml:space=\"preserve\"> </w:t>"
        }

        let lines = escaped.components(separatedBy: "\n")
        var parts: [String] = []
        for (index, line) in lines.enumerated() {
            if index > 0 {
                parts.append("<w:br/>")
            }
            parts.append("<w:t xml:space=\"preserve\">\(line.isEmpty ? " " : line)</w:t>")
        }
        return parts.joined()
    }

    private func firstRegexSubstring(pattern: String, in text: String) -> String? {
        guard let range = firstRegexRange(pattern: pattern, in: text) else { return nil }
        return String(text[range])
    }

    private func firstRegexRange(pattern: String, in text: String) -> Range<String.Index>? {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: []) else { return nil }
        let nsRange = NSRange(text.startIndex..<text.endIndex, in: text)
        guard let match = regex.firstMatch(in: text, options: [], range: nsRange) else { return nil }
        return Range(match.range, in: text)
    }

    private func regexRanges(pattern: String, in text: String) -> [Range<String.Index>] {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: []) else { return [] }
        let nsRange = NSRange(text.startIndex..<text.endIndex, in: text)
        return regex.matches(in: text, options: [], range: nsRange).compactMap { Range($0.range, in: text) }
    }

    private func makeIyunoHeaderRowXML() -> String {
        let speakerCell = makeIyunoTableCellXML(
            text: "Character",
            width: IyunoTableLayout.speakerWidth,
            centered: true,
            verticalAlignment: "center",
            fontSizeHalfPoints: 24,
            borderColor: IyunoTableLayout.borderColor,
            isBold: true
        )
        let tcCell = makeIyunoTableCellXML(
            text: "TC",
            width: IyunoTableLayout.timecodeWidth,
            centered: true,
            verticalAlignment: "center",
            fontSizeHalfPoints: 24,
            borderColor: IyunoTableLayout.borderColor,
            isBold: true
        )
        let noteCell = makeIyunoTableCellXML(
            text: "Note",
            width: IyunoTableLayout.blankWidth,
            centered: true,
            verticalAlignment: "center",
            fontSizeHalfPoints: 24,
            borderColor: IyunoTableLayout.borderColor,
            isBold: true
        )
        let textCell = makeIyunoTableCellXML(
            text: "TEXT",
            width: IyunoTableLayout.textWidth,
            centered: true,
            verticalAlignment: "center",
            fontSizeHalfPoints: 24,
            borderColor: IyunoTableLayout.borderColor,
            isBold: true
        )
        return "<w:tr>\(speakerCell)\(tcCell)\(noteCell)\(textCell)</w:tr>"
    }

    private func makeIyunoTableRowXML(_ row: WordExportRow) -> String {
        let speakerCell = makeIyunoTableCellXML(
            text: row.speaker,
            width: IyunoTableLayout.speakerWidth,
            centered: false,
            verticalAlignment: "top",
            fontSizeHalfPoints: IyunoTableLayout.speakerFontSizeHalfPoints,
            borderColor: IyunoTableLayout.bodyBorderColor
        )
        let timecodeCell = makeIyunoTableCellXML(
            text: row.timecode,
            width: IyunoTableLayout.timecodeWidth,
            centered: true,
            verticalAlignment: "bottom",
            fontSizeHalfPoints: IyunoTableLayout.timecodeFontSizeHalfPoints,
            borderColor: IyunoTableLayout.bodyBorderColor
        )
        let blankCell = makeIyunoTableCellXML(
            text: "",
            width: IyunoTableLayout.blankWidth,
            centered: false,
            verticalAlignment: "bottom",
            fontSizeHalfPoints: IyunoTableLayout.blankFontSizeHalfPoints,
            borderColor: IyunoTableLayout.bodyBorderColor
        )
        let textCell = makeIyunoTableCellXML(
            text: row.text,
            width: IyunoTableLayout.textWidth,
            centered: false,
            verticalAlignment: "top",
            fontSizeHalfPoints: IyunoTableLayout.textFontSizeHalfPoints,
            borderColor: IyunoTableLayout.bodyBorderColor
        )
        return "<w:tr>\(speakerCell)\(timecodeCell)\(blankCell)\(textCell)</w:tr>"
    }

    private func makeIyunoTableCellXML(
        text: String,
        width: Int,
        centered: Bool,
        verticalAlignment: String,
        fontSizeHalfPoints: Int,
        borderColor: String,
        isBold: Bool = false
    ) -> String {
        let cellText: String
        let escapedText = xmlEscaped(text)
        if escapedText.isEmpty {
            cellText = "<w:t xml:space=\"preserve\"> </w:t>"
        } else {
            let withBreaks = escapedText.replacingOccurrences(of: "\n", with: "</w:t><w:br/><w:t xml:space=\"preserve\">")
            cellText = "<w:t xml:space=\"preserve\">\(withBreaks)</w:t>"
        }

        let paragraphAlignment = centered ? "<w:pPr><w:jc w:val=\"center\"/></w:pPr>" : "<w:pPr/>"
        let boldMarkup = isBold ? "<w:b/><w:bCs/>" : ""
        return """
        <w:tc>
          <w:tcPr>
            <w:tcW w:w="\(width)" w:type="dxa"/>
            <w:vAlign w:val="\(verticalAlignment)"/>
            <w:tcBorders>
              <w:top w:val="single" w:sz="4" w:space="0" w:color="\(borderColor)"/>
              <w:left w:val="single" w:sz="4" w:space="0" w:color="\(borderColor)"/>
              <w:bottom w:val="single" w:sz="4" w:space="0" w:color="\(borderColor)"/>
              <w:right w:val="single" w:sz="4" w:space="0" w:color="\(borderColor)"/>
            </w:tcBorders>
          </w:tcPr>
          <w:p>\(paragraphAlignment)<w:r><w:rPr><w:rFonts w:ascii="Times New Roman" w:hAnsi="Times New Roman" w:cs="Times New Roman"/><w:sz w:val="\(fontSizeHalfPoints)"/><w:szCs w:val="\(fontSizeHalfPoints)"/>\(boldMarkup)</w:rPr>\(cellText)</w:r></w:p>
        </w:tc>
        """
    }

    private func xmlEscaped(_ value: String) -> String {
        var result = xmlSanitized(value)
        let replacements: [(String, String)] = [
            ("&", "&amp;"),
            ("<", "&lt;"),
            (">", "&gt;"),
            ("\"", "&quot;"),
            ("'", "&#39;")
        ]
        for (needle, replacement) in replacements {
            result = result.replacingOccurrences(of: needle, with: replacement)
        }
        return result
    }

    private func htmlEscaped(_ value: String) -> String {
        var result = xmlSanitized(value)
        let replacements: [(String, String)] = [
            ("&", "&amp;"),
            ("<", "&lt;"),
            (">", "&gt;"),
            ("\"", "&quot;"),
            ("'", "&#39;")
        ]
        for (needle, replacement) in replacements {
            result = result.replacingOccurrences(of: needle, with: replacement)
        }
        return result
    }

    private func xmlSanitized(_ value: String) -> String {
        let filteredScalars = value.unicodeScalars.filter { scalar in
            switch scalar.value {
            case 0x9, 0xA, 0xD:
                return true
            case 0x20...0xD7FF, 0xE000...0xFFFD, 0x10000...0x10FFFF:
                return true
            default:
                return false
            }
        }
        return String(String.UnicodeScalarView(filteredScalars))
    }
}

private struct ExportProcessOutput {
    let status: Int32
    let stdout: Data
    let stderr: Data

    var stderrString: String {
        String(data: stderr, encoding: .utf8) ?? ""
    }
}

private enum ExportProcessRunner {
    static func run(
        executablePath: String,
        arguments: [String],
        timeoutSeconds: TimeInterval = 45
    ) throws -> ExportProcessOutput {
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
            throw WordExportServiceError.failedToLaunchTool(error.localizedDescription)
        }

        let timeoutResult = waitWithTimeout(process: process, timeoutSeconds: timeoutSeconds)
        if !timeoutResult.finished {
            process.terminate()
            _ = waitWithTimeout(process: process, timeoutSeconds: 2)
            let command = ([executablePath] + arguments).joined(separator: " ")
            throw WordExportServiceError.processTimedOut(command: command, timeoutSeconds: timeoutSeconds)
        }

        ioGroup.wait()
        ioLock.lock()
        let output = ExportProcessOutput(status: process.terminationStatus, stdout: stdoutData, stderr: stderrData)
        ioLock.unlock()
        return output
    }

    private static func waitWithTimeout(process: Process, timeoutSeconds: TimeInterval) -> (finished: Bool, status: Int32) {
        let semaphore = DispatchSemaphore(value: 0)
        process.terminationHandler = { _ in
            semaphore.signal()
        }

        let waitResult = semaphore.wait(timeout: .now() + timeoutSeconds)
        if waitResult == .timedOut {
            process.terminationHandler = nil
            return (false, process.terminationStatus)
        }
        process.terminationHandler = nil
        return (true, process.terminationStatus)
    }
}
