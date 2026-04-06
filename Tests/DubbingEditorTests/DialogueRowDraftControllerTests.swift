import Foundation
#if canImport(XCTest)
import XCTest
@testable import DubbingEditor

final class DialogueRowDraftControllerTests: XCTestCase {
    func testTextDraftSyncSkipsFocusedFieldButRefreshesAfterFocusLeaves() {
        var controller = DialogueRowDraftController()
        let original = DialogueLine(
            index: 1,
            speaker: "A",
            text: "Original",
            startTimecode: "00:00:01:00",
            endTimecode: "00:00:02:00"
        )
        let updated = DialogueLine(
            id: original.id,
            index: 1,
            speaker: "A",
            text: "Updated from model",
            startTimecode: "00:00:01:00",
            endTimecode: "00:00:02:00"
        )

        controller.load(from: original, fps: 25, hideFrames: false)
        controller.editableTextDraft = "Local draft"

        controller.syncTextFromModel(updated, isFocused: true)
        XCTAssertEqual(controller.editableTextDraft, "Local draft")

        controller.syncTextFromModel(updated, isFocused: false)
        XCTAssertEqual(controller.editableTextDraft, "Updated from model")
    }

    func testCommitStartTimecodeNormalizesHiddenFramesDraft() {
        var controller = DialogueRowDraftController()
        var line = DialogueLine(
            index: 1,
            speaker: "A",
            text: "Text",
            startTimecode: "",
            endTimecode: ""
        )
        var committedFields: [String] = []

        controller.load(from: line, fps: 25, hideFrames: true)
        controller.startTimecodeDraft = "00:00:05"

        controller.commitStartTimecodeIfNeeded(
            into: &line,
            fps: 25,
            hideFrames: true
        ) { field in
            committedFields.append(field)
        }

        XCTAssertEqual(line.startTimecode, "00:00:05:00")
        XCTAssertEqual(controller.startTimecodeDraft, "00:00:05")
        XCTAssertEqual(
            controller.resolvedDisplayedStartTimecode(for: line, fps: 25, hideFrames: true),
            "00:00:05"
        )
        XCTAssertEqual(committedFields, ["start_tc"])
    }

    func testHideFramesRefreshUpdatesDisplayedTimecodeDrafts() {
        var controller = DialogueRowDraftController()
        let line = DialogueLine(
            index: 1,
            speaker: "A",
            text: "Text",
            startTimecode: "00:00:07:12",
            endTimecode: "00:00:08:20"
        )

        controller.load(from: line, fps: 25, hideFrames: false)
        XCTAssertEqual(controller.startTimecodeDraft, "00:00:07:12")
        XCTAssertEqual(controller.endTimecodeDraft, "00:00:08:20")

        controller.updateForHideFramesChange(
            line: line,
            fps: 25,
            hideFrames: true,
            isStartFocused: false,
            isEndFocused: false
        )

        XCTAssertEqual(controller.startTimecodeDraft, "00:00:07")
        XCTAssertEqual(controller.endTimecodeDraft, "00:00:08")
        XCTAssertEqual(
            controller.resolvedDisplayedStartTimecode(for: line, fps: 25, hideFrames: true),
            "00:00:07"
        )
        XCTAssertEqual(
            controller.resolvedDisplayedEndTimecode(for: line, fps: 25, hideFrames: true),
            "00:00:08"
        )
    }

    func testResolvedDisplayedTimecodeIgnoresStaleCacheWhenHideFramesModeChanges() {
        var controller = DialogueRowDraftController()
        let line = DialogueLine(
            index: 1,
            speaker: "A",
            text: "Text",
            startTimecode: "00:00:07:12",
            endTimecode: "00:00:08:20"
        )

        controller.load(from: line, fps: 25, hideFrames: false)

        XCTAssertEqual(
            controller.resolvedDisplayedStartTimecode(for: line, fps: 25, hideFrames: true),
            "00:00:07"
        )
        XCTAssertEqual(
            controller.resolvedDisplayedEndTimecode(for: line, fps: 25, hideFrames: true),
            "00:00:08"
        )
    }
}
#endif
