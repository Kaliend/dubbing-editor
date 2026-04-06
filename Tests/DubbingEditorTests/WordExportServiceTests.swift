import Foundation
#if canImport(XCTest)
import XCTest
@testable import DubbingEditor

final class WordExportServiceTests: XCTestCase {
    func testMakePlainTextDocumentUsesTabSeparatedRowsAndTrailingNewline() {
        let draft = WordExportDraft(
            profile: .classic,
            rows: [
                WordExportRow(
                    lineID: UUID(uuidString: "11111111-1111-1111-1111-111111111111")!,
                    lineIndex: 1,
                    speaker: "ETTA",
                    timecode: "01:00:08:00",
                    text: "Ahoj"
                ),
                WordExportRow(
                    lineID: UUID(uuidString: "22222222-2222-2222-2222-222222222222")!,
                    lineIndex: 2,
                    speaker: "JESPER",
                    timecode: "",
                    text: ""
                )
            ],
            skippedLineCount: 0
        )

        let output = WordExportService().makePlainTextDocument(from: draft)
        XCTAssertEqual(output, "ETTA\t01:00:08:00\tAhoj\nJESPER\t\t\n")
    }

    func testExportDocxCreatesOutputFile() throws {
        guard FileManager.default.isExecutableFile(atPath: "/usr/bin/textutil") else {
            throw XCTSkip("/usr/bin/textutil neni dostupny")
        }

        let tempRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent("DubbingEditor-WordExportServiceTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempRoot, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempRoot) }

        let draft = WordExportDraft(
            profile: .classic,
            rows: [
                WordExportRow(
                    lineID: UUID(uuidString: "33333333-3333-3333-3333-333333333333")!,
                    lineIndex: 1,
                    speaker: "POLICE OFFICER",
                    timecode: "00:21:07:00",
                    text: "Dobra, jaka je situace?"
                )
            ],
            skippedLineCount: 0
        )

        let destinationWithoutExtension = tempRoot.appendingPathComponent("export-test")
        try WordExportService().exportDocx(draft: draft, to: destinationWithoutExtension)

        let finalURL = destinationWithoutExtension.appendingPathExtension("docx")
        XCTAssertTrue(FileManager.default.fileExists(atPath: finalURL.path))

        let attributes = try FileManager.default.attributesOfItem(atPath: finalURL.path)
        let fileSize = (attributes[.size] as? NSNumber)?.intValue ?? 0
        XCTAssertGreaterThan(fileSize, 0)
    }

    func testMakeIyunoDocumentXMLContainsTableRows() {
        let draft = WordExportDraft(
            profile: .sdi,
            rows: [
                WordExportRow(
                    lineID: UUID(uuidString: "44444444-4444-4444-4444-444444444444")!,
                    lineIndex: 1,
                    speaker: "Insert 9",
                    timecode: "01:37:59",
                    text: "Tell them."
                )
            ],
            skippedLineCount: 0
        )

        let xml = WordExportService().makeIyunoDocumentXML(from: draft)
        XCTAssertTrue(xml.contains("<w:tbl>"))
        XCTAssertTrue(xml.contains("<w:tr>"))
        XCTAssertTrue(xml.contains("Insert 9"))
        XCTAssertTrue(xml.contains("01:37:59"))
        XCTAssertTrue(xml.contains("Tell them."))
    }

    func testExportDocxIyunoContainsWordTable() throws {
        guard FileManager.default.isExecutableFile(atPath: "/usr/bin/textutil") else {
            throw XCTSkip("/usr/bin/textutil neni dostupny")
        }
        guard FileManager.default.isExecutableFile(atPath: "/usr/bin/unzip") else {
            throw XCTSkip("/usr/bin/unzip neni dostupny")
        }

        let tempRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent("DubbingEditor-WordExportServiceTests-IYUNO-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempRoot, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempRoot) }

        let draft = WordExportDraft(
            profile: .sdi,
            rows: [
                WordExportRow(
                    lineID: UUID(uuidString: "55555555-5555-5555-5555-555555555555")!,
                    lineIndex: 1,
                    speaker: "ETTA",
                    timecode: "01:00:08",
                    text: "Ahoj"
                )
            ],
            skippedLineCount: 0
        )

        let destinationURL = tempRoot.appendingPathComponent("iyuno-export.docx")
        try WordExportService().exportDocx(draft: draft, to: destinationURL)

        let xml = try unzipEntry(docxURL: destinationURL, entryPath: "word/document.xml")
        XCTAssertTrue(xml.contains("<w:tbl"))
    }

    func testExportDocxFailsForEmptyDraft() {
        let emptyDraft = WordExportDraft(profile: .classic, rows: [], skippedLineCount: 0)

        XCTAssertThrowsError(try WordExportService().exportDocx(draft: emptyDraft, to: URL(fileURLWithPath: "/tmp/test.docx"))) { error in
            guard case WordExportServiceError.noRowsToExport = error else {
                XCTFail("Neocekavana chyba: \(error)")
                return
            }
        }
    }

    private func unzipEntry(docxURL: URL, entryPath: String) throws -> String {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/unzip")
        process.arguments = ["-p", docxURL.path, entryPath]

        let stdoutPipe = Pipe()
        let stderrPipe = Pipe()
        process.standardOutput = stdoutPipe
        process.standardError = stderrPipe

        try process.run()
        process.waitUntilExit()

        guard process.terminationStatus == 0 else {
            let errorData = stderrPipe.fileHandleForReading.readDataToEndOfFile()
            let message = String(data: errorData, encoding: .utf8) ?? "unzip failed"
            throw NSError(domain: "WordExportServiceTests", code: Int(process.terminationStatus), userInfo: [
                NSLocalizedDescriptionKey: message
            ])
        }

        let data = stdoutPipe.fileHandleForReading.readDataToEndOfFile()
        return String(data: data, encoding: .utf8) ?? ""
    }
}
#endif
