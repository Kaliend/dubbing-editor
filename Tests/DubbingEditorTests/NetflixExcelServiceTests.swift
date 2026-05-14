import Foundation
#if canImport(XCTest)
import XCTest
@testable import DubbingEditor

final class NetflixExcelServiceTests: XCTestCase {
    func testParseImportPackageMapsNetflixColumnsByHeaderName() throws {
        let package = NetflixExcelPackageContents(
            workbookXML: workbookXML(),
            workbookRelationshipsXML: workbookRelationshipsXML(),
            worksheetXMLByPath: ["xl/worksheets/sheet1.xml": worksheetXMLWithSharedStrings()],
            sharedStringsXML: sharedStringsXML()
        )

        let parsed = try NetflixExcelService().parseImportPackage(package, fps: 25)

        XCTAssertEqual(parsed.lines.count, 2)
        XCTAssertEqual(parsed.skippedRowCount, 1)

        XCTAssertEqual(parsed.lines[0].startTimecode, "00:00:01:05")
        XCTAssertEqual(parsed.lines[0].endTimecode, "00:00:06:13")
        XCTAssertEqual(parsed.lines[0].speaker, "SENTRY")
        XCTAssertEqual(parsed.lines[0].text, "To je nemozne.")

        XCTAssertEqual(parsed.lines[1].startTimecode, "00:00:07:00")
        XCTAssertEqual(parsed.lines[1].endTimecode, "00:00:08:00")
        XCTAssertEqual(parsed.lines[1].speaker, "")
        XCTAssertEqual(parsed.lines[1].text, "Druha veta.")
    }

    func testParseImportPackageThrowsWhenRequiredHeadersAreMissing() {
        let package = NetflixExcelPackageContents(
            workbookXML: workbookXML(),
            workbookRelationshipsXML: workbookRelationshipsXML(),
            worksheetXMLByPath: [
                "xl/worksheets/sheet1.xml": """
                <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
                <worksheet xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main">
                  <sheetData>
                    <row r="1">
                      <c r="A1" t="inlineStr"><is><t>IN-TIMECODE</t></is></c>
                      <c r="B1" t="inlineStr"><is><t>OUT-TIMECODE</t></is></c>
                      <c r="C1" t="inlineStr"><is><t>SOURCE</t></is></c>
                    </row>
                  </sheetData>
                </worksheet>
                """
            ],
            sharedStringsXML: nil
        )

        XCTAssertThrowsError(try NetflixExcelService().parseImportPackage(package, fps: 25)) { error in
            guard case NetflixExcelServiceError.requiredHeadersMissing(let headers) = error else {
                XCTFail("Neocekavana chyba: \(error)")
                return
            }
            XCTAssertTrue(headers.contains("DIALOGUE"))
        }
    }

    func testBuildExportDraftFormatsTimecodesAndSkipsEmptyRows() {
        let lines = [
            DialogueLine(
                id: UUID(uuidString: "11111111-1111-1111-1111-111111111111")!,
                index: 1,
                speaker: "SENTRY",
                text: "To je nemozne.",
                startTimecode: "00:00:01:05",
                endTimecode: "00:00:06:13"
            ),
            DialogueLine(
                id: UUID(uuidString: "22222222-2222-2222-2222-222222222222")!,
                index: 2,
                speaker: "",
                text: "",
                startTimecode: "",
                endTimecode: ""
            )
        ]

        let draft = NetflixExcelService().buildExportDraft(from: lines, fps: 25)

        XCTAssertEqual(draft.rows.count, 1)
        XCTAssertEqual(draft.skippedLineCount, 1)
        XCTAssertEqual(draft.rows[0].inTimecode, "00:00:01:05")
        XCTAssertEqual(draft.rows[0].outTimecode, "00:00:06:13")
        XCTAssertEqual(draft.rows[0].speaker, "SENTRY")
        XCTAssertEqual(draft.rows[0].dialogue, "To je nemozne.")
    }

    func testExportXLSXCreatesDialogueListWorksheet() throws {
        guard FileManager.default.isExecutableFile(atPath: "/usr/bin/unzip") else {
            throw XCTSkip("/usr/bin/unzip neni dostupny")
        }
        guard FileManager.default.isExecutableFile(atPath: "/usr/bin/ditto") else {
            throw XCTSkip("/usr/bin/ditto neni dostupny")
        }

        let tempRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent("DubbingEditor-NetflixExcelServiceTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempRoot, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempRoot) }

        let draft = NetflixExcelExportDraft(
            rows: [
                NetflixExcelExportRow(
                    lineID: UUID(uuidString: "33333333-3333-3333-3333-333333333333")!,
                    lineIndex: 1,
                    inTimecode: "00:00:01:05",
                    outTimecode: "00:00:06:13",
                    speaker: "SENTRY",
                    dialogue: "To je nemozne."
                )
            ],
            skippedLineCount: 0
        )

        let destinationURL = tempRoot.appendingPathComponent("netflix-export.xlsx")
        try NetflixExcelService().exportXLSX(draft: draft, to: destinationURL)

        XCTAssertTrue(FileManager.default.fileExists(atPath: destinationURL.path))

        let workbookXML = try unzipEntry(xlsxURL: destinationURL, entryPath: "xl/workbook.xml")
        let worksheetXML = try unzipEntry(xlsxURL: destinationURL, entryPath: "xl/worksheets/sheet1.xml")

        XCTAssertTrue(workbookXML.contains("Dialogue List"))
        XCTAssertTrue(worksheetXML.contains("IN-TIMECODE"))
        XCTAssertTrue(worksheetXML.contains("OUT-TIMECODE"))
        XCTAssertTrue(worksheetXML.contains("SOURCE"))
        XCTAssertTrue(worksheetXML.contains("TRANSCRIPTION"))
        XCTAssertTrue(worksheetXML.contains("DIALOGUE"))
        XCTAssertTrue(worksheetXML.contains("00:00:01:05"))
        XCTAssertTrue(worksheetXML.contains("00:00:06:13"))
        XCTAssertTrue(worksheetXML.contains("SENTRY"))
        XCTAssertTrue(worksheetXML.contains("To je nemozne."))
    }

    private func workbookXML() -> String {
        """
        <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
        <workbook xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main" xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships">
          <sheets>
            <sheet name="Dialogue List" sheetId="1" r:id="rId1"/>
          </sheets>
        </workbook>
        """
    }

    private func workbookRelationshipsXML() -> String {
        """
        <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
        <Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">
          <Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/worksheet" Target="worksheets/sheet1.xml"/>
        </Relationships>
        """
    }

    private func sharedStringsXML() -> String {
        """
        <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
        <sst xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main">
          <si><t>OUT-TIMECODE</t></si>
          <si><t>DIALOGUE</t></si>
          <si><t>IN-TIMECODE</t></si>
          <si><t>SOURCE</t></si>
          <si><t>TRANSCRIPTION</t></si>
          <si><t>00:00:01:05</t></si>
          <si><t>00:00:06:13</t></si>
          <si><t>SENTRY</t></si>
          <si><t>To je nemozne.</t></si>
          <si><t>00:00:07:00</t></si>
          <si><t>00:00:08:00</t></si>
          <si><t>Druha veta.</t></si>
        </sst>
        """
    }

    private func worksheetXMLWithSharedStrings() -> String {
        """
        <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
        <worksheet xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main">
          <sheetData>
            <row r="1">
              <c r="B1" t="s"><v>0</v></c>
              <c r="E1" t="s"><v>1</v></c>
              <c r="A1" t="s"><v>2</v></c>
              <c r="C1" t="s"><v>3</v></c>
              <c r="D1" t="s"><v>4</v></c>
            </row>
            <row r="2">
              <c r="A2" t="s"><v>5</v></c>
              <c r="B2" t="s"><v>6</v></c>
              <c r="C2" t="s"><v>7</v></c>
              <c r="E2" t="s"><v>8</v></c>
            </row>
            <row r="3">
              <c r="D3" t="inlineStr"><is><t>ignored</t></is></c>
            </row>
            <row r="4">
              <c r="A4" t="s"><v>9</v></c>
              <c r="B4" t="s"><v>10</v></c>
              <c r="E4" t="s"><v>11</v></c>
            </row>
          </sheetData>
        </worksheet>
        """
    }

    private func unzipEntry(xlsxURL: URL, entryPath: String) throws -> String {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/unzip")
        process.arguments = ["-p", xlsxURL.path, entryPath]

        let stdoutPipe = Pipe()
        let stderrPipe = Pipe()
        process.standardOutput = stdoutPipe
        process.standardError = stderrPipe

        try process.run()
        process.waitUntilExit()

        guard process.terminationStatus == 0 else {
            let errorData = stderrPipe.fileHandleForReading.readDataToEndOfFile()
            let message = String(data: errorData, encoding: .utf8) ?? "unzip failed"
            throw NSError(domain: "NetflixExcelServiceTests", code: Int(process.terminationStatus), userInfo: [
                NSLocalizedDescriptionKey: message
            ])
        }

        let data = stdoutPipe.fileHandleForReading.readDataToEndOfFile()
        return String(data: data, encoding: .utf8) ?? ""
    }
}
#endif
