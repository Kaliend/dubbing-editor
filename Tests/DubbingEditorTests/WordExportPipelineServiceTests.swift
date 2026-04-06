import Foundation
#if canImport(XCTest)
import XCTest
@testable import DubbingEditor

final class WordExportPipelineServiceTests: XCTestCase {
    func testBuildDraftMapsRowsToSpeakerTimecodeTextOrder() {
        let lines = [
            DialogueLine(
                id: UUID(uuidString: "11111111-1111-1111-1111-111111111111")!,
                index: 1,
                speaker: "ETTA",
                text: "Ahoj",
                startTimecode: "01:00:08",
                endTimecode: ""
            )
        ]
        let service = WordExportPipelineService()
        let draft = service.buildDraft(from: lines, options: .defaultClassic, fps: 25)

        XCTAssertEqual(draft.profile, .classic)
        XCTAssertEqual(draft.rows.count, 1)
        XCTAssertEqual(draft.rows[0].speaker, "ETTA")
        XCTAssertEqual(draft.rows[0].timecode, "01:00:08:00")
        XCTAssertEqual(draft.rows[0].text, "Ahoj")
        XCTAssertEqual(draft.rows[0].tabSeparated, "ETTA\t01:00:08:00\tAhoj")
    }

    func testBuildDraftKeepsSpeakerOnlyRows() {
        let lines = [
            DialogueLine(index: 1, speaker: "JESPER", text: "", startTimecode: "", endTimecode: "")
        ]
        let service = WordExportPipelineService()
        let draft = service.buildDraft(from: lines, options: .defaultClassic, fps: 25)

        XCTAssertEqual(draft.rows.count, 1)
        XCTAssertEqual(draft.rows[0].speaker, "JESPER")
        XCTAssertEqual(draft.rows[0].timecode, "")
        XCTAssertEqual(draft.rows[0].text, "")
    }

    func testBuildDraftSkipsCompletelyEmptyRowsByDefault() {
        let lines = [
            DialogueLine(index: 1, speaker: "", text: "", startTimecode: "", endTimecode: "")
        ]
        let service = WordExportPipelineService()
        let draft = service.buildDraft(from: lines, options: .defaultClassic, fps: 25)

        XCTAssertEqual(draft.rows.count, 0)
        XCTAssertEqual(draft.skippedLineCount, 1)
    }

    func testTimecodeFormattingHonorsSelectedComponents() {
        var options = WordExportOptions.defaultClassic
        options.timecodeFormat = WordExportTimecodeFormat(
            includeHours: false,
            includeMinutes: true,
            includeSeconds: true,
            includeFrames: false
        )

        let lines = [
            DialogueLine(index: 1, speaker: "A", text: "B", startTimecode: "01:11:22:12", endTimecode: "")
        ]
        let draft = WordExportPipelineService().buildDraft(from: lines, options: options, fps: 25)
        XCTAssertEqual(draft.rows.count, 1)
        XCTAssertEqual(draft.rows[0].timecode, "71:22")
    }

    func testTimecodeFormattingFallsBackToRawForInvalidTimecode() {
        let lines = [
            DialogueLine(index: 1, speaker: "A", text: "B", startTimecode: "??:bad", endTimecode: "")
        ]
        let draft = WordExportPipelineService().buildDraft(from: lines, options: .defaultClassic, fps: 25)
        XCTAssertEqual(draft.rows.count, 1)
        XCTAssertEqual(draft.rows[0].timecode, "??:bad")
    }

    func testBuildDraftCanUseEndTimecodeSource() {
        var options = WordExportOptions.defaultClassic
        options.timecodeSource = .end
        options.timecodeFormat = WordExportTimecodeFormat(
            includeHours: true,
            includeMinutes: true,
            includeSeconds: true,
            includeFrames: false
        )

        let lines = [
            DialogueLine(index: 1, speaker: "A", text: "B", startTimecode: "00:00:10:00", endTimecode: "00:00:12:12")
        ]
        let draft = WordExportPipelineService().buildDraft(from: lines, options: options, fps: 25)
        XCTAssertEqual(draft.rows.count, 1)
        XCTAssertEqual(draft.rows[0].timecode, "00:00:12")
    }
}
#endif
