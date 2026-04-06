import AVFoundation
import Foundation
#if canImport(XCTest)
import XCTest
@testable import DubbingEditor

@MainActor
final class EditorViewModelTests: XCTestCase {
    func testInsertNewLineAfterSelectionInsertsAfterSelectedAndRenumbers() {
        let model = EditorViewModel()
        let line1 = DialogueLine(index: 7, speaker: "A", text: "Prvni", startTimecode: "00:00:00:00", endTimecode: "")
        let line2 = DialogueLine(index: 8, speaker: "B", text: "Druha", startTimecode: "00:00:10:00", endTimecode: "")
        let line3 = DialogueLine(index: 9, speaker: "C", text: "Treti", startTimecode: "00:00:20:00", endTimecode: "")
        model.lines = [line1, line2, line3]
        model.selectedLineID = line2.id

        let newID = model.insertNewLineAfterSelection()

        XCTAssertEqual(model.lines.count, 4)
        XCTAssertEqual(model.lines[0].id, line1.id)
        XCTAssertEqual(model.lines[1].id, line2.id)
        XCTAssertEqual(model.lines[2].id, newID)
        XCTAssertEqual(model.lines[3].id, line3.id)
        XCTAssertEqual(model.lines.map(\.index), [1, 2, 3, 4])
        XCTAssertEqual(model.selectedLineID, newID)
        XCTAssertEqual(model.highlightedLineID, newID)
        XCTAssertEqual(model.editingLineID, newID)
        XCTAssertEqual(model.lines[2].text, "")
        XCTAssertEqual(model.lines[2].speaker, "")
        XCTAssertEqual(model.lines[2].startTimecode, "00:00:15:00")
        XCTAssertEqual(model.lines[2].endTimecode, "")
    }

    func testInsertNewLineWithoutSelectionAppendsAtEnd() {
        let model = EditorViewModel()
        model.lines = [
            DialogueLine(index: 1, speaker: "A", text: "One", startTimecode: "00:00:03:00", endTimecode: ""),
            DialogueLine(index: 2, speaker: "B", text: "Two", startTimecode: "00:00:09:00", endTimecode: "")
        ]
        model.selectedLineID = nil

        let newID = model.insertNewLineAfterSelection()

        XCTAssertEqual(model.lines.count, 3)
        XCTAssertEqual(model.lines.last?.id, newID)
        XCTAssertEqual(model.lines.map(\.index), [1, 2, 3])
        XCTAssertEqual(model.selectedLineID, newID)
        XCTAssertEqual(model.highlightedLineID, newID)
        XCTAssertEqual(model.editingLineID, newID)
        XCTAssertEqual(model.lines.last?.startTimecode, "00:00:14:00")
    }

    func testInsertNewLineFallsBackToLatestValidPreviousTimecode() {
        let model = EditorViewModel()
        let line1 = DialogueLine(index: 1, speaker: "A", text: "One", startTimecode: "00:00:12:00", endTimecode: "")
        let line2 = DialogueLine(index: 2, speaker: "B", text: "Two", startTimecode: "", endTimecode: "")
        model.lines = [line1, line2]
        model.selectedLineID = line2.id

        let newID = model.insertNewLineAfterSelection()

        XCTAssertEqual(model.lines.last?.id, newID)
        XCTAssertEqual(model.lines.last?.startTimecode, "00:00:17:00")
    }

    func testInsertNewLineWithLoadedVideoUsesCurrentPlaybackTimecode() async {
        let model = EditorViewModel()
        model.lines = [
            DialogueLine(index: 1, speaker: "A", text: "One", startTimecode: "00:00:03:00", endTimecode: "")
        ]
        model.selectedLineID = model.lines[0].id
        attachSeekableVideo(to: model, seekSeconds: 12.48)
        await waitForPlayerSeek()

        let expected = model.currentInsertionStartTimecode()
        let newID = model.insertNewLineAfterSelection()

        XCTAssertEqual(model.lines.count, 2)
        XCTAssertEqual(model.lines[1].id, newID)
        XCTAssertEqual(model.lines[1].startTimecode, expected)
        XCTAssertEqual(model.lines[1].endTimecode, "")
    }

    func testInsertNewLineWithLoadedVideoUsesOffsetAwarePlaybackTimecode() async {
        let model = EditorViewModel()
        model.lines = [
            DialogueLine(index: 1, speaker: "A", text: "One", startTimecode: "00:00:03:00", endTimecode: "")
        ]
        model.selectedLineID = model.lines[0].id
        model.videoOffsetSeconds = 1.25
        attachSeekableVideo(to: model, seekSeconds: 12.48)
        await waitForPlayerSeek()

        let expected = TimecodeService.timecode(
            from: model.timelineSeconds(fromPlaybackSeconds: 12.48),
            fps: model.fps
        )
        let newID = model.insertNewLineAfterSelection()

        XCTAssertEqual(model.lines[1].id, newID)
        XCTAssertEqual(model.lines[1].startTimecode, expected)
    }

    func testInsertNewLineWithoutLoadedVideoKeepsExistingFallbackMechanism() {
        let model = EditorViewModel()
        model.lines = [
            DialogueLine(index: 1, speaker: "A", text: "One", startTimecode: "00:00:12:00", endTimecode: ""),
            DialogueLine(index: 2, speaker: "B", text: "Two", startTimecode: "", endTimecode: "")
        ]
        model.selectedLineID = model.lines[1].id

        let newID = model.insertNewLineAfterSelection()

        XCTAssertEqual(model.lines.last?.id, newID)
        XCTAssertEqual(model.lines.last?.startTimecode, "00:00:17:00")
    }

    func testInsertNewLineMatchesCanonicalPlaybackTimecodePath() async {
        let model = EditorViewModel()
        model.lines = [
            DialogueLine(index: 1, speaker: "A", text: "One", startTimecode: "00:00:01:00", endTimecode: "")
        ]
        model.selectedLineID = model.lines[0].id
        attachSeekableVideo(to: model, seekSeconds: 41.72)
        await waitForPlayerSeek()

        let canonical = model.currentInsertionStartTimecode()
        let newID = model.insertNewLineAfterSelection()

        XCTAssertEqual(model.lines[1].id, newID)
        XCTAssertEqual(model.lines[1].startTimecode, canonical)
    }

    func testInsertNewLinePreservesFrameSnappingAtTwentyFourFPS() async {
        let model = EditorViewModel()
        model.setFPSPreset(.fps24)
        model.lines = [
            DialogueLine(index: 1, speaker: "A", text: "One", startTimecode: "00:00:01:00", endTimecode: "")
        ]
        model.selectedLineID = model.lines[0].id
        attachSeekableVideo(to: model, seekSeconds: 10 + (11.0 / 24.0))
        await waitForPlayerSeek()

        let newID = model.insertNewLineAfterSelection()

        XCTAssertEqual(model.lines[1].id, newID)
        XCTAssertEqual(model.lines[1].startTimecode, "00:00:10:11")
    }

    func testApplySpeakerAutocompleteSuggestionCommitsDirectlyToTargetLine() {
        let model = EditorViewModel()
        let target = DialogueLine(index: 1, speaker: "VIVIAN", text: "A", startTimecode: "", endTimecode: "")
        let other = DialogueLine(index: 2, speaker: "KEL", text: "B", startTimecode: "", endTimecode: "")
        model.lines = [target, other]

        let applied = model.applySpeakerAutocompleteSuggestion(
            lineID: target.id,
            suggestion: "  KELLY  "
        )

        XCTAssertTrue(applied)
        XCTAssertEqual(model.lines[0].speaker, "KELLY")
        XCTAssertEqual(model.lines[1].speaker, "KEL")
    }

    func testSpeakerColorOverrideUsesNormalizedSpeakerKeyAndCanReset() {
        let model = EditorViewModel()

        model.setSpeakerColorOverride(for: "  Jocelyn  ", paletteID: SpeakerColorPaletteID.rose.rawValue)

        XCTAssertEqual(model.speakerColorOverridePaletteID(for: "JOCELYN"), .rose)
        XCTAssertEqual(model.speakerColorOverridePaletteID(for: "jocelyn"), .rose)

        model.resetSpeakerColorOverride(for: "  JOCELYN ")

        XCTAssertNil(model.speakerColorOverridePaletteID(for: "Jocelyn"))
        XCTAssertTrue(model.speakerColorOverridesByKey.isEmpty)
    }

    func testSpeakerColorOverrideMatchingDefaultDoesNotPersistExplicitOverride() {
        let model = EditorViewModel()
        let defaultPaletteID = try XCTUnwrap(
            SpeakerAppearanceService.defaultPaletteID(for: "TRINITY")
        )

        model.setSpeakerColorOverride(for: "TRINITY", paletteID: defaultPaletteID.rawValue)

        XCTAssertNil(model.speakerColorOverridePaletteID(for: "TRINITY"))
        XCTAssertTrue(model.speakerColorOverridesByKey.isEmpty)
    }

    func testCaptureStartTimecodeForSelectedLineAdvancesSelection() {
        let model = EditorViewModel()
        let line1 = DialogueLine(index: 1, speaker: "A", text: "One", startTimecode: "", endTimecode: "")
        let line2 = DialogueLine(index: 2, speaker: "B", text: "Two", startTimecode: "", endTimecode: "")
        model.lines = [line1, line2]
        model.selectedLineID = line1.id

        model.captureStartTimecodeForSelectedLine(advanceToNext: true)

        XCTAssertEqual(model.lines[0].startTimecode, "00:00:00:00")
        XCTAssertEqual(model.selectedLineID, line2.id)
        XCTAssertEqual(model.highlightedLineID, line2.id)
    }

    func testCaptureEndTimecodeWithoutSelectionUsesFirstLine() {
        let model = EditorViewModel()
        let line1 = DialogueLine(index: 1, speaker: "A", text: "One", startTimecode: "", endTimecode: "")
        let line2 = DialogueLine(index: 2, speaker: "B", text: "Two", startTimecode: "", endTimecode: "")
        model.lines = [line1, line2]
        model.selectedLineID = nil

        model.captureEndTimecodeForSelectedLine(advanceToNext: false)

        XCTAssertEqual(model.selectedLineID, line1.id)
        XCTAssertEqual(model.highlightedLineID, line1.id)
        XCTAssertEqual(model.lines[0].endTimecode, "00:00:00:00")
    }

    func testCaptureStartTimecodeWithoutAdvanceKeepsSelection() {
        let model = EditorViewModel()
        let line1 = DialogueLine(index: 1, speaker: "A", text: "One", startTimecode: "", endTimecode: "")
        let line2 = DialogueLine(index: 2, speaker: "B", text: "Two", startTimecode: "", endTimecode: "")
        model.lines = [line1, line2]
        model.selectedLineID = line1.id
        model.isTimecodeAutoSwitchTargetEnabled = false

        model.captureStartTimecodeForSelectedLine(advanceToNext: false)

        XCTAssertEqual(model.timecodeCaptureTarget, .start)
        XCTAssertEqual(model.selectedLineID, line1.id)
        XCTAssertEqual(model.highlightedLineID, line1.id)
        XCTAssertEqual(model.lines[0].startTimecode, "00:00:00:00")
    }

    func testCaptureStartTimecodeWithoutAdvanceAutoSwitchesToEndWhenEnabled() {
        let model = EditorViewModel()
        model.lines = [
            DialogueLine(index: 1, speaker: "A", text: "One", startTimecode: "", endTimecode: "")
        ]
        model.selectedLineID = model.lines[0].id
        model.isTimecodeAutoSwitchTargetEnabled = true

        model.captureStartTimecodeForSelectedLine(advanceToNext: false)

        XCTAssertEqual(model.timecodeCaptureTarget, .end)
        XCTAssertEqual(model.lines[0].startTimecode, "00:00:00:00")
    }

    func testCaptureEndTimecodeAutoSwitchesToStartWhenEnabled() {
        let model = EditorViewModel()
        model.lines = [
            DialogueLine(index: 1, speaker: "A", text: "One", startTimecode: "", endTimecode: "")
        ]
        model.selectedLineID = model.lines[0].id
        model.isTimecodeAutoSwitchTargetEnabled = true

        model.captureEndTimecodeForSelectedLine(advanceToNext: false)

        XCTAssertEqual(model.timecodeCaptureTarget, .start)
        XCTAssertEqual(model.lines[0].endTimecode, "00:00:00:00")
    }

    func testSelectNextLineMissingTimecodeForActiveTargetWraps() {
        let model = EditorViewModel()
        let line1 = DialogueLine(index: 1, speaker: "A", text: "One", startTimecode: "00:00:01:00", endTimecode: "00:00:02:00")
        let line2 = DialogueLine(index: 2, speaker: "B", text: "Two", startTimecode: "", endTimecode: "00:00:04:00")
        let line3 = DialogueLine(index: 3, speaker: "C", text: "Three", startTimecode: "00:00:05:00", endTimecode: "")
        model.lines = [line1, line2, line3]
        model.selectedLineID = line3.id
        model.timecodeCaptureTarget = .start

        let movedToStart = model.selectNextLineMissingTimecodeForActiveTarget()

        XCTAssertTrue(movedToStart)
        XCTAssertEqual(model.selectedLineID, line2.id)

        model.timecodeCaptureTarget = .end
        let movedToEnd = model.selectNextLineMissingTimecodeForActiveTarget()

        XCTAssertTrue(movedToEnd)
        XCTAssertEqual(model.selectedLineID, line3.id)
    }

    func testPrefillEmptyStartTimecodeUsesPreviousHourMinutePrefix() {
        let model = EditorViewModel()
        let line1 = DialogueLine(index: 1, speaker: "A", text: "One", startTimecode: "01:24:18:10", endTimecode: "")
        let line2 = DialogueLine(index: 2, speaker: "B", text: "Two", startTimecode: "", endTimecode: "")
        model.lines = [line1, line2]
        model.isTimecodeModeEnabled = true

        let changed = model.prefillEmptyTimecodeWithPreviousHourMinute(
            lineID: line2.id,
            target: .start
        )

        XCTAssertTrue(changed)
        XCTAssertEqual(model.lines[1].startTimecode, "01:24:")
    }

    func testPrefillEmptyStartTimecodeUsesPreviousPrefixWithoutSeconds() {
        let model = EditorViewModel()
        let line1 = DialogueLine(index: 1, speaker: "A", text: "One", startTimecode: "01:24:", endTimecode: "")
        let line2 = DialogueLine(index: 2, speaker: "B", text: "Two", startTimecode: "", endTimecode: "")
        model.lines = [line1, line2]
        model.isTimecodeModeEnabled = true

        let changed = model.prefillEmptyTimecodeWithPreviousHourMinute(
            lineID: line2.id,
            target: .start
        )

        XCTAssertTrue(changed)
        XCTAssertEqual(model.lines[1].startTimecode, "01:24:")
    }

    func testPrefillEmptyStartTimecodeNormalizesPreviousMinuteSecondInput() {
        let model = EditorViewModel()
        let line1 = DialogueLine(index: 1, speaker: "A", text: "One", startTimecode: "06:45", endTimecode: "")
        let line2 = DialogueLine(index: 2, speaker: "B", text: "Two", startTimecode: "", endTimecode: "")
        model.lines = [line1, line2]
        model.isTimecodeModeEnabled = true

        let changed = model.prefillEmptyTimecodeWithPreviousHourMinute(
            lineID: line2.id,
            target: .start
        )

        XCTAssertTrue(changed)
        XCTAssertEqual(model.lines[1].startTimecode, "00:06:")
    }

    func testPrefillEmptyEndTimecodeUsesPreviousHourMinutePrefix() {
        let model = EditorViewModel()
        let line1 = DialogueLine(index: 1, speaker: "A", text: "One", startTimecode: "", endTimecode: "00:59:44:22")
        let line2 = DialogueLine(index: 2, speaker: "B", text: "Two", startTimecode: "", endTimecode: "")
        model.lines = [line1, line2]
        model.isTimecodeModeEnabled = true

        let changed = model.prefillEmptyTimecodeWithPreviousHourMinute(
            lineID: line2.id,
            target: .end
        )

        XCTAssertTrue(changed)
        XCTAssertEqual(model.lines[1].endTimecode, "00:59:")
    }

    func testPrefillDoesNothingWhenPreviousTimecodeMissing() {
        let model = EditorViewModel()
        let line1 = DialogueLine(index: 1, speaker: "A", text: "One", startTimecode: "", endTimecode: "")
        let line2 = DialogueLine(index: 2, speaker: "B", text: "Two", startTimecode: "", endTimecode: "")
        model.lines = [line1, line2]
        model.isTimecodeModeEnabled = true

        let changed = model.prefillEmptyTimecodeWithPreviousHourMinute(
            lineID: line2.id,
            target: .start
        )

        XCTAssertFalse(changed)
        XCTAssertEqual(model.lines[1].startTimecode, "")
    }

    func testChronologicalStartIssuesDetectsDescendingStartTimecodes() {
        let model = EditorViewModel()
        model.lines = [
            DialogueLine(index: 1, speaker: "A", text: "One", startTimecode: "00:00:10:00", endTimecode: ""),
            DialogueLine(index: 2, speaker: "B", text: "Two", startTimecode: "00:00:09:00", endTimecode: ""),
            DialogueLine(index: 3, speaker: "C", text: "Three", startTimecode: "00:00:11:00", endTimecode: ""),
            DialogueLine(index: 4, speaker: "D", text: "Four", startTimecode: "00:00:10:12", endTimecode: "")
        ]

        let issues = model.chronologicalStartIssues()

        XCTAssertEqual(issues.count, 2)
        XCTAssertEqual(issues[0].previousLineIndex, 1)
        XCTAssertEqual(issues[0].lineIndex, 2)
        XCTAssertEqual(issues[1].previousLineIndex, 3)
        XCTAssertEqual(issues[1].lineIndex, 4)
    }

    func testChronologicalStartIssuesSkipMissingStartTimecodes() {
        let model = EditorViewModel()
        model.lines = [
            DialogueLine(index: 1, speaker: "A", text: "One", startTimecode: "00:00:05:00", endTimecode: ""),
            DialogueLine(index: 2, speaker: "B", text: "Two", startTimecode: "", endTimecode: ""),
            DialogueLine(index: 3, speaker: "C", text: "Three", startTimecode: "00:00:04:00", endTimecode: "")
        ]

        let issues = model.chronologicalStartIssues()

        XCTAssertEqual(issues.count, 1)
        XCTAssertEqual(issues[0].previousLineIndex, 1)
        XCTAssertEqual(issues[0].lineIndex, 3)
    }

    func testShiftExtendSelectionCreatesContiguousRange() {
        let model = EditorViewModel()
        let line1 = DialogueLine(index: 1, speaker: "A", text: "One", startTimecode: "", endTimecode: "")
        let line2 = DialogueLine(index: 2, speaker: "B", text: "Two", startTimecode: "", endTimecode: "")
        let line3 = DialogueLine(index: 3, speaker: "C", text: "Three", startTimecode: "", endTimecode: "")
        let line4 = DialogueLine(index: 4, speaker: "D", text: "Four", startTimecode: "", endTimecode: "")
        model.lines = [line1, line2, line3, line4]

        model.selectLine(line2)
        model.selectLine(line4, extendSelection: true)

        XCTAssertEqual(model.selectedLineID, line4.id)
        XCTAssertEqual(model.selectedLineIDs, Set([line2.id, line3.id, line4.id]))
    }

    func testDeleteSelectedLinesRemovesMultiSelectionAndRenumbers() {
        let model = EditorViewModel()
        let line1 = DialogueLine(index: 1, speaker: "A", text: "One", startTimecode: "", endTimecode: "")
        let line2 = DialogueLine(index: 2, speaker: "B", text: "Two", startTimecode: "", endTimecode: "")
        let line3 = DialogueLine(index: 3, speaker: "C", text: "Three", startTimecode: "", endTimecode: "")
        let line4 = DialogueLine(index: 4, speaker: "D", text: "Four", startTimecode: "", endTimecode: "")
        model.lines = [line1, line2, line3, line4]
        model.selectedLineID = line3.id
        model.selectedLineIDs = [line2.id, line3.id]

        let deleted = model.deleteSelectedLines()

        XCTAssertEqual(deleted, 2)
        XCTAssertEqual(model.lines.count, 2)
        XCTAssertEqual(model.lines.map(\.id), [line1.id, line4.id])
        XCTAssertEqual(model.lines.map(\.index), [1, 2])
        XCTAssertEqual(model.selectedLineID, line4.id)
        XCTAssertEqual(model.selectedLineIDs, Set([line4.id]))
    }

    func testFillMissingStartTimecodesWithPreviousHourMinuteFillsEmptyRows() {
        let model = EditorViewModel()
        model.lines = [
            DialogueLine(index: 1, speaker: "A", text: "One", startTimecode: "01:10:05:12", endTimecode: ""),
            DialogueLine(index: 2, speaker: "B", text: "Two", startTimecode: "", endTimecode: ""),
            DialogueLine(index: 3, speaker: "C", text: "Three", startTimecode: "01:11:", endTimecode: ""),
            DialogueLine(index: 4, speaker: "D", text: "Four", startTimecode: "", endTimecode: ""),
            DialogueLine(index: 5, speaker: "E", text: "Five", startTimecode: "", endTimecode: ""),
            DialogueLine(index: 6, speaker: "F", text: "Six", startTimecode: "02:20:00:00", endTimecode: ""),
            DialogueLine(index: 7, speaker: "G", text: "Seven", startTimecode: "", endTimecode: "")
        ]

        let filled = model.fillMissingStartTimecodesWithPreviousHourMinute()

        XCTAssertEqual(filled, 4)
        XCTAssertEqual(model.lines[1].startTimecode, "01:10:")
        XCTAssertEqual(model.lines[3].startTimecode, "01:11:")
        XCTAssertEqual(model.lines[4].startTimecode, "01:11:")
        XCTAssertEqual(model.lines[6].startTimecode, "02:20:")
    }

    func testFillMissingStartTimecodesWithPreviousHourMinuteNormalizesMinuteSecondInput() {
        let model = EditorViewModel()
        model.lines = [
            DialogueLine(index: 1, speaker: "A", text: "One", startTimecode: "06:45", endTimecode: ""),
            DialogueLine(index: 2, speaker: "B", text: "Two", startTimecode: "", endTimecode: "")
        ]

        let filled = model.fillMissingStartTimecodesWithPreviousHourMinute()

        XCTAssertEqual(filled, 1)
        XCTAssertEqual(model.lines[1].startTimecode, "00:06:")
    }

    func testPlaybackTimelineConversionsUseVideoOffset() {
        let model = EditorViewModel()
        model.videoOffsetSeconds = 2.5

        XCTAssertEqual(model.playbackSeconds(fromTimelineSeconds: 10), 12.5, accuracy: 0.0001)
        XCTAssertEqual(model.timelineSeconds(fromPlaybackSeconds: 12.5), 10, accuracy: 0.0001)
        XCTAssertEqual(model.timelineSeconds(fromPlaybackSeconds: 1), 0, accuracy: 0.0001)
    }

    func testApplyVideoOffsetParsesSecondsAndTimecode() {
        let model = EditorViewModel()

        model.applyVideoOffset(rawValue: "1.5")
        XCTAssertEqual(model.videoOffsetSeconds, 1.5, accuracy: 0.0001)

        model.applyVideoOffset(rawValue: "-00:00:02:00")
        XCTAssertEqual(model.videoOffsetSeconds, -2, accuracy: 0.0001)
    }

    func testSetFPSPresetChangesProjectFPS() {
        let model = EditorViewModel()

        model.setFPSPreset(.fps23976)
        XCTAssertEqual(model.fps, 23.976, accuracy: 0.000_001)
        XCTAssertEqual(model.fpsPresetSelection, .fps23976)

        model.setFPSPreset(.fps24)
        XCTAssertEqual(model.fps, 24, accuracy: 0.000_001)
        XCTAssertEqual(model.fpsPresetSelection, .fps24)
    }

    func testQualityIssuesIncludesOnlyConfiguredValidationTypes() {
        let model = EditorViewModel()
        let line = DialogueLine(
            index: 1,
            speaker: "",
            text: "Ahoj",
            startTimecode: "",
            endTimecode: ""
        )

        var issues = model.qualityIssues(for: line)
        XCTAssertEqual(
            Set(issues),
            Set([
                "Chybejici charakter.",
                "Chybejici start TC.",
                "Chybejici end TC."
            ])
        )

        model.validateMissingSpeaker = false
        model.validateMissingStartTC = false
        model.validateMissingEndTC = true
        model.validateInvalidTC = false

        issues = model.qualityIssues(for: line)
        XCTAssertEqual(issues, ["Chybejici end TC."])
    }

    func testQualityIssuesFlagsInvalidTimecodeWhenEnabled() {
        let model = EditorViewModel()
        let line = DialogueLine(
            index: 1,
            speaker: "A",
            text: "Ahoj",
            startTimecode: "abc",
            endTimecode: "00:00:03:00"
        )

        var issues = model.qualityIssues(for: line)
        XCTAssertTrue(issues.contains("Spatne zadany TC."))

        model.validateInvalidTC = false
        issues = model.qualityIssues(for: line)
        XCTAssertFalse(issues.contains("Spatne zadany TC."))
    }

    func testSpeakerStatisticsRefreshAsynchronouslyAfterLinesChange() async {
        let model = EditorViewModel()
        model.lines = [
            DialogueLine(index: 1, speaker: "ETTA", text: "Jedna dve tri", startTimecode: "", endTimecode: ""),
            DialogueLine(index: 2, speaker: "", text: "Bez speakeru", startTimecode: "", endTimecode: ""),
            DialogueLine(index: 3, speaker: "ETTA", text: "Ctvrta pata", startTimecode: "", endTimecode: ""),
            DialogueLine(index: 4, speaker: "MIKE", text: "Sesta", startTimecode: "", endTimecode: "")
        ]

        model.handleLinesDidChange()
        try? await Task.sleep(nanoseconds: 500_000_000)

        let stats = model.speakerStatistics()
        XCTAssertEqual(model.missingSpeakerCount, 1)
        XCTAssertEqual(stats.map(\.speaker), ["ETTA", "MIKE"])
        XCTAssertEqual(stats.first?.entries, 2)
        XCTAssertEqual(stats.first?.wordCount, 5)
    }

    private func attachSeekableVideo(to model: EditorViewModel, seekSeconds: Double) {
        let composition = AVMutableComposition()
        composition.insertEmptyTimeRange(
            CMTimeRange(
                start: .zero,
                duration: CMTime(seconds: 300, preferredTimescale: 600)
            )
        )

        let item = AVPlayerItem(asset: composition)
        model.player.replaceCurrentItem(with: item)
        model.player.seek(
            to: CMTime(seconds: seekSeconds, preferredTimescale: 600),
            toleranceBefore: .zero,
            toleranceAfter: .zero
        )
    }

    private func waitForPlayerSeek() async {
        try? await Task.sleep(nanoseconds: 120_000_000)
    }
}
#endif
