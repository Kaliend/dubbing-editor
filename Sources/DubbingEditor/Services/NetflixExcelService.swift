import Foundation
#if canImport(FoundationXML)
import FoundationXML
#endif

struct NetflixExcelImportResult {
    let sourceURL: URL
    let lines: [DialogueLine]
    let skippedRowCount: Int
}

struct NetflixExcelExportRow: Equatable {
    let lineID: DialogueLine.ID
    let lineIndex: Int
    let inTimecode: String
    let outTimecode: String
    let speaker: String
    let dialogue: String
}

struct NetflixExcelExportDraft: Equatable {
    let rows: [NetflixExcelExportRow]
    let skippedLineCount: Int
}

enum NetflixExcelServiceError: LocalizedError {
    case inputFileNotFound(URL)
    case unsupportedExtension(String)
    case failedToLaunchTool(String)
    case failedToReadPackage(String)
    case workbookXMLNotFound
    case workbookRelationshipsXMLNotFound
    case worksheetXMLNotFound(String)
    case requiredHeadersMissing([String])
    case invalidXML(String)
    case noRowsToExport
    case unsupportedOutputURL(URL)
    case exportFailed(String)
    case processTimedOut(command: String, timeoutSeconds: TimeInterval)

    var errorDescription: String? {
        switch self {
        case .inputFileNotFound(let url):
            return "Vstupni Excel soubor nebyl nalezen: \(url.lastPathComponent)"
        case .unsupportedExtension(let ext):
            return "Nepodporovana pripona souboru: .\(ext)"
        case .failedToLaunchTool(let details):
            return "Nepodarilo se spustit systemovy nastroj. \(details)"
        case .failedToReadPackage(let details):
            return "Nepodarilo se nacist XLSX balicek. \(details)"
        case .workbookXMLNotFound:
            return "V XLSX chybi soubor xl/workbook.xml"
        case .workbookRelationshipsXMLNotFound:
            return "V XLSX chybi soubor xl/_rels/workbook.xml.rels"
        case .worksheetXMLNotFound(let path):
            return "V XLSX chybi worksheet \(path)"
        case .requiredHeadersMissing(let headers):
            return "V Netflix Excelu chybi povinne sloupce: \(headers.joined(separator: ", "))"
        case .invalidXML(let details):
            return "Nepodarilo se naparsovat XML obsah Excelu. \(details)"
        case .noRowsToExport:
            return "Export nema zadna data."
        case .unsupportedOutputURL(let url):
            return "Nepodporovana cilova cesta pro export: \(url.path)"
        case .exportFailed(let details):
            return "Nepodarilo se vytvorit XLSX. \(details)"
        case .processTimedOut(let command, let timeoutSeconds):
            return "Excel import/export se zasekl pri prikazu '\(command)' a byl ukoncen po \(Int(timeoutSeconds))s."
        }
    }
}

struct NetflixExcelPackageContents {
    let workbookXML: String
    let workbookRelationshipsXML: String
    let worksheetXMLByPath: [String: String]
    let sharedStringsXML: String?
}

struct NetflixExcelService {
    private enum RequiredHeader: String, CaseIterable {
        case inTimecode = "IN-TIMECODE"
        case outTimecode = "OUT-TIMECODE"
        case source = "SOURCE"
        case dialogue = "DIALOGUE"
    }

    private enum ExportColumn: CaseIterable {
        case inTimecode
        case outTimecode
        case source
        case transcription
        case dialogue

        var reference: String {
            switch self {
            case .inTimecode:
                return "A"
            case .outTimecode:
                return "B"
            case .source:
                return "C"
            case .transcription:
                return "D"
            case .dialogue:
                return "E"
            }
        }

        var headerTitle: String {
            switch self {
            case .inTimecode:
                return "IN-TIMECODE"
            case .outTimecode:
                return "OUT-TIMECODE"
            case .source:
                return "SOURCE"
            case .transcription:
                return "TRANSCRIPTION"
            case .dialogue:
                return "DIALOGUE"
            }
        }

        var width: Double {
            switch self {
            case .inTimecode, .outTimecode, .source:
                return 31.1640625
            case .transcription, .dialogue:
                return 93.6640625
            }
        }
    }

    func importLines(sourceURL: URL, fps: Double) throws -> NetflixExcelImportResult {
        let package = try readPackage(from: sourceURL)
        let parsed = try parseImportPackage(package, fps: fps)
        return NetflixExcelImportResult(
            sourceURL: sourceURL,
            lines: parsed.lines,
            skippedRowCount: parsed.skippedRowCount
        )
    }

    func buildExportDraft(from lines: [DialogueLine], fps: Double) -> NetflixExcelExportDraft {
        var rows: [NetflixExcelExportRow] = []
        rows.reserveCapacity(lines.count)

        for line in lines {
            let start = formattedExportTimecode(line.startTimecode, fps: fps)
            let end = formattedExportTimecode(line.endTimecode, fps: fps)
            let speaker = sanitizedCellValue(line.speaker)
            let dialogue = sanitizedCellValue(line.text)

            if start.isEmpty, end.isEmpty, speaker.isEmpty, dialogue.isEmpty {
                continue
            }

            rows.append(
                NetflixExcelExportRow(
                    lineID: line.id,
                    lineIndex: line.index,
                    inTimecode: start,
                    outTimecode: end,
                    speaker: speaker,
                    dialogue: dialogue
                )
            )
        }

        return NetflixExcelExportDraft(
            rows: rows,
            skippedLineCount: max(0, lines.count - rows.count)
        )
    }

    func exportXLSX(draft: NetflixExcelExportDraft, to destinationURL: URL) throws {
        guard !draft.rows.isEmpty else {
            throw NetflixExcelServiceError.noRowsToExport
        }
        guard destinationURL.isFileURL else {
            throw NetflixExcelServiceError.unsupportedOutputURL(destinationURL)
        }

        let finalDestinationURL = normalizedDestinationURL(destinationURL)
        let tempRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent("DubbingEditor-NetflixExcelExport-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempRoot, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempRoot) }

        let packageContents = makeWorkbookPackage(draft: draft)
        for (relativePath, data) in packageContents {
            let fileURL = tempRoot.appendingPathComponent(relativePath)
            try FileManager.default.createDirectory(
                at: fileURL.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            try data.write(to: fileURL)
        }

        if FileManager.default.fileExists(atPath: finalDestinationURL.path) {
            try FileManager.default.removeItem(at: finalDestinationURL)
        }

        let output = try SpreadsheetProcessRunner.run(
            executablePath: "/usr/bin/ditto",
            arguments: ["-c", "-k", "--norsrc", tempRoot.path, finalDestinationURL.path]
        )
        guard output.status == 0 else {
            let details = output.stderrString.trimmingCharacters(in: .whitespacesAndNewlines)
            throw NetflixExcelServiceError.exportFailed(details.isEmpty ? "Nepodarilo se zabalit XLSX." : details)
        }
    }

    func makeWorkbookPackage(draft: NetflixExcelExportDraft) -> [String: Data] {
        let createdAt = iso8601Timestamp(Date())
        return [
            "[Content_Types].xml": Data(makeContentTypesXML().utf8),
            "_rels/.rels": Data(makeRootRelationshipsXML().utf8),
            "docProps/app.xml": Data(makeAppPropertiesXML().utf8),
            "docProps/core.xml": Data(makeCorePropertiesXML(createdAt: createdAt).utf8),
            "xl/workbook.xml": Data(makeWorkbookXML().utf8),
            "xl/_rels/workbook.xml.rels": Data(makeWorkbookRelationshipsXML().utf8),
            "xl/styles.xml": Data(makeStylesXML().utf8),
            "xl/worksheets/sheet1.xml": Data(makeDialogueListWorksheetXML(rows: draft.rows).utf8)
        ]
    }

    func parseImportPackage(
        _ package: NetflixExcelPackageContents,
        fps: Double
    ) throws -> (lines: [DialogueLine], skippedRowCount: Int) {
        let worksheetPath = try resolveDialogueListWorksheetPath(in: package)
        guard let worksheetXML = package.worksheetXMLByPath[worksheetPath] else {
            throw NetflixExcelServiceError.worksheetXMLNotFound(worksheetPath)
        }

        let sharedStrings = try parseSharedStrings(package.sharedStringsXML)
        let worksheetRows = try parseWorksheetRows(xml: worksheetXML, sharedStrings: sharedStrings)
        let (headerRowIndex, headerMap) = try resolveHeaderMap(in: worksheetRows)

        var lines: [DialogueLine] = []
        lines.reserveCapacity(max(0, worksheetRows.count - headerRowIndex - 1))
        var skippedRowCount = 0

        for row in worksheetRows where row.rowNumber > headerRowIndex {
            let startTimecode = normalizedImportedTimecode(row.valuesByColumn[headerMap[.inTimecode] ?? ""] ?? "", fps: fps)
            let endTimecode = normalizedImportedTimecode(row.valuesByColumn[headerMap[.outTimecode] ?? ""] ?? "", fps: fps)
            let speaker = sanitizedCellValue(row.valuesByColumn[headerMap[.source] ?? ""] ?? "")
            let dialogue = sanitizedCellValue(row.valuesByColumn[headerMap[.dialogue] ?? ""] ?? "")

            if startTimecode.isEmpty, endTimecode.isEmpty, speaker.isEmpty, dialogue.isEmpty {
                skippedRowCount += 1
                continue
            }

            lines.append(
                DialogueLine(
                    index: lines.count + 1,
                    speaker: speaker,
                    text: dialogue,
                    startTimecode: startTimecode,
                    endTimecode: endTimecode
                )
            )
        }

        return (lines, skippedRowCount)
    }

    private func readPackage(from sourceURL: URL) throws -> NetflixExcelPackageContents {
        guard FileManager.default.fileExists(atPath: sourceURL.path) else {
            throw NetflixExcelServiceError.inputFileNotFound(sourceURL)
        }

        let ext = sourceURL.pathExtension.lowercased()
        guard ext == "xlsx" else {
            throw NetflixExcelServiceError.unsupportedExtension(ext)
        }

        let tempRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent("DubbingEditor-NetflixExcelImport-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempRoot, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempRoot) }

        let output = try SpreadsheetProcessRunner.run(
            executablePath: "/usr/bin/unzip",
            arguments: ["-q", sourceURL.path, "-d", tempRoot.path]
        )
        guard output.status == 0 else {
            let details = output.stderrString.trimmingCharacters(in: .whitespacesAndNewlines)
            throw NetflixExcelServiceError.failedToReadPackage(details.isEmpty ? "unzip vratil chybu." : details)
        }

        let workbookXMLURL = tempRoot.appendingPathComponent("xl/workbook.xml")
        let workbookRelationshipsXMLURL = tempRoot.appendingPathComponent("xl/_rels/workbook.xml.rels")
        let sharedStringsXMLURL = tempRoot.appendingPathComponent("xl/sharedStrings.xml")
        let worksheetsRootURL = tempRoot.appendingPathComponent("xl/worksheets", isDirectory: true)

        guard FileManager.default.fileExists(atPath: workbookXMLURL.path) else {
            throw NetflixExcelServiceError.workbookXMLNotFound
        }
        guard FileManager.default.fileExists(atPath: workbookRelationshipsXMLURL.path) else {
            throw NetflixExcelServiceError.workbookRelationshipsXMLNotFound
        }

        let workbookXML = try decodeXMLData(Data(contentsOf: workbookXMLURL))
        let workbookRelationshipsXML = try decodeXMLData(Data(contentsOf: workbookRelationshipsXMLURL))
        let sharedStringsXML: String?
        if FileManager.default.fileExists(atPath: sharedStringsXMLURL.path) {
            sharedStringsXML = try decodeXMLData(Data(contentsOf: sharedStringsXMLURL))
        } else {
            sharedStringsXML = nil
        }

        var worksheetXMLByPath: [String: String] = [:]
        if FileManager.default.fileExists(atPath: worksheetsRootURL.path),
           let enumerator = FileManager.default.enumerator(at: worksheetsRootURL, includingPropertiesForKeys: nil) {
            for case let fileURL as URL in enumerator where fileURL.pathExtension.lowercased() == "xml" {
                let relativePath = "xl/worksheets/\(fileURL.lastPathComponent)"
                worksheetXMLByPath[relativePath] = try decodeXMLData(Data(contentsOf: fileURL))
            }
        }

        return NetflixExcelPackageContents(
            workbookXML: workbookXML,
            workbookRelationshipsXML: workbookRelationshipsXML,
            worksheetXMLByPath: worksheetXMLByPath,
            sharedStringsXML: sharedStringsXML
        )
    }

    private func decodeXMLData(_ data: Data) throws -> String {
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
        throw NetflixExcelServiceError.invalidXML("Nepodarilo se dekodovat XML soubor.")
    }

    private func resolveDialogueListWorksheetPath(in package: NetflixExcelPackageContents) throws -> String {
        let workbookDocument = try makeXMLDocument(from: package.workbookXML)
        let relationshipsDocument = try makeXMLDocument(from: package.workbookRelationshipsXML)

        let sheetNodes = try workbookDocument.nodes(forXPath: "/*[local-name()='workbook']/*[local-name()='sheets']/*[local-name()='sheet']")
        let relationshipNodes = try relationshipsDocument.nodes(forXPath: "/*[local-name()='Relationships']/*[local-name()='Relationship']")

        var relationshipTargets: [String: String] = [:]
        for case let node as XMLElement in relationshipNodes {
            guard
                let id = node.attribute(forName: "Id")?.stringValue,
                let target = node.attribute(forName: "Target")?.stringValue
            else {
                continue
            }
            relationshipTargets[id] = normalizedWorksheetPath(target)
        }

        let resolvedSheets: [(name: String, path: String)] = sheetNodes.compactMap { node in
            guard let element = node as? XMLElement else { return nil }
            guard
                let name = element.attribute(forName: "name")?.stringValue,
                let relationshipID = relationshipAttributeValue(in: element),
                let targetPath = relationshipTargets[relationshipID]
            else {
                return nil
            }
            return (name, targetPath)
        }

        if let dialogueList = resolvedSheets.first(where: { normalizedHeaderName($0.name) == "DIALOGUE LIST" }) {
            return dialogueList.path
        }
        if let first = resolvedSheets.first {
            return first.path
        }
        throw NetflixExcelServiceError.failedToReadPackage("Workbook neobsahuje zadny worksheet.")
    }

    private func parseSharedStrings(_ xml: String?) throws -> [String] {
        guard let xml, !xml.isEmpty else {
            return []
        }
        let document = try makeXMLDocument(from: xml)
        let nodes = try document.nodes(forXPath: "/*[local-name()='sst']/*[local-name()='si']")
        return nodes.compactMap { node in
            guard let element = node as? XMLElement else { return nil }
            return stringValue(fromSharedStringItem: element)
        }
    }

    private func parseWorksheetRows(
        xml: String,
        sharedStrings: [String]
    ) throws -> [WorksheetRow] {
        let document = try makeXMLDocument(from: xml)
        let rowNodes = try document.nodes(forXPath: "/*[local-name()='worksheet']/*[local-name()='sheetData']/*[local-name()='row']")
        return rowNodes.compactMap { rowNode in
            guard let rowElement = rowNode as? XMLElement else { return nil }
            let rowNumber = Int(rowElement.attribute(forName: "r")?.stringValue ?? "") ?? 0
            var valuesByColumn: [String: String] = [:]
            for case let cellElement as XMLElement in rowElement.children ?? [] {
                guard cellElement.localName == "c" else { continue }
                let column = columnReference(from: cellElement.attribute(forName: "r")?.stringValue ?? "")
                guard !column.isEmpty else { continue }
                valuesByColumn[column] = resolvedCellValue(from: cellElement, sharedStrings: sharedStrings)
            }
            return WorksheetRow(rowNumber: rowNumber, valuesByColumn: valuesByColumn)
        }
    }

    private func resolveHeaderMap(
        in worksheetRows: [WorksheetRow]
    ) throws -> (headerRowIndex: Int, headerMap: [RequiredHeader: String]) {
        for row in worksheetRows {
            var headerMap: [RequiredHeader: String] = [:]
            for (column, value) in row.valuesByColumn {
                let normalizedValue = normalizedHeaderName(value)
                if let header = RequiredHeader(rawValue: normalizedValue) {
                    headerMap[header] = column
                }
            }

            if RequiredHeader.allCases.allSatisfy({ headerMap[$0] != nil }) {
                return (row.rowNumber, headerMap)
            }
        }

        throw NetflixExcelServiceError.requiredHeadersMissing(RequiredHeader.allCases.map(\.rawValue))
    }

    private func relationshipAttributeValue(in element: XMLElement) -> String? {
        if let namespaced = element.attribute(forLocalName: "id", uri: "http://schemas.openxmlformats.org/officeDocument/2006/relationships")?.stringValue {
            return namespaced
        }
        for attribute in element.attributes ?? [] where attribute.localName == "id" {
            return attribute.stringValue
        }
        return nil
    }

    private func normalizedWorksheetPath(_ target: String) -> String {
        let trimmed = target.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.hasPrefix("xl/") {
            return trimmed
        }
        if trimmed.hasPrefix("/") {
            return String(trimmed.dropFirst())
        }
        return "xl/\(trimmed)"
    }

    private func makeXMLDocument(from xml: String) throws -> XMLDocument {
        do {
            return try XMLDocument(data: Data(xml.utf8), options: [])
        } catch {
            throw NetflixExcelServiceError.invalidXML(error.localizedDescription)
        }
    }

    private func stringValue(fromSharedStringItem item: XMLElement) -> String {
        guard let nodes = try? item.nodes(forXPath: ".//*[local-name()='t']") else {
            return item.stringValue ?? ""
        }
        let combined = nodes.compactMap { ($0 as? XMLElement)?.stringValue ?? $0.stringValue }.joined()
        return combined
    }

    private func resolvedCellValue(from cell: XMLElement, sharedStrings: [String]) -> String {
        let cellType = cell.attribute(forName: "t")?.stringValue ?? ""

        switch cellType {
        case "s":
            guard
                let indexString = firstChildValue(named: "v", in: cell),
                let index = Int(indexString),
                sharedStrings.indices.contains(index)
            else {
                return ""
            }
            return sharedStrings[index]

        case "inlineStr":
            guard let inlineNodes = try? cell.nodes(forXPath: ".//*[local-name()='is']//*[local-name()='t']") else {
                return ""
            }
            return inlineNodes.compactMap { ($0 as? XMLElement)?.stringValue ?? $0.stringValue }.joined()

        default:
            return firstChildValue(named: "v", in: cell) ?? ""
        }
    }

    private func firstChildValue(named localName: String, in element: XMLElement) -> String? {
        for case let child as XMLElement in element.children ?? [] where child.localName == localName {
            return child.stringValue
        }
        return nil
    }

    private func columnReference(from cellReference: String) -> String {
        let prefix = cellReference.prefix { $0.isLetter }
        return prefix.uppercased()
    }

    private func normalizedHeaderName(_ value: String) -> String {
        sanitizedCellValue(value).uppercased()
    }

    private func normalizedImportedTimecode(_ value: String, fps: Double) -> String {
        let sanitized = sanitizedCellValue(value)
        guard !sanitized.isEmpty else {
            return ""
        }
        if isPreservedNetflixTimecode(sanitized) {
            return sanitized
        }
        guard let seconds = TimecodeService.seconds(from: sanitized, fps: fps) else {
            return sanitized
        }
        return TimecodeService.timecode(from: seconds, fps: fps)
    }

    private func formattedExportTimecode(_ value: String, fps: Double) -> String {
        let sanitized = sanitizedCellValue(value)
        guard !sanitized.isEmpty else {
            return ""
        }
        if isPreservedNetflixTimecode(sanitized) {
            return sanitized
        }
        guard let seconds = TimecodeService.seconds(from: sanitized, fps: fps) else {
            return sanitized
        }
        return TimecodeService.timecode(from: seconds, fps: fps)
    }

    private func isPreservedNetflixTimecode(_ value: String) -> Bool {
        let components = value.split(separator: ":", omittingEmptySubsequences: false)
        guard components.count == 3 || components.count == 4 else {
            return false
        }
        return components.allSatisfy { component in
            component.count == 2 && component.allSatisfy(\.isNumber)
        }
    }

    private func sanitizedCellValue(_ value: String) -> String {
        let xmlSafe = value.unicodeScalars.map { scalar -> String in
            switch scalar.value {
            case 0x9, 0xA, 0xD, 0x20...0xD7FF, 0xE000...0xFFFD:
                return String(scalar)
            default:
                return " "
            }
        }.joined()

        let normalized = xmlSafe
            .replacingOccurrences(of: "\t", with: " ")
            .replacingOccurrences(of: "\r\n", with: " ")
            .replacingOccurrences(of: "\n", with: " ")
            .replacingOccurrences(of: "\r", with: " ")
            .replacingOccurrences(of: "\u{00A0}", with: " ")

        return normalized
            .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func normalizedDestinationURL(_ url: URL) -> URL {
        if url.pathExtension.lowercased() == "xlsx" {
            return url
        }
        return url.appendingPathExtension("xlsx")
    }

    private func makeContentTypesXML() -> String {
        """
        <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
        <Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types">
          <Default Extension="rels" ContentType="application/vnd.openxmlformats-package.relationships+xml"/>
          <Default Extension="xml" ContentType="application/xml"/>
          <Override PartName="/docProps/app.xml" ContentType="application/vnd.openxmlformats-officedocument.extended-properties+xml"/>
          <Override PartName="/docProps/core.xml" ContentType="application/vnd.openxmlformats-package.core-properties+xml"/>
          <Override PartName="/xl/workbook.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.sheet.main+xml"/>
          <Override PartName="/xl/worksheets/sheet1.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.worksheet+xml"/>
          <Override PartName="/xl/styles.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.styles+xml"/>
        </Types>
        """
    }

    private func makeRootRelationshipsXML() -> String {
        """
        <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
        <Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">
          <Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/officeDocument" Target="xl/workbook.xml"/>
          <Relationship Id="rId2" Type="http://schemas.openxmlformats.org/package/2006/relationships/metadata/core-properties" Target="docProps/core.xml"/>
          <Relationship Id="rId3" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/extended-properties" Target="docProps/app.xml"/>
        </Relationships>
        """
    }

    private func makeAppPropertiesXML() -> String {
        """
        <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
        <Properties xmlns="http://schemas.openxmlformats.org/officeDocument/2006/extended-properties" xmlns:vt="http://schemas.openxmlformats.org/officeDocument/2006/docPropsVTypes">
          <Application>DubbingEditor</Application>
        </Properties>
        """
    }

    private func makeCorePropertiesXML(createdAt: String) -> String {
        """
        <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
        <cp:coreProperties xmlns:cp="http://schemas.openxmlformats.org/package/2006/metadata/core-properties" xmlns:dc="http://purl.org/dc/elements/1.1/" xmlns:dcterms="http://purl.org/dc/terms/" xmlns:dcmitype="http://purl.org/dc/dcmitype/" xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance">
          <dc:creator>DubbingEditor</dc:creator>
          <cp:lastModifiedBy>DubbingEditor</cp:lastModifiedBy>
          <dcterms:created xsi:type="dcterms:W3CDTF">\(createdAt)</dcterms:created>
          <dcterms:modified xsi:type="dcterms:W3CDTF">\(createdAt)</dcterms:modified>
        </cp:coreProperties>
        """
    }

    private func makeWorkbookXML() -> String {
        """
        <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
        <workbook xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main" xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships">
          <sheets>
            <sheet name="Dialogue List" sheetId="1" r:id="rId1"/>
          </sheets>
        </workbook>
        """
    }

    private func makeWorkbookRelationshipsXML() -> String {
        """
        <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
        <Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">
          <Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/worksheet" Target="worksheets/sheet1.xml"/>
          <Relationship Id="rId2" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/styles" Target="styles.xml"/>
        </Relationships>
        """
    }

    private func makeStylesXML() -> String {
        """
        <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
        <styleSheet xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main">
          <fonts count="1">
            <font>
              <sz val="11"/>
              <name val="Aptos"/>
              <family val="2"/>
            </font>
          </fonts>
          <fills count="2">
            <fill><patternFill patternType="none"/></fill>
            <fill><patternFill patternType="gray125"/></fill>
          </fills>
          <borders count="1">
            <border><left/><right/><top/><bottom/><diagonal/></border>
          </borders>
          <cellStyleXfs count="1">
            <xf numFmtId="0" fontId="0" fillId="0" borderId="0"/>
          </cellStyleXfs>
          <cellXfs count="1">
            <xf numFmtId="0" fontId="0" fillId="0" borderId="0" xfId="0"/>
          </cellXfs>
          <cellStyles count="1">
            <cellStyle name="Normal" xfId="0" builtinId="0"/>
          </cellStyles>
        </styleSheet>
        """
    }

    func makeDialogueListWorksheetXML(rows: [NetflixExcelExportRow]) -> String {
        let headerCells = ExportColumn.allCases.map { column in
            makeInlineStringCell(reference: "\(column.reference)1", value: column.headerTitle)
        }.joined()

        let rowXML = rows.enumerated().map { offset, row in
            let rowNumber = offset + 2
            let cells = [
                makeInlineStringCell(reference: "A\(rowNumber)", value: row.inTimecode),
                makeInlineStringCell(reference: "B\(rowNumber)", value: row.outTimecode),
                makeInlineStringCell(reference: "C\(rowNumber)", value: row.speaker),
                makeInlineStringCell(reference: "E\(rowNumber)", value: row.dialogue)
            ]
            .filter { !$0.isEmpty }
            .joined()

            return #"<row r="\#(rowNumber)">\#(cells)</row>"#
        }.joined()

        let columnXML = ExportColumn.allCases.enumerated().map { idx, column in
            let columnIndex = idx + 1
            return #"<col min="\#(columnIndex)" max="\#(columnIndex)" width="\#(column.width)" customWidth="1"/>"#
        }.joined()

        return """
        <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
        <worksheet xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main">
          <dimension ref="A1:E\(max(1, rows.count + 1))"/>
          <sheetViews>
            <sheetView workbookViewId="0">
              <pane ySplit="1" topLeftCell="A2" activePane="bottomLeft" state="frozen"/>
            </sheetView>
          </sheetViews>
          <sheetFormatPr defaultRowHeight="15"/>
          <cols>\(columnXML)</cols>
          <sheetData>
            <row r="1">\(headerCells)</row>
            \(rowXML)
          </sheetData>
        </worksheet>
        """
    }

    private func makeInlineStringCell(reference: String, value: String) -> String {
        guard !value.isEmpty else {
            return ""
        }
        return #"<c r="\#(reference)" t="inlineStr"><is><t xml:space="preserve">\#(xmlEscaped(value))</t></is></c>"#
    }

    private func xmlEscaped(_ value: String) -> String {
        value
            .replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
            .replacingOccurrences(of: "\"", with: "&quot;")
            .replacingOccurrences(of: "'", with: "&apos;")
    }

    private func iso8601Timestamp(_ date: Date) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        return formatter.string(from: date)
    }
}

private struct WorksheetRow {
    let rowNumber: Int
    let valuesByColumn: [String: String]
}

private struct SpreadsheetProcessOutput {
    let status: Int32
    let stdoutString: String
    let stderrString: String
}

private enum SpreadsheetProcessRunner {
    static func run(
        executablePath: String,
        arguments: [String],
        timeoutSeconds: TimeInterval = 20
    ) throws -> SpreadsheetProcessOutput {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executablePath)
        process.arguments = arguments

        let stdoutPipe = Pipe()
        let stderrPipe = Pipe()
        process.standardOutput = stdoutPipe
        process.standardError = stderrPipe

        do {
            try process.run()
        } catch {
            throw NetflixExcelServiceError.failedToLaunchTool(error.localizedDescription)
        }

        let timedOut = DispatchSemaphore(value: 0)
        let waitQueue = DispatchQueue(label: "NetflixExcelService.ProcessRunner")
        waitQueue.async {
            process.waitUntilExit()
            timedOut.signal()
        }

        if timedOut.wait(timeout: .now() + timeoutSeconds) == .timedOut {
            process.terminate()
            throw NetflixExcelServiceError.processTimedOut(
                command: ([executablePath] + arguments).joined(separator: " "),
                timeoutSeconds: timeoutSeconds
            )
        }

        let stdoutData = stdoutPipe.fileHandleForReading.readDataToEndOfFile()
        let stderrData = stderrPipe.fileHandleForReading.readDataToEndOfFile()

        return SpreadsheetProcessOutput(
            status: process.terminationStatus,
            stdoutString: String(data: stdoutData, encoding: .utf8) ?? "",
            stderrString: String(data: stderrData, encoding: .utf8) ?? ""
        )
    }
}
