import Foundation
#if canImport(XCTest)
import XCTest
@testable import DubbingEditor

final class EditorProjectionCoordinatorTests: XCTestCase {
    func testRebuildAllComputesIssuesChronologyDisplayedAndSearch() {
        let coordinator = EditorProjectionCoordinator()
        let first = DialogueLine(
            index: 1,
            speaker: "",
            text: "Alpha",
            startTimecode: "00:00:05:00",
            endTimecode: ""
        )
        let second = DialogueLine(
            index: 2,
            speaker: "Bob",
            text: "Target bravo",
            startTimecode: "00:00:04:00",
            endTimecode: ""
        )

        let result = coordinator.rebuildAll(
            from: makeInput(
                lines: [first, second],
                findQuery: "target",
                showValidationIssues: true,
                validateMissingSpeaker: true,
                validateMissingStartTC: true,
                validateMissingEndTC: true
            )
        )

        XCTAssertEqual(result.issuesByLineID[first.id], ["Chybejici charakter.", "Chybejici end TC."])
        XCTAssertEqual(result.issuesByLineID[second.id], ["Chybejici end TC."])
        XCTAssertEqual(result.chronoStartIssues.count, 1)
        XCTAssertEqual(result.chronoIssueLineIDs, [second.id])
        XCTAssertEqual(result.displayedLineIndices, [0, 1])
        XCTAssertEqual(result.searchMatchIndices, [1])
        XCTAssertEqual(result.normalizedFindQuery, "target")
        XCTAssertEqual(result.issueLineCount, 2)
        XCTAssertFalse(result.issueCountIsViewportScoped)
    }

    func testRebuildAllPreservesPreviousViewportIssuesOutsideEvaluationTarget() {
        let coordinator = EditorProjectionCoordinator()
        let first = DialogueLine(
            index: 1,
            speaker: "",
            text: "Alpha",
            startTimecode: "00:00:01:00",
            endTimecode: "00:00:02:00"
        )
        let second = DialogueLine(
            index: 2,
            speaker: "Bob",
            text: "Bravo",
            startTimecode: "00:00:03:00",
            endTimecode: ""
        )

        _ = coordinator.rebuildAll(
            from: makeInput(
                lines: [first, second],
                showValidationIssues: true
            )
        )

        let result = coordinator.rebuildAll(
            from: makeInput(
                lines: [first, second],
                showValidationIssues: true,
                useViewportScopedIssues: true,
                visibleLineIDs: [first.id]
            )
        )

        XCTAssertEqual(result.issuesByLineID[first.id], ["Chybejici charakter."])
        XCTAssertEqual(result.issuesByLineID[second.id], ["Chybejici end TC."])
        XCTAssertTrue(result.issueCountIsViewportScoped)
    }

    func testRefreshSingleLineUpdatesIssuesAndSearchHaystack() {
        let coordinator = EditorProjectionCoordinator()
        let lineID = UUID()
        let original = DialogueLine(
            id: lineID,
            index: 1,
            speaker: "",
            text: "Alpha",
            startTimecode: "00:00:01:00",
            endTimecode: ""
        )
        let updated = DialogueLine(
            id: lineID,
            index: 1,
            speaker: "Dr. Desai",
            text: "Alpha",
            startTimecode: "00:00:01:00",
            endTimecode: "00:00:02:00"
        )

        var result = coordinator.rebuildAll(
            from: makeInput(
                lines: [original],
                findQuery: "desai",
                showValidationIssues: true
            )
        )

        let refreshed = coordinator.refreshSingleLine(
            lineID,
            in: &result,
            from: makeInput(
                lines: [updated],
                findQuery: "desai",
                showValidationIssues: true
            )
        )

        XCTAssertTrue(refreshed)
        XCTAssertEqual(result.issuesByLineID[lineID], [])
        XCTAssertEqual(
            result.normalizedSearchHaystackByLineID[lineID],
            EditorProjectionCoordinator.normalizeSearch("Dr. Desai 00:00:01:00 00:00:02:00 Alpha")
        )
    }

    private func makeInput(
        lines: [DialogueLine],
        findQuery: String = "",
        showValidationIssues: Bool = false,
        showOnlyIssues: Bool = false,
        validateMissingSpeaker: Bool = true,
        validateMissingStartTC: Bool = true,
        validateMissingEndTC: Bool = true,
        validateInvalidTC: Bool = true,
        showOnlyChronologyIssues: Bool = false,
        showOnlyMissingSpeakerIssues: Bool = false,
        selectedCharacterFilterKeys: Set<String> = [],
        visibleLineIDs: Set<DialogueLine.ID> = [],
        useViewportScopedIssues: Bool = false,
        selectedLineID: DialogueLine.ID? = nil,
        editingLineID: DialogueLine.ID? = nil,
        highlightedLineID: DialogueLine.ID? = nil,
        activeSearchLineID: DialogueLine.ID? = nil,
        isLightModeEnabled: Bool = false,
        fps: Double = 25
    ) -> EditorProjectionInput {
        EditorProjectionInput(
            lines: lines,
            fps: fps,
            findQuery: findQuery,
            showValidationIssues: showValidationIssues,
            showOnlyIssues: showOnlyIssues,
            validateMissingSpeaker: validateMissingSpeaker,
            validateMissingStartTC: validateMissingStartTC,
            validateMissingEndTC: validateMissingEndTC,
            validateInvalidTC: validateInvalidTC,
            showOnlyChronologyIssues: showOnlyChronologyIssues,
            showOnlyMissingSpeakerIssues: showOnlyMissingSpeakerIssues,
            selectedCharacterFilterKeys: selectedCharacterFilterKeys,
            visibleLineIDs: visibleLineIDs,
            useViewportScopedIssues: useViewportScopedIssues,
            selectedLineID: selectedLineID,
            editingLineID: editingLineID,
            highlightedLineID: highlightedLineID,
            activeSearchLineID: activeSearchLineID,
            isLightModeEnabled: isLightModeEnabled
        )
    }
}
#endif
