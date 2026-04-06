import Foundation

struct DialogueRowDraftController {
    private struct DisplayCacheSignature: Equatable {
        let fps: Double
        let hideFrames: Bool
    }

    var editableTextDraft: String = ""
    var speakerDraft: String = ""
    var startTimecodeDraft: String = ""
    var endTimecodeDraft: String = ""
    private(set) var displayedStartTimecode: String?
    private(set) var displayedEndTimecode: String?
    private var displayedTimecodeSignature: DisplayCacheSignature?

    mutating func load(
        from line: DialogueLine,
        fps: Double,
        hideFrames: Bool
    ) {
        editableTextDraft = line.text
        speakerDraft = line.speaker
        syncTimecodesFromModel(
            line: line,
            fps: fps,
            hideFrames: hideFrames,
            isStartFocused: false,
            isEndFocused: false
        )
    }

    mutating func syncTextFromModel(
        _ line: DialogueLine,
        isFocused: Bool,
        forceWhileFocused: Bool = false
    ) {
        guard forceWhileFocused || !isFocused else { return }
        if editableTextDraft != line.text {
            editableTextDraft = line.text
        }
    }

    mutating func syncSpeakerFromModel(
        _ line: DialogueLine,
        isFocused: Bool,
        forceWhileFocused: Bool = false
    ) {
        guard forceWhileFocused || !isFocused else { return }
        if speakerDraft != line.speaker {
            speakerDraft = line.speaker
        }
    }

    mutating func syncTimecodesFromModel(
        line: DialogueLine,
        fps: Double,
        hideFrames: Bool,
        isStartFocused: Bool,
        isEndFocused: Bool
    ) {
        syncDisplayedTimecodesFromModel(line: line, fps: fps, hideFrames: hideFrames)

        if !isStartFocused {
            startTimecodeDraft = resolvedDisplayedStartTimecode(
                for: line,
                fps: fps,
                hideFrames: hideFrames
            )
        }
        if !isEndFocused {
            endTimecodeDraft = resolvedDisplayedEndTimecode(
                for: line,
                fps: fps,
                hideFrames: hideFrames
            )
        }
    }

    mutating func syncStartTimecodeFromModel(
        _ line: DialogueLine,
        fps: Double,
        hideFrames: Bool,
        isFocused: Bool
    ) {
        displayedStartTimecode = Self.displayedTimecode(
            line.startTimecode,
            fps: fps,
            hideFrames: hideFrames
        )
        if !isFocused {
            startTimecodeDraft = resolvedDisplayedStartTimecode(
                for: line,
                fps: fps,
                hideFrames: hideFrames
            )
        }
    }

    mutating func syncEndTimecodeFromModel(
        _ line: DialogueLine,
        fps: Double,
        hideFrames: Bool,
        isFocused: Bool
    ) {
        displayedEndTimecode = Self.displayedTimecode(
            line.endTimecode,
            fps: fps,
            hideFrames: hideFrames
        )
        if !isFocused {
            endTimecodeDraft = resolvedDisplayedEndTimecode(
                for: line,
                fps: fps,
                hideFrames: hideFrames
            )
        }
    }

    mutating func updateForHideFramesChange(
        line: DialogueLine,
        fps: Double,
        hideFrames: Bool,
        isStartFocused: Bool,
        isEndFocused: Bool
    ) {
        syncTimecodesFromModel(
            line: line,
            fps: fps,
            hideFrames: hideFrames,
            isStartFocused: isStartFocused,
            isEndFocused: isEndFocused
        )
    }

    mutating func prepareSpeakerEditing(from line: DialogueLine) {
        speakerDraft = line.speaker
    }

    mutating func prepareStartTimecodeEditing(
        from line: DialogueLine,
        fps: Double,
        hideFrames: Bool
    ) {
        syncStartTimecodeFromModel(line, fps: fps, hideFrames: hideFrames, isFocused: false)
    }

    mutating func prepareEndTimecodeEditing(
        from line: DialogueLine,
        fps: Double,
        hideFrames: Bool
    ) {
        syncEndTimecodeFromModel(line, fps: fps, hideFrames: hideFrames, isFocused: false)
    }

    mutating func commitTextIfNeeded(
        into line: inout DialogueLine,
        onCommit: (String) -> Void
    ) {
        guard line.text != editableTextDraft else { return }
        line.text = editableTextDraft
        onCommit("text")
    }

    @discardableResult
    mutating func commitSpeakerIfNeeded(
        into line: inout DialogueLine,
        onCommit: (String) -> Void
    ) -> Bool {
        let didChange = line.speaker != speakerDraft
        if didChange {
            line.speaker = speakerDraft
            onCommit("speaker")
        }
        speakerDraft = line.speaker
        return didChange
    }

    mutating func commitStartTimecodeIfNeeded(
        into line: inout DialogueLine,
        fps: Double,
        hideFrames: Bool,
        onCommit: (String) -> Void
    ) {
        let normalized = Self.normalizedEditedTimecode(
            startTimecodeDraft,
            fps: fps,
            hideFrames: hideFrames
        )
        if line.startTimecode != normalized {
            line.startTimecode = normalized
            onCommit("start_tc")
        }
        syncStartTimecodeFromModel(line, fps: fps, hideFrames: hideFrames, isFocused: false)
    }

    mutating func commitEndTimecodeIfNeeded(
        into line: inout DialogueLine,
        fps: Double,
        hideFrames: Bool,
        onCommit: (String) -> Void
    ) {
        let normalized = Self.normalizedEditedTimecode(
            endTimecodeDraft,
            fps: fps,
            hideFrames: hideFrames
        )
        if line.endTimecode != normalized {
            line.endTimecode = normalized
            onCommit("end_tc")
        }
        syncEndTimecodeFromModel(line, fps: fps, hideFrames: hideFrames, isFocused: false)
    }

    mutating func flushAll(
        into line: inout DialogueLine,
        fps: Double,
        hideFrames: Bool,
        onCommit: (String) -> Void
    ) {
        commitTextIfNeeded(into: &line, onCommit: onCommit)
        _ = commitSpeakerIfNeeded(into: &line, onCommit: onCommit)
        commitStartTimecodeIfNeeded(
            into: &line,
            fps: fps,
            hideFrames: hideFrames,
            onCommit: onCommit
        )
        commitEndTimecodeIfNeeded(
            into: &line,
            fps: fps,
            hideFrames: hideFrames,
            onCommit: onCommit
        )
    }

    func shouldFlushOnDisappear(
        comparedTo line: DialogueLine,
        fps: Double,
        hideFrames: Bool,
        isEditable: Bool,
        hasFocusedField: Bool
    ) -> Bool {
        if isEditable || hasFocusedField {
            return true
        }

        if editableTextDraft != line.text || speakerDraft != line.speaker {
            return true
        }

        if startTimecodeDraft != resolvedDisplayedStartTimecode(for: line, fps: fps, hideFrames: hideFrames) {
            return true
        }

        if endTimecodeDraft != resolvedDisplayedEndTimecode(for: line, fps: fps, hideFrames: hideFrames) {
            return true
        }

        return false
    }

    func resolvedDisplayedStartTimecode(
        for line: DialogueLine,
        fps: Double,
        hideFrames: Bool
    ) -> String {
        if displayedTimecodeSignature == DisplayCacheSignature(fps: fps, hideFrames: hideFrames),
           let displayedStartTimecode {
            return displayedStartTimecode
        }
        return Self.displayedTimecode(line.startTimecode, fps: fps, hideFrames: hideFrames)
    }

    func resolvedDisplayedEndTimecode(
        for line: DialogueLine,
        fps: Double,
        hideFrames: Bool
    ) -> String {
        if displayedTimecodeSignature == DisplayCacheSignature(fps: fps, hideFrames: hideFrames),
           let displayedEndTimecode {
            return displayedEndTimecode
        }
        return Self.displayedTimecode(line.endTimecode, fps: fps, hideFrames: hideFrames)
    }

    private mutating func syncDisplayedTimecodesFromModel(
        line: DialogueLine,
        fps: Double,
        hideFrames: Bool
    ) {
        displayedTimecodeSignature = DisplayCacheSignature(fps: fps, hideFrames: hideFrames)
        displayedStartTimecode = Self.displayedTimecode(
            line.startTimecode,
            fps: fps,
            hideFrames: hideFrames
        )
        displayedEndTimecode = Self.displayedTimecode(
            line.endTimecode,
            fps: fps,
            hideFrames: hideFrames
        )
    }

    static func normalizedEditedTimecode(
        _ edited: String,
        fps: Double,
        hideFrames: Bool
    ) -> String {
        let trimmed = edited.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return "" }

        if hideFrames, let seconds = TimecodeService.seconds(from: trimmed, fps: fps) {
            return TimecodeService.timecode(from: seconds, fps: fps)
        }
        return edited
    }

    private static func displayedTimecode(
        _ raw: String,
        fps: Double,
        hideFrames: Bool
    ) -> String {
        TimecodeService.displayTimecode(raw, fps: fps, hideFrames: hideFrames)
    }
}
