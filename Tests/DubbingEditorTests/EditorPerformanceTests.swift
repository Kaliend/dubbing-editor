import Foundation
#if canImport(XCTest)
import XCTest
@testable import DubbingEditor

@MainActor
final class EditorPerformanceTests: XCTestCase {
    func testReplaceAllOnTwoThousandLinesSmokePerformance() {
        let model = EditorViewModel()
        model.lines = makeLargeProjectLines(count: 2_000)

        let started = CFAbsoluteTimeGetCurrent()
        let replaced = model.replaceInAllLines(query: "takze", replacement: "tedy")
        let elapsed = CFAbsoluteTimeGetCurrent() - started

        XCTAssertEqual(replaced, 4_000)
        XCTAssertLessThan(elapsed, 6.0, "replaceInAllLines is too slow: \(elapsed)s")
    }

    func testSelectionTraversalOnTwoThousandLinesSmokePerformance() {
        let model = EditorViewModel()
        model.lines = makeLargeProjectLines(count: 2_000)
        model.selectedLineID = model.lines.first?.id

        let started = CFAbsoluteTimeGetCurrent()
        for _ in 1..<model.lines.count {
            model.moveSelection(step: 1)
        }
        let elapsed = CFAbsoluteTimeGetCurrent() - started

        XCTAssertEqual(model.selectedLineID, model.lines.last?.id)
        XCTAssertLessThan(elapsed, 6.0, "Selection traversal is too slow: \(elapsed)s")
    }

    func testIssueCountOnTwoThousandLinesSmokePerformance() {
        let model = EditorViewModel()
        model.lines = makeLargeProjectLines(count: 2_000)

        let started = CFAbsoluteTimeGetCurrent()
        let count = model.issueLineCount()
        let elapsed = CFAbsoluteTimeGetCurrent() - started

        XCTAssertEqual(count, 2_000)
        XCTAssertLessThan(elapsed, 6.0, "issueLineCount is too slow: \(elapsed)s")
    }

    func testFullProjectionRebuildOnTwoThousandLinesSmokePerformance() {
        let coordinator = EditorProjectionCoordinator()
        let lines = makeLargeProjectLines(count: 2_000)

        let started = CFAbsoluteTimeGetCurrent()
        let result = coordinator.rebuildAll(
            from: makeProjectionInput(
                lines: lines,
                findQuery: "takze",
                showValidationIssues: true,
                showOnlyIssues: true
            )
        )
        let elapsed = CFAbsoluteTimeGetCurrent() - started

        XCTAssertEqual(result.displayedLineIndices.count, 2_000)
        XCTAssertEqual(result.searchMatchIndices.count, 2_000)
        XCTAssertEqual(result.issueLineCount, 2_000)
        XCTAssertLessThan(elapsed, 6.0, "full projection rebuild is too slow: \(elapsed)s")
    }

    func testIncrementalSingleLineProjectionUpdateOnTwoThousandLinesSmokePerformance() {
        let coordinator = EditorProjectionCoordinator()
        let lineID = UUID()
        let originalLines = makeLargeProjectLines(count: 2_000, firstLineID: lineID)
        let updatedLines = makeUpdatedLargeProjectLines(from: originalLines, lineID: lineID)

        var result = coordinator.rebuildAll(
            from: makeProjectionInput(
                lines: originalLines,
                findQuery: "desai",
                showValidationIssues: true,
                showOnlyIssues: true
            )
        )

        let started = CFAbsoluteTimeGetCurrent()
        let refreshed = coordinator.refreshSingleLine(
            lineID,
            in: &result,
            from: makeProjectionInput(
                lines: updatedLines,
                findQuery: "desai",
                showValidationIssues: true,
                showOnlyIssues: true
            )
        )
        coordinator.rebuildDisplayedIndicesAndIssueCount(
            in: &result,
            from: makeProjectionInput(
                lines: updatedLines,
                findQuery: "desai",
                showValidationIssues: true,
                showOnlyIssues: true
            )
        )
        coordinator.rebuildSearch(
            in: &result,
            from: makeProjectionInput(
                lines: updatedLines,
                findQuery: "desai",
                showValidationIssues: true,
                showOnlyIssues: true
            )
        )
        let elapsed = CFAbsoluteTimeGetCurrent() - started

        XCTAssertTrue(refreshed)
        XCTAssertEqual(result.issuesByLineID[lineID], [])
        XCTAssertEqual(result.searchMatchIndices.count, 1)
        XCTAssertLessThan(elapsed, 2.0, "incremental projection update is too slow: \(elapsed)s")
    }

    func testTimecodeParsingBatchSmokePerformance() {
        let inputs = [
            "01:02:03:12",
            "00:00:10,250",
            "00:01:05",
            "01:05"
        ]

        let started = CFAbsoluteTimeGetCurrent()
        var checksum = 0.0
        for index in 0..<100_000 {
            checksum += TimecodeService.seconds(from: inputs[index % inputs.count], fps: 25) ?? -1
        }
        let elapsed = CFAbsoluteTimeGetCurrent() - started

        XCTAssertGreaterThan(checksum, 0)
        XCTAssertLessThan(elapsed, 2.0, "timecode parsing is too slow: \(elapsed)s")
    }

    private func makeLargeProjectLines(count: Int, firstLineID: UUID? = nil) -> [DialogueLine] {
        (1...count).map { idx in
            let second = idx % 3_000
            let start = String(format: "00:%02d:%02d:00", (second / 60) % 60, second % 60)
            let endSecond = min(second + 2, 3_599)
            let end = String(format: "00:%02d:%02d:00", (endSecond / 60) % 60, endSecond % 60)

            return DialogueLine(
                id: idx == 1 ? (firstLineID ?? UUID()) : UUID(),
                index: idx,
                speaker: idx.isMultiple(of: 2) ? "VERONIKA" : "TOMAS",
                text: "Takže replika \(idx) Takze test vykonu pro hledani a nahrazeni.",
                startTimecode: start,
                endTimecode: end
            )
        }
    }

    private func makeUpdatedLargeProjectLines(from lines: [DialogueLine], lineID: UUID) -> [DialogueLine] {
        lines.map { line in
            guard line.id == lineID else { return line }
            var updated = line
            updated.speaker = "DR. DESAI"
            updated.endTimecode = "00:00:03:00"
            return updated
        }
    }

    private func makeProjectionInput(
        lines: [DialogueLine],
        findQuery: String = "",
        showValidationIssues: Bool = false,
        showOnlyIssues: Bool = false
    ) -> EditorProjectionInput {
        EditorProjectionInput(
            lines: lines,
            fps: 25,
            findQuery: findQuery,
            showValidationIssues: showValidationIssues,
            showOnlyIssues: showOnlyIssues,
            validateMissingSpeaker: true,
            validateMissingStartTC: true,
            validateMissingEndTC: true,
            validateInvalidTC: true,
            showOnlyChronologyIssues: false,
            showOnlyMissingSpeakerIssues: false,
            selectedCharacterFilterKeys: [],
            visibleLineIDs: [],
            useViewportScopedIssues: false,
            selectedLineID: nil,
            editingLineID: nil,
            highlightedLineID: nil,
            activeSearchLineID: nil,
            isLightModeEnabled: false
        )
    }
}
#endif
