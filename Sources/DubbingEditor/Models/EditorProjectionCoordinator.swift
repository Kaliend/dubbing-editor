import Foundation

struct EditorProjectionInput {
    let lines: [DialogueLine]
    let fps: Double
    let findQuery: String
    let showValidationIssues: Bool
    let showOnlyIssues: Bool
    let validateMissingSpeaker: Bool
    let validateMissingStartTC: Bool
    let validateMissingEndTC: Bool
    let validateInvalidTC: Bool
    let showOnlyChronologyIssues: Bool
    let showOnlyMissingSpeakerIssues: Bool
    let selectedCharacterFilterKeys: Set<String>
    let visibleLineIDs: Set<DialogueLine.ID>
    let useViewportScopedIssues: Bool
    let selectedLineID: DialogueLine.ID?
    let editingLineID: DialogueLine.ID?
    let highlightedLineID: DialogueLine.ID?
    let activeSearchLineID: DialogueLine.ID?
    let isLightModeEnabled: Bool
}

struct EditorProjectionResult: Equatable {
    var issuesByLineID: [DialogueLine.ID: [String]] = [:]
    var chronoStartIssues: [EditorViewModel.ChronologicalStartIssue] = []
    var chronoIssueLineIDs: Set<DialogueLine.ID> = []
    var displayedLineIndices: [Int] = []
    var normalizedSearchHaystackByLineID: [DialogueLine.ID: String] = [:]
    var searchMatchIndices: [Int] = []
    var normalizedFindQuery: String = ""
    var issueLineCount: Int = 0
    var issueCountIsViewportScoped: Bool = false
}

final class EditorProjectionCoordinator {
    private static let searchLocale = Locale(identifier: "cs_CZ")
    private var retainedIssuesByLineID: [DialogueLine.ID: [String]] = [:]

    func rebuildAll(from input: EditorProjectionInput) -> EditorProjectionResult {
        var result = EditorProjectionResult()
        result.issueCountIsViewportScoped = input.useViewportScopedIssues

        let shouldComputeIssues = shouldComputeIssues(in: input)
        let shouldMaintainSearchHaystack = shouldMaintainSearchHaystack(in: input)
        let issueTargetLineIDs = shouldComputeIssues
            ? validationEvaluationTargetLineIDs(in: input)
            : []

        result.issuesByLineID = buildIssuesByLineID(
            from: input,
            shouldComputeIssues: shouldComputeIssues,
            issueTargetLineIDs: issueTargetLineIDs
        )
        result.chronoStartIssues = chronologicalStartIssues(in: input.lines, fps: input.fps)
        result.chronoIssueLineIDs = Set(result.chronoStartIssues.map(\.lineID))
        result.normalizedSearchHaystackByLineID = shouldMaintainSearchHaystack
            ? buildSearchHaystackByLineID(for: input.lines)
            : [:]

        rebuildDisplayedIndicesAndIssueCount(in: &result, from: input)
        rebuildSearch(in: &result, from: input)
        retainedIssuesByLineID = result.issuesByLineID
        return result
    }

    @discardableResult
    func refreshSingleLine(
        _ lineID: DialogueLine.ID,
        in result: inout EditorProjectionResult,
        from input: EditorProjectionInput
    ) -> Bool {
        guard
            let lineIndex = input.lines.firstIndex(where: { $0.id == lineID }),
            input.lines.indices.contains(lineIndex)
        else {
            return false
        }

        let line = input.lines[lineIndex]
        if shouldComputeIssues(in: input) {
            result.issuesByLineID[lineID] = qualityIssues(for: line, in: input)
        } else {
            result.issuesByLineID[lineID] = []
        }

        if shouldMaintainSearchHaystack(in: input) {
            result.normalizedSearchHaystackByLineID[lineID] = searchHaystack(for: line)
        } else {
            result.normalizedSearchHaystackByLineID.removeValue(forKey: lineID)
        }

        retainedIssuesByLineID = result.issuesByLineID
        return true
    }

    func rebuildDisplayedIndicesAndIssueCount(
        in result: inout EditorProjectionResult,
        from input: EditorProjectionInput
    ) {
        let showOnlyValidationIssues = input.showValidationIssues && input.showOnlyIssues
        let hasCharacterFilter = !input.selectedCharacterFilterKeys.isEmpty
        var displayedLineIndices: [Int] = []
        displayedLineIndices.reserveCapacity(input.lines.count)

        var issueLineCount = 0
        for index in input.lines.indices {
            let line = input.lines[index]
            let hasValidationIssues = !(result.issuesByLineID[line.id] ?? []).isEmpty
            let hasChronologyIssue = result.chronoIssueLineIDs.contains(line.id)
            let hasMissingSpeaker = line.speaker.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty

            if hasValidationIssues {
                issueLineCount += 1
            }

            if showOnlyValidationIssues && !hasValidationIssues {
                continue
            }
            if input.showOnlyChronologyIssues && !hasChronologyIssue {
                continue
            }
            if input.showOnlyMissingSpeakerIssues && !hasMissingSpeaker {
                continue
            }
            if hasCharacterFilter && !input.selectedCharacterFilterKeys.contains(Self.normalizedSpeakerKey(line.speaker)) {
                continue
            }

            displayedLineIndices.append(index)
        }

        result.displayedLineIndices = displayedLineIndices
        result.issueLineCount = issueLineCount
    }

    func rebuildSearch(
        in result: inout EditorProjectionResult,
        from input: EditorProjectionInput
    ) {
        let query = Self.normalizeSearch(input.findQuery)
        result.normalizedFindQuery = query

        guard !query.isEmpty else {
            result.normalizedSearchHaystackByLineID = [:]
            result.searchMatchIndices = []
            return
        }

        ensureSearchHaystackCacheBuilt(in: &result, lines: input.lines)

        var matches: [Int] = []
        let displayedLineIndices = result.displayedLineIndices.filter { input.lines.indices.contains($0) }
        matches.reserveCapacity(min(256, displayedLineIndices.count))

        for index in displayedLineIndices {
            let line = input.lines[index]
            let haystack = result.normalizedSearchHaystackByLineID[line.id] ?? searchHaystack(for: line)
            if haystack.contains(query) {
                matches.append(index)
            }
        }

        result.searchMatchIndices = matches
    }

    static func normalizeSearch(_ value: String) -> String {
        value
            .folding(options: [.diacriticInsensitive, .caseInsensitive], locale: searchLocale)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    static func normalizedSpeakerKey(_ speaker: String) -> String {
        SpeakerAppearanceService.normalizedSpeakerKey(speaker)
    }

    private func shouldComputeIssues(in input: EditorProjectionInput) -> Bool {
        input.showOnlyIssues || (input.showValidationIssues && !input.isLightModeEnabled)
    }

    private func shouldMaintainSearchHaystack(in input: EditorProjectionInput) -> Bool {
        !input.findQuery.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private func validationEvaluationTargetLineIDs(in input: EditorProjectionInput) -> Set<DialogueLine.ID> {
        guard shouldComputeIssues(in: input) else { return [] }
        guard input.useViewportScopedIssues else {
            return Set(input.lines.map(\.id))
        }

        var targetLineIDs = input.visibleLineIDs
        if let selectedLineID = input.selectedLineID {
            targetLineIDs.insert(selectedLineID)
        }
        if let editingLineID = input.editingLineID {
            targetLineIDs.insert(editingLineID)
        }
        if let highlightedLineID = input.highlightedLineID {
            targetLineIDs.insert(highlightedLineID)
        }
        if let activeSearchLineID = input.activeSearchLineID {
            targetLineIDs.insert(activeSearchLineID)
        }
        return targetLineIDs
    }

    private func buildIssuesByLineID(
        from input: EditorProjectionInput,
        shouldComputeIssues: Bool,
        issueTargetLineIDs: Set<DialogueLine.ID>
    ) -> [DialogueLine.ID: [String]] {
        var issuesByLineID: [DialogueLine.ID: [String]] = [:]
        issuesByLineID.reserveCapacity(input.lines.count)

        for line in input.lines {
            if shouldComputeIssues, issueTargetLineIDs.contains(line.id) {
                issuesByLineID[line.id] = qualityIssues(for: line, in: input)
            } else if shouldComputeIssues && input.useViewportScopedIssues {
                issuesByLineID[line.id] = retainedIssuesByLineID[line.id] ?? []
            } else {
                issuesByLineID[line.id] = []
            }
        }

        return issuesByLineID
    }

    private func qualityIssues(for line: DialogueLine, in input: EditorProjectionInput) -> [String] {
        var issues: [String] = []
        let speaker = line.speaker.trimmingCharacters(in: .whitespacesAndNewlines)
        let start = line.startTimecode.trimmingCharacters(in: .whitespacesAndNewlines)
        let end = line.endTimecode.trimmingCharacters(in: .whitespacesAndNewlines)

        if input.validateMissingSpeaker, speaker.isEmpty {
            issues.append("Chybejici charakter.")
        }
        if input.validateMissingStartTC, start.isEmpty {
            issues.append("Chybejici start TC.")
        }
        if input.validateMissingEndTC, end.isEmpty {
            issues.append("Chybejici end TC.")
        }
        if input.validateInvalidTC {
            let hasInvalidStart = !start.isEmpty && TimecodeService.seconds(from: start, fps: input.fps) == nil
            let hasInvalidEnd = !end.isEmpty && TimecodeService.seconds(from: end, fps: input.fps) == nil
            if hasInvalidStart || hasInvalidEnd {
                issues.append("Spatne zadany TC.")
            }
        }

        return issues
    }

    private func chronologicalStartIssues(
        in lines: [DialogueLine],
        fps: Double
    ) -> [EditorViewModel.ChronologicalStartIssue] {
        var issues: [EditorViewModel.ChronologicalStartIssue] = []
        issues.reserveCapacity(max(0, lines.count / 10))

        var previousValidLine: (line: DialogueLine, seconds: Double)?
        for line in lines {
            guard let currentSeconds = TimecodeService.seconds(from: line.startTimecode, fps: fps) else {
                continue
            }

            if let previousValidLine, currentSeconds < previousValidLine.seconds {
                issues.append(
                    EditorViewModel.ChronologicalStartIssue(
                        previousLineID: previousValidLine.line.id,
                        lineID: line.id,
                        previousLineIndex: previousValidLine.line.index,
                        lineIndex: line.index,
                        previousStartTimecode: previousValidLine.line.startTimecode,
                        startTimecode: line.startTimecode,
                        previousStartSeconds: previousValidLine.seconds,
                        startSeconds: currentSeconds
                    )
                )
            }

            previousValidLine = (line: line, seconds: currentSeconds)
        }

        return issues
    }

    private func buildSearchHaystackByLineID(for lines: [DialogueLine]) -> [DialogueLine.ID: String] {
        var haystackByLineID: [DialogueLine.ID: String] = [:]
        haystackByLineID.reserveCapacity(lines.count)
        for line in lines {
            haystackByLineID[line.id] = searchHaystack(for: line)
        }
        return haystackByLineID
    }

    private func ensureSearchHaystackCacheBuilt(
        in result: inout EditorProjectionResult,
        lines: [DialogueLine]
    ) {
        guard result.normalizedSearchHaystackByLineID.count != lines.count else { return }
        result.normalizedSearchHaystackByLineID = buildSearchHaystackByLineID(for: lines)
    }

    private func searchHaystack(for line: DialogueLine) -> String {
        Self.normalizeSearch(
            "\(line.speaker) \(line.startTimecode) \(line.endTimecode) \(line.text)"
        )
    }
}
