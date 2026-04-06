import Foundation
#if canImport(XCTest)
import XCTest
@testable import DubbingEditor

final class WordImportServiceTests: XCTestCase {
    func testFormatDetectorDetectsIyunoTableProfile() {
        let xml = """
        <w:document>
          <w:body>
            <w:tbl>
              <w:tr><w:tc><w:p><w:r><w:t>CHAR</w:t></w:r></w:p></w:tc></w:tr>
              <w:tr><w:tc><w:p><w:r><w:t>TEXT</w:t></w:r></w:p></w:tc></w:tr>
            </w:tbl>
          </w:body>
        </w:document>
        """

        let format = ImportFormatDetector().detectFormat(inDocumentXML: xml)
        XCTAssertEqual(format, .iyunoTable)
    }

    func testFormatDetectorDetectsClassicTabsProfile() {
        let xml = """
        <w:document>
          <w:body>
            <w:p><w:r><w:t>Speaker</w:t></w:r><w:r><w:tab/></w:r><w:r><w:t>00:00:01</w:t></w:r></w:p>
            <w:p><w:r><w:t>Text</w:t></w:r><w:r><w:tab/></w:r><w:r><w:t>Hello</w:t></w:r></w:p>
          </w:body>
        </w:document>
        """

        let format = ImportFormatDetector().detectFormat(inDocumentXML: xml)
        XCTAssertEqual(format, .classicTabs)
    }

    func testFormatDetectorFallsBackToUnknown() {
        let xml = """
        <w:document>
          <w:body>
            <w:p><w:r><w:t>Free text only</w:t></w:r></w:p>
          </w:body>
        </w:document>
        """

        let format = ImportFormatDetector().detectFormat(inDocumentXML: xml)
        XCTAssertEqual(format, .unknown)
    }

    func testInspectPipelineUsesDetectorResult() throws {
        let xml = """
        <w:document>
          <w:body>
            <w:p><w:r><w:t>A</w:t></w:r><w:r><w:tab/></w:r><w:r><w:t>B</w:t></w:r></w:p>
            <w:p><w:r><w:t>C</w:t></w:r><w:r><w:tab/></w:r><w:r><w:t>D</w:t></w:r></w:p>
          </w:body>
        </w:document>
        """

        let service = WordImportService(
            inputNormalizer: MockNormalizer(),
            docxPackageReader: MockReader(xml: xml),
            formatDetector: ImportFormatDetector()
        )

        let inspection = try service.inspect(sourceURL: URL(fileURLWithPath: "/tmp/sample.docx"))
        XCTAssertEqual(inspection.detectedFormat, .classicTabs)
        XCTAssertFalse(inspection.convertedFromLegacyDoc)
        XCTAssertTrue(inspection.documentXML.contains("<w:document>"))
    }

    func testImportClassicIncludesRowsWithoutSpeaker() throws {
        let xml = """
        <w:document xmlns:w="http://schemas.openxmlformats.org/wordprocessingml/2006/main">
          <w:body>
            <w:p>
              <w:r><w:t>LIZ</w:t></w:r>
              <w:r><w:tab/></w:r>
              <w:r><w:t>03:43</w:t></w:r>
              <w:r><w:tab/></w:r>
              <w:r><w:t>Jestli chces byt moderator.</w:t></w:r>
            </w:p>
            <w:p>
              <w:r><w:t>03:51</w:t></w:r>
              <w:r><w:tab/></w:r>
              <w:r><w:t>Jasne, chapu.</w:t></w:r>
            </w:p>
          </w:body>
        </w:document>
        """

        let service = WordImportService(
            inputNormalizer: MockNormalizer(),
            docxPackageReader: MockReader(xml: xml),
            formatDetector: ImportFormatDetector()
        )

        let result = try service.importLines(sourceURL: URL(fileURLWithPath: "/tmp/classic.docx"), fps: 25)
        XCTAssertEqual(result.detectedFormat, .classicTabs)
        XCTAssertEqual(result.lines.count, 2)
        XCTAssertEqual(result.lines[0].speaker, "LIZ")
        XCTAssertEqual(result.lines[0].startTimecode, "00:03:43:00")
        XCTAssertEqual(result.lines[1].speaker, "")
        XCTAssertEqual(result.lines[1].startTimecode, "00:03:51:00")
        XCTAssertEqual(result.lines[1].text, "Jasne, chapu.")
    }

    func testImportIyunoIncludesRowsWithoutTimecodeAndWithoutSpeaker() throws {
        let xml = """
        <w:document xmlns:w="http://schemas.openxmlformats.org/wordprocessingml/2006/main">
          <w:body>
            <w:tbl>
              <w:tr>
                <w:tc><w:p><w:r><w:t>001</w:t></w:r></w:p></w:tc>
                <w:tc><w:p><w:r><w:t>00:00:10</w:t></w:r></w:p></w:tc>
                <w:tc><w:p><w:r><w:t>CHRIS</w:t></w:r></w:p></w:tc>
                <w:tc><w:p><w:r><w:t>Ahoj.</w:t></w:r></w:p></w:tc>
              </w:tr>
              <w:tr>
                <w:tc><w:p><w:r><w:t>002</w:t></w:r></w:p></w:tc>
                <w:tc><w:p><w:r><w:t></w:t></w:r></w:p></w:tc>
                <w:tc><w:p><w:r><w:t>POLICE OFFICER</w:t></w:r></w:p></w:tc>
                <w:tc><w:p><w:r><w:t>Dobra, jaka je situace?</w:t></w:r></w:p></w:tc>
              </w:tr>
              <w:tr>
                <w:tc><w:p><w:r><w:t>003</w:t></w:r></w:p></w:tc>
                <w:tc><w:p><w:r><w:t></w:t></w:r></w:p></w:tc>
                <w:tc><w:p><w:r><w:t></w:t></w:r></w:p></w:tc>
                <w:tc><w:p><w:r><w:t>Samotny text bez speakeru.</w:t></w:r></w:p></w:tc>
              </w:tr>
              <w:tr>
                <w:tc><w:p><w:r><w:t>004</w:t></w:r></w:p></w:tc>
                <w:tc><w:p><w:r><w:t></w:t></w:r></w:p></w:tc>
                <w:tc><w:p><w:r><w:t>ETTA</w:t></w:r></w:p></w:tc>
                <w:tc><w:p><w:r><w:t>(pres) 00:28 (heky)</w:t></w:r></w:p></w:tc>
              </w:tr>
            </w:tbl>
          </w:body>
        </w:document>
        """

        let service = WordImportService(
            inputNormalizer: MockNormalizer(),
            docxPackageReader: MockReader(xml: xml),
            formatDetector: ImportFormatDetector()
        )

        let result = try service.importLines(sourceURL: URL(fileURLWithPath: "/tmp/iyuno.docx"), fps: 25)
        XCTAssertEqual(result.detectedFormat, .iyunoTable)
        XCTAssertEqual(result.lines.count, 4)
        XCTAssertEqual(result.lines[0].speaker, "CHRIS")
        XCTAssertEqual(result.lines[0].startTimecode, "00:00:10:00")
        XCTAssertEqual(result.lines[1].speaker, "POLICE OFFICER")
        XCTAssertEqual(result.lines[1].startTimecode, "")
        XCTAssertEqual(result.lines[2].speaker, "")
        XCTAssertEqual(result.lines[2].text, "Samotny text bez speakeru.")
        XCTAssertEqual(result.lines[3].speaker, "ETTA")
        XCTAssertEqual(result.lines[3].startTimecode, "")
        XCTAssertEqual(result.lines[3].text, "(pres) 00:28 (heky)")
    }

    func testImportIyunoDoesNotDropDialogueContainingKonecWord() throws {
        let xml = """
        <w:document xmlns:w="http://schemas.openxmlformats.org/wordprocessingml/2006/main">
          <w:body>
            <w:tbl>
              <w:tr>
                <w:tc><w:p><w:r><w:t>001</w:t></w:r></w:p></w:tc>
                <w:tc><w:p><w:r><w:t>01:03:24</w:t></w:r></w:p></w:tc>
                <w:tc><w:p><w:r><w:t>LEAH</w:t></w:r></w:p></w:tc>
                <w:tc><w:p><w:r><w:t>Zavolej matce. Rekni, ze je konec. :14 (dechy) Splatime to, plus uroky.</w:t></w:r></w:p></w:tc>
              </w:tr>
            </w:tbl>
          </w:body>
        </w:document>
        """

        let service = WordImportService(
            inputNormalizer: MockNormalizer(),
            docxPackageReader: MockReader(xml: xml),
            formatDetector: ImportFormatDetector()
        )

        let result = try service.importLines(sourceURL: URL(fileURLWithPath: "/tmp/iyuno-konec.docx"), fps: 25)
        XCTAssertEqual(result.lines.count, 1)
        XCTAssertEqual(result.lines[0].speaker, "LEAH")
        XCTAssertEqual(result.lines[0].startTimecode, "01:03:24:00")
        XCTAssertTrue(result.lines[0].text.contains("je konec"))
    }

    func testImportClassicSkipsLeadingPreambleRows() throws {
        let xml = """
        <w:document xmlns:w="http://schemas.openxmlformats.org/wordprocessingml/2006/main">
          <w:body>
            <w:p><w:r><w:t>ORIGINAL TITLE</w:t></w:r><w:r><w:tab/></w:r><w:r><w:t>KANGAROO</w:t></w:r></w:p>
            <w:p><w:r><w:t>TRANSLATED BY</w:t></w:r><w:r><w:tab/></w:r><w:r><w:t>Someone</w:t></w:r></w:p>
            <w:p><w:r><w:t>SCRIPT NAME</w:t></w:r><w:r><w:tab/></w:r><w:r><w:t>ORIGINAL NAME</w:t></w:r></w:p>
            <w:p>
              <w:r><w:t>LIZ</w:t></w:r>
              <w:r><w:tab/></w:r>
              <w:r><w:t>03:43</w:t></w:r>
              <w:r><w:tab/></w:r>
              <w:r><w:t>Jestli chces byt moderator.</w:t></w:r>
            </w:p>
            <w:p>
              <w:r><w:t>03:51</w:t></w:r>
              <w:r><w:tab/></w:r>
              <w:r><w:t>Jasne, chapu.</w:t></w:r>
            </w:p>
          </w:body>
        </w:document>
        """

        let service = WordImportService(
            inputNormalizer: MockNormalizer(),
            docxPackageReader: MockReader(xml: xml),
            formatDetector: ImportFormatDetector()
        )

        let result = try service.importLines(sourceURL: URL(fileURLWithPath: "/tmp/classic-preamble.docx"), fps: 25)
        XCTAssertEqual(result.detectedFormat, .classicTabs)
        XCTAssertEqual(result.lines.count, 2)
        XCTAssertEqual(result.lines[0].speaker, "LIZ")
        XCTAssertEqual(result.lines[0].startTimecode, "00:03:43:00")
        XCTAssertEqual(result.lines[1].speaker, "")
        XCTAssertEqual(result.lines[1].startTimecode, "00:03:51:00")
    }

    func testImportIyunoParagraphSkipsLeadingMetadata() throws {
        let xml = """
        <w:document xmlns:w="http://schemas.openxmlformats.org/wordprocessingml/2006/main">
          <w:body>
            <w:p><w:r><w:t>ORIGINAL TITLE</w:t></w:r></w:p>
            <w:p><w:r><w:t>LIGHT OF THE WORLD</w:t></w:r></w:p>
            <w:p><w:r><w:t>TRANSLATED BY</w:t></w:r></w:p>
            <w:p><w:r><w:t>Translator Name</w:t></w:r></w:p>
            <w:p><w:r><w:t>Ahoj.</w:t></w:r></w:p>
            <w:p><w:r><w:t>JOHN</w:t></w:r></w:p>
            <w:p><w:r><w:t>00:00:05</w:t></w:r></w:p>
            <w:p><w:r><w:t>Nazdar.</w:t></w:r></w:p>
            <w:p><w:r><w:t>MARY</w:t></w:r></w:p>
            <w:p><w:r><w:t>00:00:08</w:t></w:r></w:p>
            <w:p><w:r><w:t>Jak se mas?</w:t></w:r></w:p>
          </w:body>
        </w:document>
        """

        let service = WordImportService(
            inputNormalizer: MockNormalizer(),
            docxPackageReader: MockReader(xml: xml),
            formatDetector: ImportFormatDetector()
        )

        let result = try service.importLines(sourceURL: URL(fileURLWithPath: "/tmp/iyuno-preamble.docx"), fps: 25)
        XCTAssertEqual(result.lines.count, 2)
        XCTAssertEqual(result.lines[0].speaker, "JOHN")
        XCTAssertEqual(result.lines[0].startTimecode, "00:00:05:00")
        XCTAssertEqual(result.lines[0].text, "Nazdar.")
        XCTAssertEqual(result.lines[1].speaker, "MARY")
        XCTAssertEqual(result.lines[1].startTimecode, "00:00:08:00")
        XCTAssertEqual(result.lines[1].text, "Jak se mas?")
    }

    func testImportIyunoParagraphTreatsHashSpeakerAsSpeaker() throws {
        let xml = """
        <w:document xmlns:w="http://schemas.openxmlformats.org/wordprocessingml/2006/main">
          <w:body>
            <w:p><w:r><w:t>Jdeme.</w:t></w:r></w:p>
            <w:p><w:r><w:t>FISHERMAN #4</w:t></w:r></w:p>
            <w:p><w:r><w:t>01:11:22</w:t></w:r></w:p>
            <w:p><w:r><w:t>Běž.</w:t></w:r></w:p>
            <w:p><w:r><w:t>DAN</w:t></w:r></w:p>
            <w:p><w:r><w:t>01:11:24</w:t></w:r></w:p>
          </w:body>
        </w:document>
        """

        let service = WordImportService(
            inputNormalizer: MockNormalizer(),
            docxPackageReader: MockReader(xml: xml),
            formatDetector: ImportFormatDetector()
        )

        let result = try service.importLines(sourceURL: URL(fileURLWithPath: "/tmp/iyuno-hash-speaker.docx"), fps: 25)
        XCTAssertEqual(result.lines.count, 2)
        XCTAssertEqual(result.lines[0].speaker, "FISHERMAN #4")
        XCTAssertEqual(result.lines[0].startTimecode, "01:11:22:00")
        XCTAssertEqual(result.lines[0].text, "Jdeme.")
        XCTAssertEqual(result.lines[1].speaker, "DAN")
        XCTAssertEqual(result.lines[1].startTimecode, "01:11:24:00")
        XCTAssertEqual(result.lines[1].text, "Běž.")
    }

    func testImportIyunoParagraphTreatsInsertLabelAsSpeaker() throws {
        let xml = """
        <w:document xmlns:w="http://schemas.openxmlformats.org/wordprocessingml/2006/main">
          <w:body>
            <w:p><w:r><w:t>Reknete jim.</w:t></w:r></w:p>
            <w:p><w:r><w:t>Insert 9</w:t></w:r></w:p>
            <w:p><w:r><w:t>01:37:59</w:t></w:r></w:p>
          </w:body>
        </w:document>
        """

        let service = WordImportService(
            inputNormalizer: MockNormalizer(),
            docxPackageReader: MockReader(xml: xml),
            formatDetector: ImportFormatDetector()
        )

        let result = try service.importLines(sourceURL: URL(fileURLWithPath: "/tmp/iyuno-insert-speaker.docx"), fps: 25)
        XCTAssertEqual(result.lines.count, 1)
        XCTAssertEqual(result.lines[0].speaker, "Insert 9")
        XCTAssertEqual(result.lines[0].startTimecode, "01:37:59:00")
        XCTAssertEqual(result.lines[0].text, "Reknete jim.")
    }
}

private struct MockNormalizer: DocInputNormalizing {
    func normalize(sourceURL: URL) throws -> DocInputNormalizationResult {
        DocInputNormalizationResult(
            docxURL: sourceURL,
            convertedFromLegacyDoc: false,
            temporaryCleanupURL: nil
        )
    }
}

private struct MockReader: DocxPackageReading {
    let xml: String

    func readDocumentXML(from _: URL) throws -> Data {
        Data(xml.utf8)
    }
}
#endif
