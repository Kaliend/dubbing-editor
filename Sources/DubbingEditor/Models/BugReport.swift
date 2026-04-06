import Foundation

struct BugReportDraft: Equatable, Sendable {
    var title: String = ""
    var reproductionSteps: String = ""
    var expectedBehavior: String = ""
    var actualBehavior: String = ""
    var includeWindowScreenshot: Bool = true
    var includeLogs: Bool = true
    var includeProjectSnapshot: Bool = true
}

struct BugReportUIState: Codable, Hashable, Sendable {
    var rightPaneTab: String
    var findQuery: String
    var replaceQuery: String
    var showOnlyChronologyIssues: Bool
    var showOnlyMissingSpeakerIssues: Bool
    var selectedCharacterFilters: [String]
}

struct BugReportLineContext: Codable, Hashable, Sendable {
    let id: UUID
    let index: Int
    let speaker: String
    let startTimecode: String
    let endTimecode: String
    let textPreview: String
}

struct BugReportEditorState: Codable, Hashable, Sendable {
    let documentTitle: String
    let lineCount: Int
    let selectedLineCount: Int
    let fps: Double
    let playbackPositionSeconds: Double?
    let isLoopEnabled: Bool
    let isPlaybackActive: Bool
    let isTimecodeModeEnabled: Bool
    let timecodeCaptureTarget: String
    let playbackSeekStepSeconds: Double
    let videoOffsetSeconds: Double
    let isReplayPrerollEnabled: Bool
    let isLightModeEnabled: Bool
    let showValidationIssues: Bool
    let showOnlyIssues: Bool
    let validateMissingSpeaker: Bool
    let validateMissingStartTC: Bool
    let validateMissingEndTC: Bool
    let validateInvalidTC: Bool
    let currentProjectPath: String?
    let sourceWordPath: String?
    let sourceVideoPath: String?
    let selectedLine: BugReportLineContext?
    let highlightedLine: BugReportLineContext?
    let editingLine: BugReportLineContext?
}

struct BugReportContext: Codable, Hashable, Sendable {
    let createdAt: Date
    let appVersion: String
    let buildNumber: String
    let osVersion: String
    let reportIdentifier: String
    let draft: BugReportDraftPayload
    let editor: BugReportEditorState
    let ui: BugReportUIState
}

struct BugReportDraftPayload: Codable, Hashable, Sendable {
    let title: String
    let reproductionSteps: String
    let expectedBehavior: String
    let actualBehavior: String
    let includeWindowScreenshot: Bool
    let includeLogs: Bool
    let includeProjectSnapshot: Bool

    init(draft: BugReportDraft) {
        title = draft.title
        reproductionSteps = draft.reproductionSteps
        expectedBehavior = draft.expectedBehavior
        actualBehavior = draft.actualBehavior
        includeWindowScreenshot = draft.includeWindowScreenshot
        includeLogs = draft.includeLogs
        includeProjectSnapshot = draft.includeProjectSnapshot
    }
}

struct BugReportIndexEntry: Codable, Hashable, Sendable {
    let identifier: String
    let createdAt: Date
    let title: String
    let folderName: String
    let documentTitle: String
    let projectPath: String?
    let selectedLineIndex: Int?
    let selectedLineSpeaker: String?
    let hasWindowScreenshot: Bool
    let hasProjectSnapshot: Bool
    let hasLogs: Bool
    let hasArchive: Bool
}
