import AVFoundation
import AppKit
import Foundation
import UniformTypeIdentifiers

@MainActor
final class EditorViewModel: ObservableObject {
    enum FPSPreset: String, CaseIterable, Identifiable {
        case fps23976 = "23.976"
        case fps24 = "24"
        case fps25 = "25"

        var id: String { rawValue }

        var value: Double {
            switch self {
            case .fps23976:
                return 23.976
            case .fps24:
                return 24
            case .fps25:
                return 25
            }
        }

        var displayName: String {
            rawValue
        }
    }

    enum TimecodeCaptureTarget: String {
        case start
        case end
    }

    private enum SeekIntent {
        case interactiveJump
        case loopJump
        case frameAccurate
    }

    enum LineChangeKind {
        case none
        case structure
        case multiLine
        case singleLineText(lineID: DialogueLine.ID)
        case singleLineMetadata(lineID: DialogueLine.ID)
    }

    struct ChronologicalStartIssue: Identifiable, Hashable {
        let previousLineID: DialogueLine.ID
        let lineID: DialogueLine.ID
        let previousLineIndex: Int
        let lineIndex: Int
        let previousStartTimecode: String
        let startTimecode: String
        let previousStartSeconds: Double
        let startSeconds: Double

        var id: String {
            "\(previousLineID.uuidString)-\(lineID.uuidString)"
        }
    }

    struct SpeakerStatistic: Identifiable, Hashable, Sendable {
        let speaker: String
        let entries: Int
        let wordCount: Int

        var replicaUnits: Double {
            Double(wordCount) / 8.0
        }

        var id: String {
            speaker
        }
    }

    struct DevInteractionMetrics {
        var clickToFocusMilliseconds: Double?
        var clickToFocusLabel: String = "-"
        var commitToLinesChangedMilliseconds: Double?
        var commitToLinesChangedLabel: String = "-"
        var linesChangedToCacheDoneMilliseconds: Double?
        var linesChangedToCacheDoneLabel: String = "-"
        var lastUpdated: Date?
    }

    struct BackspaceDebugTrace {
        struct TargetLine {
            let id: DialogueLine.ID
            let index: Int
            let summary: String
        }

        let timestamp: Date
        let watchedReplicaIndex: Int
        let watchedReplicaMatched: Bool
        let selectedLineID: DialogueLine.ID?
        let highlightedLineID: DialogueLine.ID?
        let selectionAnchorLineID: DialogueLine.ID?
        let selectedLineIDsInOrder: [DialogueLine.ID]
        let targetLines: [TargetLine]
        let beforeAllLineIDs: [DialogueLine.ID]
        let beforeLineSummaryByID: [DialogueLine.ID: String]
    }

    struct SelectionClickDebugTrace {
        let timestamp: Date
        let source: String
        let clickedLineID: DialogueLine.ID
        let clickedLineSummaryBefore: String
        let selectedLineIDBefore: DialogueLine.ID?
        let highlightedLineIDBefore: DialogueLine.ID?
        let selectionAnchorLineIDBefore: DialogueLine.ID?
        let selectedLineIDsBeforeInOrder: [DialogueLine.ID]
        let beforeLineSummaryByID: [DialogueLine.ID: String]
    }

    private struct DebugSelectionSnapshot {
        let selected: String
        let highlighted: String
        let anchor: String
        let selectedLineIDs: String
    }

    private struct DeletedLineChange {
        let line: DialogueLine
        let index: Int
    }

    private struct ClipboardLinePayload: Codable {
        let speaker: String
        let text: String
        let startTimecode: String
        let endTimecode: String
    }

    private struct LineUpdateChange {
        let before: DialogueLine
        let after: DialogueLine
    }

    private enum HistoryEntry {
        case snapshot([DialogueLine])
        case lineUpdate(change: LineUpdateChange)
        case insert(lines: [DialogueLine], index: Int)
        case delete(items: [DeletedLineChange])
        case move(lineID: DialogueLine.ID, fromIndex: Int, toIndex: Int)
    }

    private struct PlaybackSourceState {
        let videoAudioTrackID: CMPersistentTrackID?
        let externalAudioTrackID: CMPersistentTrackID?
    }

    private static let lightModeDefaultsKey = "performance_light_mode"
    private static let devModeDefaultsKey = "developer_mode_enabled"
    private static let hideTimecodeFramesDefaultsKey = "view_hide_timecode_frames"
    private static let hideEndTimecodeFieldDefaultsKey = "view_hide_end_timecode_field"
    private static let editModeTimecodePrefillDefaultsKey = "edit_mode_timecode_prefill_enabled"
    private static let timecodeModeDefaultsKey = "timecode_mode_enabled"
    private static let timecodeAutoAdvanceDefaultsKey = "timecode_mode_auto_advance_enabled"
    private static let timecodeAutoSwitchTargetDefaultsKey = "timecode_mode_auto_switch_target_enabled"
    private static let timecodeCaptureTargetDefaultsKey = "timecode_mode_capture_target"
    private static let playbackSeekStepDefaultsKey = "playback_seek_step_seconds"
    private static let replayPrerollEnabledDefaultsKey = "replay_preroll_enabled"
    private static let videoOffsetDefaultsKey = "video_offset_seconds"
    private static let muteLeftChannelDefaultsKey = "audio_mute_left_channel"
    private static let muteRightChannelDefaultsKey = "audio_mute_right_channel"
    private static let replicaTextFontSizeDefaultsKey = "replica_text_font_size_pt"
    private static let wordExportProfileDefaultsKey = "word_export_profile"
    private static let wordExportTimecodeSourceDefaultsKey = "word_export_timecode_source"
    private static let wordExportIncludeHoursDefaultsKey = "word_export_include_hours"
    private static let wordExportIncludeMinutesDefaultsKey = "word_export_include_minutes"
    private static let wordExportIncludeSecondsDefaultsKey = "word_export_include_seconds"
    private static let wordExportIncludeFramesDefaultsKey = "word_export_include_frames"
    private static let recentProjectsDefaultsKey = "recent_project_paths"
    private static let fixedFPS: Double = 25
    private static let defaultPlaybackSeekStepSeconds: Double = 1
    private static let defaultReplicaTextFontSize: Double = 13
    private static let minReplicaTextFontSize: Double = 13
    private static let maxReplicaTextFontSize: Double = 30
    private static let minPlaybackSeekStepSeconds: Double = 0.05
    private static let maxPlaybackSeekStepSeconds: Double = 60
    private static let minVideoOffsetSeconds: Double = -86_400
    private static let maxVideoOffsetSeconds: Double = 86_400
    private static let minSupportedFPS: Double = 1
    private static let maxSupportedFPS: Double = 240
    private static let fpsPresetSnapTolerance: Double = 0.05
    private static let maxRecentProjectsCount = 12
    private static let replicaClipboardType = NSPasteboard.PasteboardType("local.dubbingeditor.replicas.json")
    private static let backspaceDebugLogURL = URL(fileURLWithPath: "/tmp/dubbingeditor-backspace-debug.log")
    private static let backspaceDebugAltLogURL = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
        .appendingPathComponent("dubbingeditor-backspace-debug.log")
    private static let backspaceDebugDateFormatter: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()

    private let hourMinutePrefixRegex = try! NSRegularExpression(
        pattern: "^\\s*(\\d{2}):(\\d{2})(?::.*)?\\s*$"
    )

    @Published var lines: [DialogueLine] = []
    @Published var selectedLineID: DialogueLine.ID?
    @Published var selectedLineIDs: Set<DialogueLine.ID> = []
    @Published var highlightedLineID: DialogueLine.ID?
    @Published var editingLineID: DialogueLine.ID?
    @Published var isLoopEnabled = false
    @Published private(set) var isPlaybackActive = false
    @Published private(set) var fps: Double = EditorViewModel.fixedFPS
    @Published var videoURL: URL?
    @Published private(set) var sourceExternalAudioURL: URL?
    @Published var waveform: [Float] = []
    @Published var waveformLeft: [Float] = []
    @Published var waveformRight: [Float] = []
    @Published var externalWaveform: [Float] = []
    @Published private(set) var waveformLoadSource: WaveformLoadSource?
    @Published private(set) var externalWaveformLoadSource: WaveformLoadSource?
    @Published private(set) var waveformCacheExists = false
    @Published private(set) var waveformCacheSizeBytes: UInt64?
    @Published private(set) var externalWaveformCacheExists = false
    @Published private(set) var externalWaveformCacheSizeBytes: UInt64?
    @Published private(set) var lastVideoLoadDuration: TimeInterval?
    @Published private(set) var lastWaveformBuildDuration: TimeInterval?
    @Published var isBuildingWaveform = false
    @Published private(set) var isPreparingChannelDerivedAudio = false
    @Published var isImportingWord = false
    @Published private(set) var canUndo = false
    @Published private(set) var canRedo = false
    @Published var documentTitle = "Novy preklad"
    @Published var alertMessage: String?
    @Published private(set) var lastAutosaveDate: Date?
    @Published private(set) var pendingAutosaveRecovery: AutosaveSnapshot?
    @Published private(set) var currentProjectURL: URL?
    @Published private(set) var recentProjectURLs: [URL] = []
    @Published private(set) var pendingRestoreLineID: DialogueLine.ID?
    @Published var showValidationIssues = false
    @Published var showOnlyIssues = false
    @Published var validateMissingSpeaker = true
    @Published var validateMissingStartTC = true
    @Published var validateMissingEndTC = true
    @Published var validateInvalidTC = true
    @Published private(set) var speakerDatabase: [SpeakerStatistic] = []
    @Published private(set) var speakerColorOverridesByKey: [String: String] = [:]
    @Published private(set) var missingSpeakerCount = 0
    @Published private(set) var devInteractionMetrics = DevInteractionMetrics()
    @Published var isDevModeEnabled: Bool {
        didSet {
            guard isDevModeEnabled != oldValue else { return }
            UserDefaults.standard.set(isDevModeEnabled, forKey: Self.devModeDefaultsKey)
        }
    }
    @Published var isTimecodeModeEnabled: Bool {
        didSet {
            guard isTimecodeModeEnabled != oldValue else { return }
            UserDefaults.standard.set(isTimecodeModeEnabled, forKey: Self.timecodeModeDefaultsKey)
            if isTimecodeModeEnabled {
                finishEditing()
            }
        }
    }
    @Published var isTimecodeAutoAdvanceEnabled: Bool {
        didSet {
            guard isTimecodeAutoAdvanceEnabled != oldValue else { return }
            UserDefaults.standard.set(isTimecodeAutoAdvanceEnabled, forKey: Self.timecodeAutoAdvanceDefaultsKey)
        }
    }
    @Published var isTimecodeAutoSwitchTargetEnabled: Bool {
        didSet {
            guard isTimecodeAutoSwitchTargetEnabled != oldValue else { return }
            UserDefaults.standard.set(isTimecodeAutoSwitchTargetEnabled, forKey: Self.timecodeAutoSwitchTargetDefaultsKey)
        }
    }
    @Published var timecodeCaptureTarget: TimecodeCaptureTarget {
        didSet {
            guard timecodeCaptureTarget != oldValue else { return }
            UserDefaults.standard.set(timecodeCaptureTarget.rawValue, forKey: Self.timecodeCaptureTargetDefaultsKey)
        }
    }
    @Published var hideTimecodeFrames: Bool {
        didSet {
            guard hideTimecodeFrames != oldValue else { return }
            UserDefaults.standard.set(hideTimecodeFrames, forKey: Self.hideTimecodeFramesDefaultsKey)
        }
    }
    @Published var isEndTimecodeFieldHidden: Bool {
        didSet {
            guard isEndTimecodeFieldHidden != oldValue else { return }
            UserDefaults.standard.set(isEndTimecodeFieldHidden, forKey: Self.hideEndTimecodeFieldDefaultsKey)
        }
    }
    @Published var isEditModeTimecodePrefillEnabled: Bool {
        didSet {
            guard isEditModeTimecodePrefillEnabled != oldValue else { return }
            UserDefaults.standard.set(
                isEditModeTimecodePrefillEnabled,
                forKey: Self.editModeTimecodePrefillDefaultsKey
            )
        }
    }
    @Published var isLightModeEnabled: Bool {
        didSet {
            guard isLightModeEnabled != oldValue else { return }
            UserDefaults.standard.set(isLightModeEnabled, forKey: Self.lightModeDefaultsKey)
            applyVideoBufferingPreferences()
            if let videoURL, !isApplyingProjectSettings {
                queueWaveformBuild(for: videoURL, externalAudioURL: sourceExternalAudioURL)
            }
        }
    }
    @Published var playbackSeekStepSeconds: Double {
        didSet {
            let sanitized = Self.sanitizePlaybackSeekStepSeconds(playbackSeekStepSeconds)
            if sanitized != playbackSeekStepSeconds {
                playbackSeekStepSeconds = sanitized
                return
            }
            guard sanitized != oldValue else { return }
            UserDefaults.standard.set(sanitized, forKey: Self.playbackSeekStepDefaultsKey)
        }
    }
    @Published var isReplayPrerollEnabled: Bool {
        didSet {
            guard isReplayPrerollEnabled != oldValue else { return }
            UserDefaults.standard.set(isReplayPrerollEnabled, forKey: Self.replayPrerollEnabledDefaultsKey)
        }
    }
    @Published var videoOffsetSeconds: Double {
        didSet {
            let sanitized = Self.sanitizeVideoOffsetSeconds(videoOffsetSeconds)
            if sanitized != videoOffsetSeconds {
                videoOffsetSeconds = sanitized
                return
            }
            guard sanitized != oldValue else { return }
            UserDefaults.standard.set(sanitized, forKey: Self.videoOffsetDefaultsKey)
        }
    }
    @Published var isLeftChannelMuted: Bool {
        didSet {
            guard isLeftChannelMuted != oldValue else { return }
            UserDefaults.standard.set(isLeftChannelMuted, forKey: Self.muteLeftChannelDefaultsKey)
        }
    }
    @Published var isRightChannelMuted: Bool {
        didSet {
            guard isRightChannelMuted != oldValue else { return }
            UserDefaults.standard.set(isRightChannelMuted, forKey: Self.muteRightChannelDefaultsKey)
        }
    }
    @Published var isVideoAudioMuted = false {
        didSet {
            guard isVideoAudioMuted != oldValue else { return }
            applyCurrentAudioMix(source: "video_track_toggle")
        }
    }
    @Published var isExternalAudioMuted = false {
        didSet {
            guard isExternalAudioMuted != oldValue else { return }
            applyCurrentAudioMix(source: "external_track_toggle")
        }
    }
    @Published private(set) var hasVideoAudioTrack = false
    @Published private(set) var detectedAudioChannelCount: Int = 0
    @Published var replicaTextFontSize: Double {
        didSet {
            let sanitized = Self.sanitizeReplicaTextFontSize(replicaTextFontSize)
            if sanitized != replicaTextFontSize {
                replicaTextFontSize = sanitized
                return
            }
            guard sanitized != oldValue else { return }
            UserDefaults.standard.set(sanitized, forKey: Self.replicaTextFontSizeDefaultsKey)
        }
    }

    let player = AVPlayer()

    private let autosaveService = AutosaveService()
    private var importTask: Task<Void, Never>?
    private var autosaveTask: Task<Void, Never>?
    private var waveformTask: Task<Void, Never>?
    private var projectIOTask: Task<Void, Never>?
    private var activeProjectOperationID: UUID?
    private var isLoopSeekInFlight = false
    private var isApplyingHistoryState = false
    private var undoStack: [HistoryEntry] = []
    private var redoStack: [HistoryEntry] = []
    private var lastCommittedLines: [DialogueLine] = []
    private var lastObservedLines: [DialogueLine] = []
    private var pendingBaselineLines: [DialogueLine]?
    private var pendingExplicitHistoryEntry: HistoryEntry?
    private var autosaveRevision: UInt64 = 0
    private var lastAutosavedRevision: UInt64 = 0
    private var speakerDatabaseNeedsRefresh = false
    private var speakerDatabaseRebuildTask: Task<Void, Never>?
    private var speakerDatabaseRebuildRevision: UInt64 = 0
    private var didCheckAutosaveRecovery = false
    private var playerItemStatusObservation: NSKeyValueObservation?
    private var playerTimeControlObservation: NSKeyValueObservation?
    private var audioMixTask: Task<Void, Never>?
    private var audioChannelDetectionTask: Task<Void, Never>?
    private var videoFPSDetectionTask: Task<Void, Never>?
    private var playbackSourceTask: Task<Void, Never>?
    private var videoLoadStartedAt: Date?
    private var sourceWordURL: URL?
    private var playbackSourceState: PlaybackSourceState?
    private var lineIndexByID: [DialogueLine.ID: Int] = [:]
    private var selectionAnchorLineID: DialogueLine.ID?
    private var pendingSelectionSeekTask: Task<Void, Never>?
    private var pendingSelectionSeekLineID: DialogueLine.ID?
    private var isApplyingProjectSettings = false
    private var pendingPlaybackRestoreTimelineSeconds: Double?
    private var pendingPlaybackResumeAfterRestore = false
    private var activeSeekGeneration: UInt64 = 0
    private var completedSeekGeneration: UInt64 = 0
    private var resumePlaybackAfterSeekGeneration: UInt64?
    private let historyLimit = 30
    private let autosaveDelayNanoseconds: UInt64 = 1_100_000_000
    private let autosaveDelayWhileEditingNanoseconds: UInt64 = 1_700_000_000
    private let autosaveDelayForStructureNanoseconds: UInt64 = 1_900_000_000
    private let speakerDatabaseRebuildDelayNanoseconds: UInt64 = 180_000_000
    private let pointerSelectionSeekDebounceNanoseconds: UInt64 = 170_000_000
    private var lastLineChangeKind: LineChangeKind = .none

    init() {
        fps = Self.fixedFPS
        player.automaticallyWaitsToMinimizeStalling = false
        player.actionAtItemEnd = .pause
        isDevModeEnabled = UserDefaults.standard.bool(forKey: Self.devModeDefaultsKey)
        isTimecodeModeEnabled = false
        UserDefaults.standard.set(false, forKey: Self.timecodeModeDefaultsKey)
        if UserDefaults.standard.object(forKey: Self.timecodeAutoAdvanceDefaultsKey) == nil {
            isTimecodeAutoAdvanceEnabled = true
        } else {
            isTimecodeAutoAdvanceEnabled = UserDefaults.standard.bool(forKey: Self.timecodeAutoAdvanceDefaultsKey)
        }
        if UserDefaults.standard.object(forKey: Self.timecodeAutoSwitchTargetDefaultsKey) == nil {
            isTimecodeAutoSwitchTargetEnabled = false
        } else {
            isTimecodeAutoSwitchTargetEnabled = UserDefaults.standard.bool(forKey: Self.timecodeAutoSwitchTargetDefaultsKey)
        }
        if
            let rawTarget = UserDefaults.standard.string(forKey: Self.timecodeCaptureTargetDefaultsKey),
            let parsedTarget = TimecodeCaptureTarget(rawValue: rawTarget)
        {
            timecodeCaptureTarget = parsedTarget
        } else {
            timecodeCaptureTarget = .start
        }
        if UserDefaults.standard.object(forKey: Self.hideTimecodeFramesDefaultsKey) == nil {
            hideTimecodeFrames = true
        } else {
            hideTimecodeFrames = UserDefaults.standard.bool(forKey: Self.hideTimecodeFramesDefaultsKey)
        }
        if UserDefaults.standard.object(forKey: Self.hideEndTimecodeFieldDefaultsKey) == nil {
            isEndTimecodeFieldHidden = false
        } else {
            isEndTimecodeFieldHidden = UserDefaults.standard.bool(forKey: Self.hideEndTimecodeFieldDefaultsKey)
        }
        if UserDefaults.standard.object(forKey: Self.editModeTimecodePrefillDefaultsKey) == nil {
            isEditModeTimecodePrefillEnabled = false
        } else {
            isEditModeTimecodePrefillEnabled = UserDefaults.standard.bool(
                forKey: Self.editModeTimecodePrefillDefaultsKey
            )
        }
        isLightModeEnabled = UserDefaults.standard.bool(forKey: Self.lightModeDefaultsKey)
        let storedStep = UserDefaults.standard.double(forKey: Self.playbackSeekStepDefaultsKey)
        let initialStep = storedStep > 0 ? storedStep : Self.defaultPlaybackSeekStepSeconds
        playbackSeekStepSeconds = Self.sanitizePlaybackSeekStepSeconds(initialStep)
        if UserDefaults.standard.object(forKey: Self.replayPrerollEnabledDefaultsKey) == nil {
            isReplayPrerollEnabled = true
        } else {
            isReplayPrerollEnabled = UserDefaults.standard.bool(forKey: Self.replayPrerollEnabledDefaultsKey)
        }
        let storedVideoOffset = UserDefaults.standard.double(forKey: Self.videoOffsetDefaultsKey)
        videoOffsetSeconds = Self.sanitizeVideoOffsetSeconds(storedVideoOffset)
        isLeftChannelMuted = UserDefaults.standard.bool(forKey: Self.muteLeftChannelDefaultsKey)
        isRightChannelMuted = UserDefaults.standard.bool(forKey: Self.muteRightChannelDefaultsKey)
        if UserDefaults.standard.object(forKey: Self.replicaTextFontSizeDefaultsKey) == nil {
            replicaTextFontSize = Self.defaultReplicaTextFontSize
        } else {
            let storedFontSize = UserDefaults.standard.double(forKey: Self.replicaTextFontSizeDefaultsKey)
            replicaTextFontSize = Self.sanitizeReplicaTextFontSize(storedFontSize)
        }
        loadRecentProjectURLs()
        applyVideoBufferingPreferences()
        installPlayerStateObservation()
    }

    deinit {
        importTask?.cancel()
        pendingSelectionSeekTask?.cancel()
        speakerDatabaseRebuildTask?.cancel()
        audioMixTask?.cancel()
        audioChannelDetectionTask?.cancel()
        videoFPSDetectionTask?.cancel()
        playbackSourceTask?.cancel()
        playerItemStatusObservation?.invalidate()
        playerTimeControlObservation?.invalidate()
    }

    func importWord(from url: URL) {
        importTask?.cancel()
        isImportingWord = true
        alertMessage = nil
        let importFPS = Self.sanitizedFPS(fps)

        importTask = Task.detached(priority: .userInitiated) { [url] in
            do {
                let result = try WordImportService().importLines(sourceURL: url, fps: importFPS)
                try Task.checkCancellation()

                await MainActor.run { [weak self] in
                    guard let self else { return }
                    self.isImportingWord = false
                    self.lines = result.lines
                    self.applySpeakerColorOverrides(nil)
                    self.rebuildSpeakerDatabase(from: result.lines)
                    self.documentTitle = url.deletingPathExtension().lastPathComponent
                    self.sourceWordURL = url
                    self.currentProjectURL = nil

                    if let first = result.lines.first {
                        self.selectedLineID = first.id
                        self.selectedLineIDs = [first.id]
                        self.selectionAnchorLineID = first.id
                        self.highlightedLineID = first.id
                    } else {
                        self.selectedLineID = nil
                        self.selectedLineIDs = []
                        self.selectionAnchorLineID = nil
                        self.highlightedLineID = nil
                    }

                    self.pendingRestoreLineID = self.selectedLineID
                    self.editingLineID = nil
                    self.isLoopEnabled = false
                    self.resetHistory(with: self.lines)
                    self.markProjectDirty()
                    self.scheduleAutosave()

                    let convertedPrefix = result.convertedFromLegacyDoc
                        ? String(localized: "alert.doc_converted_prefix", bundle: .appBundle)
                        : ""
                    let skippedInfo = result.skippedRowCount > 0
                        ? String(format: String(localized: "alert.import_skipped_rows", bundle: .appBundle), result.skippedRowCount)
                        : ""
                    self.alertMessage = convertedPrefix + String(format: String(localized: "alert.import_done", bundle: .appBundle), result.detectedFormat.displayName, result.lines.count) + skippedInfo
                }
            } catch is CancellationError {
                await MainActor.run { [weak self] in
                    self?.isImportingWord = false
                }
            } catch {
                await MainActor.run { [weak self] in
                    guard let self else { return }
                    self.isImportingWord = false
                    self.alertMessage = String(format: String(localized: "alert.import_word_failed", bundle: .appBundle), error.localizedDescription)
                }
            }
        }
    }

    func importVideo(from url: URL) {
        loadVideo(from: url)
        currentProjectURL = nil
        markProjectDirty()
        scheduleAutosave()
    }

    func importExternalAudio(from url: URL) {
        guard let videoURL else {
            alertMessage = String(localized: "alert.video_required", bundle: .appBundle)
            return
        }

        rebuildPlaybackSource(
            videoURL: videoURL,
            externalAudioURL: url,
            preserveCurrentPlaybackPosition: true,
            queueWaveformRebuild: true,
            fallbackWithoutExternalAudio: false,
            alertPrefix: String(localized: "alert.external_audio_import_failed", bundle: .appBundle)
        )
        currentProjectURL = nil
        markProjectDirty()
        scheduleAutosave()
    }

    var fpsPresetSelection: FPSPreset {
        Self.closestFPSPreset(for: fps) ?? .fps25
    }

    var fpsDisplayLabel: String {
        if let preset = Self.closestFPSPreset(for: fps) {
            return preset.displayName
        }
        return Self.formattedFPSValue(fps)
    }

    func setFPSPreset(_ preset: FPSPreset) {
        let sanitized = Self.sanitizedFPS(preset.value)
        guard abs(fps - sanitized) > 0.000_001 else { return }
        fps = sanitized
        markProjectDirty()
        scheduleAutosave()
    }

    func checkAutosaveRecoveryIfNeeded() {
        guard !didCheckAutosaveRecovery else { return }
        didCheckAutosaveRecovery = true

        Task { [weak self] in
            guard let self else { return }
            do {
                let crashedLastSession = try await autosaveService.startSession()
                guard crashedLastSession else {
                    return
                }
                guard let snapshot = try await autosaveService.loadLatestSnapshot() else {
                    return
                }
                guard !snapshot.lines.isEmpty else {
                    return
                }
                self.pendingAutosaveRecovery = snapshot
            } catch {
                self.alertMessage = String(format: String(localized: "alert.autosave_load_failed", bundle: .appBundle), error.localizedDescription)
            }
        }
    }

    func restorePendingAutosave() {
        guard let snapshot = pendingAutosaveRecovery else {
            return
        }

        pendingAutosaveRecovery = nil
        apply(snapshot: snapshot)
    }

    func discardPendingAutosave() {
        pendingAutosaveRecovery = nil
        Task {
            try? await autosaveService.discardLatestSnapshot()
        }
    }

    func notifyMetadataDidChange() {
        markProjectDirty()
        scheduleAutosave()
    }

    func forceAutosaveNow() {
        scheduleAutosave(immediate: true)
    }

    func handleAppWillTerminate() {
        autosaveTask?.cancel()
        waveformTask?.cancel()
        projectIOTask?.cancel()
        speakerDatabaseRebuildTask?.cancel()
        Task { [weak self] in
            guard let self else { return }
            await performAutosaveIfNeeded()
            try? await autosaveService.endSession()
        }
    }

    func pendingAutosaveSummary() -> String {
        guard let snapshot = pendingAutosaveRecovery else {
            return ""
        }
        return "Dokument: \(snapshot.documentTitle) | Repliky: \(snapshot.lines.count)"
    }

    private func loadVideo(from url: URL) {
        rebuildPlaybackSource(
            videoURL: url,
            externalAudioURL: nil,
            videoAudioVariant: .stereo,
            preserveCurrentPlaybackPosition: false,
            queueWaveformRebuild: true,
            fallbackWithoutExternalAudio: false,
            alertPrefix: String(localized: "alert.video_import_failed", bundle: .appBundle)
        )
    }

    private func detectAudioChannels(for asset: AVAsset) {
        audioChannelDetectionTask?.cancel()
        audioChannelDetectionTask = Task { [weak self] in
            guard let self else { return }
            let channelCount = await StereoChannelMuteService.audioChannelCount(for: asset)
            guard !Task.isCancelled else { return }
            self.detectedAudioChannelCount = channelCount
        }
    }

    private func detectVideoFPS(for asset: AVAsset) {
        videoFPSDetectionTask?.cancel()
        videoFPSDetectionTask = Task { [weak self] in
            guard let self else { return }
            let detected = await Self.resolveVideoFPS(from: asset)
            guard !Task.isCancelled else { return }
            guard let detected else { return }
            self.fps = Self.normalizedDetectedFPS(detected)
        }
    }

    func playbackDebugSnapshot(
        itemOverride: AVPlayerItem? = nil,
        currentSecondsOverride: Double? = nil,
        audioMixPlanOverride: PlaybackCompositionService.AudioMixPlan? = nil
    ) -> PlaybackDebugSnapshot {
        let item = itemOverride ?? player.currentItem
        let plan = audioMixPlanOverride ?? currentAudioMixPlanForDebug()
        return PlaybackDebugSnapshot(
            item: playbackDebugItemIdentifier(item),
            timeControlStatus: playbackDebugTimeControlStatus(player.timeControlStatus),
            currentSeconds: formatPlaybackSecondsForDebug(currentSecondsOverride ?? player.currentTime().seconds),
            audioMix: item?.audioMix == nil ? "nil" : "nonNil",
            videoMuted: playbackDebugBoolean(isVideoAudioMuted),
            externalMuted: playbackDebugBoolean(isExternalAudioMuted),
            muteL: playbackDebugBoolean(isLeftChannelMuted),
            muteR: playbackDebugBoolean(isRightChannelMuted),
            hasExternalAudio: playbackDebugBoolean(playbackSourceState?.externalAudioTrackID != nil),
            tapActive: playbackDebugBoolean(plan?.applyStereoChannelMuteToVideoTrack == true),
            tapForcedOff: playbackDebugBoolean(plan?.tapForcedOff == true),
            videoTrackID: formatTrackIDForDebug(playbackSourceState?.videoAudioTrackID),
            externalTrackID: formatTrackIDForDebug(playbackSourceState?.externalAudioTrackID)
        )
    }

    func logPlaybackDebugEvent(
        _ event: String,
        source: String,
        seekGeneration: UInt64? = nil,
        itemOverride: AVPlayerItem? = nil,
        currentSecondsOverride: Double? = nil,
        audioMixPlanOverride: PlaybackCompositionService.AudioMixPlan? = nil,
        extraFields: [(String, String?)] = []
    ) {
        PlaybackDebugLogger.append(
            enabled: isDevModeEnabled,
            event: event,
            source: source,
            seekGeneration: seekGeneration ?? currentSeekGenerationForDebug(),
            snapshot: playbackDebugSnapshot(
                itemOverride: itemOverride,
                currentSecondsOverride: currentSecondsOverride,
                audioMixPlanOverride: audioMixPlanOverride
            ),
            extraFields: extraFields
        )
    }

    nonisolated func playbackDebugSnapshotForUI(
        itemOverride: AVPlayerItem? = nil,
        currentSecondsOverride: Double? = nil
    ) -> PlaybackDebugSnapshot {
        MainActor.assumeIsolated {
            playbackDebugSnapshot(
                itemOverride: itemOverride,
                currentSecondsOverride: currentSecondsOverride
            )
        }
    }

    nonisolated func logPlaybackDebugEventFromUI(
        _ event: String,
        source: String,
        seekGeneration: UInt64? = nil,
        itemOverride: AVPlayerItem? = nil,
        currentSecondsOverride: Double? = nil,
        extraFields: [(String, String?)] = []
    ) {
        MainActor.assumeIsolated {
            logPlaybackDebugEvent(
                event,
                source: source,
                seekGeneration: seekGeneration,
                itemOverride: itemOverride,
                currentSecondsOverride: currentSecondsOverride,
                extraFields: extraFields
            )
        }
    }

    private func currentAudioMixPlanForDebug() -> PlaybackCompositionService.AudioMixPlan? {
        guard let playbackSourceState else { return nil }
        return PlaybackCompositionService.makeAudioMixPlan(
            videoAudioTrackID: playbackSourceState.videoAudioTrackID,
            externalAudioTrackID: playbackSourceState.externalAudioTrackID,
            isVideoAudioMuted: isVideoAudioMuted,
            isExternalAudioMuted: isExternalAudioMuted,
            muteLeftChannel: isLeftChannelMuted,
            muteRightChannel: isRightChannelMuted
        )
    }

    private func currentSeekGenerationForDebug() -> UInt64? {
        activeSeekGeneration == 0 ? nil : activeSeekGeneration
    }

    private func formatPlaybackSecondsForDebug(_ seconds: Double?) -> String? {
        guard let seconds, seconds.isFinite else { return nil }
        return String(format: "%.3f", seconds)
    }

    private func formatTrackIDForDebug(_ trackID: CMPersistentTrackID?) -> String? {
        guard let trackID, trackID != kCMPersistentTrackID_Invalid else { return nil }
        return String(trackID)
    }

    private func playbackDebugBoolean(_ value: Bool) -> String {
        value ? "true" : "false"
    }

    private func playbackDebugItemIdentifier(_ item: AVPlayerItem?) -> String? {
        guard let item else { return nil }
        return String(describing: Unmanaged.passUnretained(item).toOpaque())
    }

    private func playbackDebugTimeControlStatus(_ status: AVPlayer.TimeControlStatus) -> String {
        switch status {
        case .paused:
            return "paused"
        case .waitingToPlayAtSpecifiedRate:
            return "waiting"
        case .playing:
            return "playing"
        @unknown default:
            return "unknown"
        }
    }

    private func playbackDebugItemStatus(_ status: AVPlayerItem.Status) -> String {
        switch status {
        case .unknown:
            return "unknown"
        case .readyToPlay:
            return "readyToPlay"
        case .failed:
            return "failed"
        @unknown default:
            return "unknown_default"
        }
    }

    private func applyCurrentAudioMix(
        to itemOverride: AVPlayerItem? = nil,
        source: String = "audio_mix_refresh"
    ) {
        audioMixTask?.cancel()

        let item = itemOverride ?? player.currentItem
        guard let item else {
            logPlaybackDebugEvent(
                "AUDIO_MIX_PLAN",
                source: source,
                itemOverride: itemOverride,
                extraFields: [("result", "no_item")]
            )
            return
        }

        guard let plan = currentAudioMixPlanForDebug() else {
            logPlaybackDebugEvent(
                "AUDIO_MIX_PLAN",
                source: source,
                itemOverride: item,
                extraFields: [
                    ("result", "no_playback_source"),
                    ("requiresAudioMix", "false"),
                    ("muteVideoTrack", "false"),
                    ("muteExternalTrack", "false"),
                    ("stereoTap", "false"),
                    ("tapForcedOff", "false")
                ]
            )
            logPlaybackDebugEvent("AUDIO_MIX_APPLY_BEGIN", source: source, itemOverride: item)
            item.audioMix = nil
            logPlaybackDebugEvent(
                "AUDIO_MIX_APPLY_END",
                source: source,
                itemOverride: item,
                extraFields: [("result", "cleared_no_playback_source")]
            )
            return
        }

        logPlaybackDebugEvent(
            "AUDIO_MIX_PLAN",
            source: source,
            itemOverride: item,
            audioMixPlanOverride: plan,
            extraFields: [
                ("requiresAudioMix", playbackDebugBoolean(plan.requiresAudioMix)),
                ("muteVideoTrack", playbackDebugBoolean(plan.muteVideoTrack)),
                ("muteExternalTrack", playbackDebugBoolean(plan.muteExternalTrack)),
                ("stereoTap", playbackDebugBoolean(plan.applyStereoChannelMuteToVideoTrack)),
                ("tapForcedOff", playbackDebugBoolean(plan.tapForcedOff))
            ]
        )
        logPlaybackDebugEvent(
            "AUDIO_MIX_APPLY_BEGIN",
            source: source,
            itemOverride: item,
            audioMixPlanOverride: plan
        )
        guard plan.requiresAudioMix else {
            item.audioMix = nil
            logPlaybackDebugEvent(
                "AUDIO_MIX_APPLY_END",
                source: source,
                itemOverride: item,
                audioMixPlanOverride: plan,
                extraFields: [("result", "cleared_no_mix")]
            )
            return
        }

        let expectedItem = item
        guard let playbackSourceState else { return }
        let videoAudioTrackID = playbackSourceState.videoAudioTrackID
        let externalAudioTrackID = playbackSourceState.externalAudioTrackID
        let videoTrackMuted = self.isVideoAudioMuted
        let externalTrackMuted = self.isExternalAudioMuted
        audioMixTask = Task { [weak self] in
            guard let self else { return }
            let mix = await PlaybackCompositionService.buildAudioMix(
                for: expectedItem.asset,
                videoAudioTrackID: videoAudioTrackID,
                externalAudioTrackID: externalAudioTrackID,
                isVideoAudioMuted: videoTrackMuted,
                isExternalAudioMuted: externalTrackMuted,
                muteLeftChannel: self.isLeftChannelMuted,
                muteRightChannel: self.isRightChannelMuted
            )
            guard !Task.isCancelled else {
                self.logPlaybackDebugEvent(
                    "AUDIO_MIX_APPLY_END",
                    source: source,
                    itemOverride: expectedItem,
                    audioMixPlanOverride: plan,
                    extraFields: [("result", "cancelled")]
                )
                return
            }
            guard expectedItem === (itemOverride ?? self.player.currentItem) else {
                self.logPlaybackDebugEvent(
                    "AUDIO_MIX_APPLY_END",
                    source: source,
                    itemOverride: expectedItem,
                    audioMixPlanOverride: plan,
                    extraFields: [("result", "skipped_item_mismatch")]
                )
                return
            }
            expectedItem.audioMix = mix
            self.logPlaybackDebugEvent(
                "AUDIO_MIX_APPLY_END",
                source: source,
                itemOverride: expectedItem,
                audioMixPlanOverride: plan,
                extraFields: [("result", mix == nil ? "applied_nil" : "applied_nonNil")]
            )
        }
    }

    private func rebuildPlaybackSource(
        videoURL: URL,
        externalAudioURL: URL?,
        videoAudioVariant: VideoAudioChannelVariant? = nil,
        preserveCurrentPlaybackPosition: Bool,
        queueWaveformRebuild: Bool,
        fallbackWithoutExternalAudio: Bool,
        alertPrefix: String,
        tracksChannelPreparationState: Bool = false,
        onFailure: (@MainActor () -> Void)? = nil
    ) {
        playbackSourceTask?.cancel()
        audioMixTask?.cancel()
        playerItemStatusObservation?.invalidate()
        playerItemStatusObservation = nil
        videoLoadStartedAt = Date()
        lastVideoLoadDuration = nil

        let restoreTimelineSeconds: Double?
        if preserveCurrentPlaybackPosition {
            restoreTimelineSeconds = currentTimelinePlaybackSeconds()
        } else {
            restoreTimelineSeconds = pendingPlaybackRestoreTimelineSeconds
        }
        let resumePlaybackAfterRestore = preserveCurrentPlaybackPosition && player.timeControlStatus == .playing
        let requestedVideoAudioVariant = videoAudioVariant ?? currentRequestedVideoAudioVariant()
        isPreparingChannelDerivedAudio = tracksChannelPreparationState && requestedVideoAudioVariant.requiresDerivedStem

        playbackSourceTask = Task { [weak self] in
            guard let self else { return }
            defer {
                Task { @MainActor [weak self] in
                    self?.isPreparingChannelDerivedAudio = false
                }
            }

            do {
                let result = try await self.buildPlaybackSourceWithFallbackIfNeeded(
                    videoURL: videoURL,
                    externalAudioURL: externalAudioURL,
                    videoAudioVariant: requestedVideoAudioVariant,
                    fallbackWithoutExternalAudio: fallbackWithoutExternalAudio
                )
                guard !Task.isCancelled else { return }
                await MainActor.run { [weak self] in
                    guard let self else { return }
                    self.commitPlaybackSource(
                        buildResult: result,
                        videoURL: videoURL,
                        externalAudioURL: result.externalAudioTrackID == nil ? nil : externalAudioURL,
                        restoreTimelineSeconds: restoreTimelineSeconds,
                        resumePlaybackAfterRestore: resumePlaybackAfterRestore,
                        queueWaveformRebuild: queueWaveformRebuild
                    )
                }
            } catch is CancellationError {
                return
            } catch {
                await MainActor.run { [weak self] in
                    guard let self else { return }
                    self.videoLoadStartedAt = nil
                    self.pendingPlaybackResumeAfterRestore = false
                    onFailure?()
                    self.alertMessage = "\(alertPrefix): \((error as? LocalizedError)?.errorDescription ?? error.localizedDescription)"
                }
            }
        }
    }

    private func buildPlaybackSourceWithFallbackIfNeeded(
        videoURL: URL,
        externalAudioURL: URL?,
        videoAudioVariant: VideoAudioChannelVariant,
        fallbackWithoutExternalAudio: Bool
    ) async throws -> PlaybackCompositionService.BuildResult {
        do {
            return try await PlaybackCompositionService.buildPlayerItem(
                videoURL: videoURL,
                videoAudioVariant: videoAudioVariant,
                externalAudioURL: externalAudioURL
            )
        } catch {
            guard fallbackWithoutExternalAudio, externalAudioURL != nil else {
                throw error
            }
            await MainActor.run { [weak self] in
                self?.alertMessage = String(localized: "alert.external_audio_fallback", bundle: .appBundle)
            }
            return try await PlaybackCompositionService.buildPlayerItem(
                videoURL: videoURL,
                videoAudioVariant: videoAudioVariant,
                externalAudioURL: nil
            )
        }
    }

    private func commitPlaybackSource(
        buildResult: PlaybackCompositionService.BuildResult,
        videoURL: URL,
        externalAudioURL: URL?,
        restoreTimelineSeconds: Double?,
        resumePlaybackAfterRestore: Bool,
        queueWaveformRebuild: Bool
    ) {
        let item = AVPlayerItem(asset: buildResult.composition)
        configurePlayerItemForSmoothPlayback(item)
        playerItemStatusObservation = item.observe(\.status, options: [.initial, .new]) { [weak self] observedItem, _ in
            Task { @MainActor in
                guard let self else { return }
                self.handleVideoItemStatusChange(observedItem)
            }
        }

        self.videoURL = videoURL
        sourceExternalAudioURL = externalAudioURL
        playbackSourceState = PlaybackSourceState(
            videoAudioTrackID: buildResult.videoAudioTrackID,
            externalAudioTrackID: buildResult.externalAudioTrackID
        )
        hasVideoAudioTrack = buildResult.sourceHasVideoAudioTrack
        pendingPlaybackRestoreTimelineSeconds = restoreTimelineSeconds
        pendingPlaybackResumeAfterRestore = resumePlaybackAfterRestore
        resetSeekPlaybackState()

        logPlaybackDebugEvent(
            "PLAYER_ITEM_REPLACED",
            source: "playback_source_commit",
            itemOverride: item
        )
        player.replaceCurrentItem(with: item)
        applyCurrentAudioMix(to: item, source: "playback_source_commit")
        detectVideoFPS(for: buildResult.videoAsset)
        detectAudioChannels(for: buildResult.videoAsset)

        if queueWaveformRebuild {
            waveformLoadSource = nil
            externalWaveformLoadSource = nil
            lastWaveformBuildDuration = nil
            refreshWaveformCacheMetadata(for: videoURL, externalAudioURL: externalAudioURL)
            queueWaveformBuild(for: videoURL, externalAudioURL: externalAudioURL)
        }
    }

    private func resetPlaybackState(alertMessage message: String? = nil) {
        playbackSourceTask?.cancel()
        waveformTask?.cancel()
        audioMixTask?.cancel()
        audioChannelDetectionTask?.cancel()
        videoFPSDetectionTask?.cancel()
        playerItemStatusObservation?.invalidate()
        playerItemStatusObservation = nil
        isPreparingChannelDerivedAudio = false
        videoLoadStartedAt = nil
        pendingPlaybackRestoreTimelineSeconds = nil
        pendingPlaybackResumeAfterRestore = false
        resetSeekPlaybackState()
        videoURL = nil
        sourceExternalAudioURL = nil
        playbackSourceState = nil
        hasVideoAudioTrack = false
        detectedAudioChannelCount = 0
        waveform = []
        waveformLeft = []
        waveformRight = []
        externalWaveform = []
        waveformLoadSource = nil
        externalWaveformLoadSource = nil
        lastVideoLoadDuration = nil
        lastWaveformBuildDuration = nil
        refreshWaveformCacheMetadata(for: nil, externalAudioURL: nil)
        logPlaybackDebugEvent(
            "PLAYER_ITEM_REPLACED",
            source: "reset",
            itemOverride: nil,
            extraFields: [("result", "cleared")]
        )
        player.replaceCurrentItem(with: nil)
        if let message {
            alertMessage = message
        }
    }

    func waveformSourceLabel() -> String? {
        waveformSourceLabel(for: waveformLoadSource)
    }

    func externalWaveformSourceLabel() -> String? {
        waveformSourceLabel(for: externalWaveformLoadSource)
    }

    var hasAnyWaveformCache: Bool {
        waveformCacheExists || externalWaveformCacheExists
    }

    private func waveformSourceLabel(for source: WaveformLoadSource?) -> String? {
        guard let source else { return nil }
        switch source {
        case .cache:
            return "cache"
        case .generated:
            return "nove vypocitana"
        }
    }

    func rebuildWaveformForCurrentVideo() {
        guard let videoURL else {
            alertMessage = String(localized: "alert.video_required", bundle: .appBundle)
            return
        }
        queueWaveformBuild(for: videoURL, externalAudioURL: sourceExternalAudioURL, forceRebuild: true)
    }

    func deleteWaveformCacheForCurrentVideo() {
        guard let videoURL else {
            alertMessage = String(localized: "alert.video_required", bundle: .appBundle)
            return
        }

        do {
            _ = try WaveformService.deleteCache(for: videoURL)
            if let sourceExternalAudioURL {
                _ = try? WaveformService.deleteCache(for: sourceExternalAudioURL)
            }
            refreshWaveformCacheMetadata(for: videoURL, externalAudioURL: sourceExternalAudioURL)
        } catch {
            alertMessage = String(format: String(localized: "alert.waveform_cache_delete_failed", bundle: .appBundle), error.localizedDescription)
        }
    }

    func selectLine(
        _ line: DialogueLine,
        extendSelection: Bool = false,
        debounceSeek: Bool = false,
        seekOnSelection: Bool = true
    ) {
        if editingLineID != nil, editingLineID != line.id {
            flushPendingHistory()
        }
        if extendSelection {
            cancelPendingSelectionSeek()
            extendSelectionRange(to: line)
        } else {
            let wasSamePrimarySelection = selectedLineID == line.id && highlightedLineID == line.id
            selectedLineID = line.id
            selectedLineIDs = [line.id]
            selectionAnchorLineID = line.id
            highlightedLineID = line.id
            if editingLineID != line.id {
                editingLineID = nil
            }
            guard !wasSamePrimarySelection else {
                return
            }

            guard seekOnSelection else {
                cancelPendingSelectionSeek()
                return
            }

            guard let seconds = TimecodeService.seconds(from: line.startTimecode, fps: fps) else {
                cancelPendingSelectionSeek()
                return
            }

            if debounceSeek {
                scheduleSelectionSeek(seconds: seconds, for: line.id)
            } else {
                cancelPendingSelectionSeek()
                // Defer seek so row selection/edit focus is reflected immediately in UI.
                DispatchQueue.main.async { [weak self] in
                    self?.seekToTimeline(seconds: seconds, source: "selection_seek")
                }
            }
        }
    }

    func activateLineByDoubleClick(_ line: DialogueLine) {
        cancelPendingSelectionSeek()
        if !isLineStrictlySingleSelected(line.id) {
            selectLine(line, seekOnSelection: false)
        }
        guard !isTimecodeModeEnabled else { return }
        editingLineID = line.id
    }

    func beginBackspaceDebugTrace(watchedReplicaIndex: Int = 8) -> BackspaceDebugTrace? {
        guard watchedReplicaIndex > 0 else { return nil }
        guard !lines.isEmpty else { return nil }

        let selectedInOrder = lines.compactMap { line in
            selectedLineIDs.contains(line.id) ? line.id : nil
        }
        let targetIndices = orderedSelectedLineIndices()
        let targetLines = targetIndices.map { idx in
            let line = lines[idx]
            return BackspaceDebugTrace.TargetLine(id: line.id, index: line.index, summary: debugLineSummary(line))
        }
        let watchedReplicaMatched = targetLines.contains { $0.index == watchedReplicaIndex }

        var summaryByID: [DialogueLine.ID: String] = [:]
        summaryByID.reserveCapacity(lines.count)
        for line in lines {
            summaryByID[line.id] = debugLineSummary(line)
        }

        return BackspaceDebugTrace(
            timestamp: Date(),
            watchedReplicaIndex: watchedReplicaIndex,
            watchedReplicaMatched: watchedReplicaMatched,
            selectedLineID: selectedLineID,
            highlightedLineID: highlightedLineID,
            selectionAnchorLineID: selectionAnchorLineID,
            selectedLineIDsInOrder: selectedInOrder,
            targetLines: targetLines,
            beforeAllLineIDs: lines.map(\.id),
            beforeLineSummaryByID: summaryByID
        )
    }

    func noteBackspaceKeyDownDebug(textInputFocused: Bool, editingLineID: DialogueLine.ID?) {
        let summaryByID = currentLineSummaryByID()
        let selectedInOrder = lines.compactMap { line in
            selectedLineIDs.contains(line.id) ? line.id : nil
        }
        let reportLines: [String] = [
            "=== BACKSPACE KEYDOWN ===",
            "timestamp=\(Self.backspaceDebugDateFormatter.string(from: Date()))",
            "textInputFocused=\(textInputFocused)",
            "editingLine=\(debugSummary(for: editingLineID, using: summaryByID))",
            "selected=\(debugSummary(for: selectedLineID, using: summaryByID))",
            "highlighted=\(debugSummary(for: highlightedLineID, using: summaryByID))",
            "anchor=\(debugSummary(for: selectionAnchorLineID, using: summaryByID))",
            "selectedLineIDs=\(selectedInOrder.map { debugSummary(for: $0, using: summaryByID) }.joined(separator: " | "))"
        ]
        let report = reportLines.joined(separator: "\n")
        appendBackspaceDebugReport(report)
        print(report)
    }

    func beginSelectionClickDebugTrace(clickedLineID: DialogueLine.ID, source: String) -> SelectionClickDebugTrace {
        let summaryByID = currentLineSummaryByID()
        let selectedInOrder = lines.compactMap { line in
            selectedLineIDs.contains(line.id) ? line.id : nil
        }
        return SelectionClickDebugTrace(
            timestamp: Date(),
            source: source,
            clickedLineID: clickedLineID,
            clickedLineSummaryBefore: debugSummary(for: clickedLineID, using: summaryByID),
            selectedLineIDBefore: selectedLineID,
            highlightedLineIDBefore: highlightedLineID,
            selectionAnchorLineIDBefore: selectionAnchorLineID,
            selectedLineIDsBeforeInOrder: selectedInOrder,
            beforeLineSummaryByID: summaryByID
        )
    }

    func finishSelectionClickDebugTrace(_ trace: SelectionClickDebugTrace) {
        let afterSummaryByID = currentLineSummaryByID()
        let selectedAfterInOrder = lines.compactMap { line in
            selectedLineIDs.contains(line.id) ? line.id : nil
        }
        let isClickedSelectedAfter = selectedLineIDs.contains(trace.clickedLineID)

        let reportLines: [String] = [
            "=== SELECTION CLICK DEBUG ===",
            "timestamp=\(Self.backspaceDebugDateFormatter.string(from: trace.timestamp))",
            "source=\(trace.source)",
            "clicked.before=\(trace.clickedLineSummaryBefore)",
            "clicked.after=\(debugSummary(for: trace.clickedLineID, using: afterSummaryByID))",
            "clicked.isSelectedAfter=\(isClickedSelectedAfter)",
            "before.selected=\(debugSummary(for: trace.selectedLineIDBefore, using: trace.beforeLineSummaryByID))",
            "before.highlighted=\(debugSummary(for: trace.highlightedLineIDBefore, using: trace.beforeLineSummaryByID))",
            "before.anchor=\(debugSummary(for: trace.selectionAnchorLineIDBefore, using: trace.beforeLineSummaryByID))",
            "before.selectedLineIDs=\(trace.selectedLineIDsBeforeInOrder.map { debugSummary(for: $0, using: trace.beforeLineSummaryByID) }.joined(separator: " | "))",
            "after.selected=\(debugSummary(for: selectedLineID, using: afterSummaryByID))",
            "after.highlighted=\(debugSummary(for: highlightedLineID, using: afterSummaryByID))",
            "after.anchor=\(debugSummary(for: selectionAnchorLineID, using: afterSummaryByID))",
            "after.selectedLineIDs=\(selectedAfterInOrder.map { debugSummary(for: $0, using: afterSummaryByID) }.joined(separator: " | "))"
        ]
        let report = reportLines.joined(separator: "\n")
        appendBackspaceDebugReport(report)
        print(report)
    }

    private func captureDebugSelectionSnapshot(using summaries: [DialogueLine.ID: String]) -> DebugSelectionSnapshot {
        let selectedInOrder = lines.compactMap { line in
            selectedLineIDs.contains(line.id) ? line.id : nil
        }
        return DebugSelectionSnapshot(
            selected: debugSummary(for: selectedLineID, using: summaries),
            highlighted: debugSummary(for: highlightedLineID, using: summaries),
            anchor: debugSummary(for: selectionAnchorLineID, using: summaries),
            selectedLineIDs: selectedInOrder.map { debugSummary(for: $0, using: summaries) }.joined(separator: " | ")
        )
    }

    private func logStructureDebug(
        event: String,
        beforeCount: Int,
        afterCount: Int,
        beforeSelection: DebugSelectionSnapshot,
        afterSelection: DebugSelectionSnapshot,
        details: String = ""
    ) {
        let reportLines: [String] = [
            "=== STRUCTURE DEBUG ===",
            "timestamp=\(Self.backspaceDebugDateFormatter.string(from: Date()))",
            "event=\(event)",
            "count.before=\(beforeCount)",
            "count.after=\(afterCount)",
            "delta=\(afterCount - beforeCount)",
            "before.selected=\(beforeSelection.selected)",
            "before.highlighted=\(beforeSelection.highlighted)",
            "before.anchor=\(beforeSelection.anchor)",
            "before.selectedLineIDs=\(beforeSelection.selectedLineIDs)",
            "after.selected=\(afterSelection.selected)",
            "after.highlighted=\(afterSelection.highlighted)",
            "after.anchor=\(afterSelection.anchor)",
            "after.selectedLineIDs=\(afterSelection.selectedLineIDs)",
            "details=\(details)"
        ]
        let report = reportLines.joined(separator: "\n")
        appendBackspaceDebugReport(report)
        print(report)
    }

    func finishBackspaceDebugTrace(_ trace: BackspaceDebugTrace, deletedCountReturned: Int) {
        let afterIDSet = Set(lines.map(\.id))
        let removedIDs = trace.beforeAllLineIDs.filter { !afterIDSet.contains($0) }
        let removedIDSet = Set(removedIDs)
        let targetIDs = trace.targetLines.map(\.id)
        let targetIDSet = Set(targetIDs)

        let removedTargetIDs = targetIDs.filter { removedIDSet.contains($0) }
        let missedTargetIDs = targetIDs.filter { !removedIDSet.contains($0) }
        let unexpectedRemovedIDs = removedIDs.filter { !targetIDSet.contains($0) }

        let reportLines: [String] = [
            "=== BACKSPACE DEBUG ===",
            "timestamp=\(Self.backspaceDebugDateFormatter.string(from: trace.timestamp))",
            "watchedReplicaIndex=\(trace.watchedReplicaIndex)",
            "watchedReplicaMatched=\(trace.watchedReplicaMatched)",
            "deletedCountReturned=\(deletedCountReturned)",
            "before.selected=\(debugSummary(for: trace.selectedLineID, using: trace.beforeLineSummaryByID))",
            "before.highlighted=\(debugSummary(for: trace.highlightedLineID, using: trace.beforeLineSummaryByID))",
            "before.anchor=\(debugSummary(for: trace.selectionAnchorLineID, using: trace.beforeLineSummaryByID))",
            "before.selectedLineIDs=\(trace.selectedLineIDsInOrder.map { debugSummary(for: $0, using: trace.beforeLineSummaryByID) }.joined(separator: " | "))",
            "before.targets=\(trace.targetLines.map(\.summary).joined(separator: " | "))",
            "after.selected=\(debugSummary(for: selectedLineID, using: currentLineSummaryByID()))",
            "after.highlighted=\(debugSummary(for: highlightedLineID, using: currentLineSummaryByID()))",
            "after.anchor=\(debugSummary(for: selectionAnchorLineID, using: currentLineSummaryByID()))",
            "after.selectedLineIDs=\(lines.compactMap { selectedLineIDs.contains($0.id) ? debugLineSummary($0) : nil }.joined(separator: " | "))",
            "removed.actual=\(removedIDs.map { debugSummary(for: $0, using: trace.beforeLineSummaryByID) }.joined(separator: " | "))",
            "removed.targeted=\(removedTargetIDs.map { debugSummary(for: $0, using: trace.beforeLineSummaryByID) }.joined(separator: " | "))",
            "removed.unexpected=\(unexpectedRemovedIDs.map { debugSummary(for: $0, using: trace.beforeLineSummaryByID) }.joined(separator: " | "))",
            "target.missed=\(missedTargetIDs.map { debugSummary(for: $0, using: trace.beforeLineSummaryByID) }.joined(separator: " | "))"
        ]

        let report = reportLines.joined(separator: "\n")
        appendBackspaceDebugReport(report)
        print(report)
    }

    func snapshotDeletionTargetIDs() -> [DialogueLine.ID] {
        guard !lines.isEmpty else { return [] }
        let targetIDs = resolvedSelectionTargetIDs()
        guard !targetIDs.isEmpty else { return [] }
        return lines.compactMap { line in
            targetIDs.contains(line.id) ? line.id : nil
        }
    }

    @discardableResult
    func deleteSelectedLines() -> Int {
        deleteLines(withIDs: snapshotDeletionTargetIDs())
    }

    @discardableResult
    func deleteLines(withIDs ids: [DialogueLine.ID]) -> Int {
        let beforeCount = lines.count
        let beforeSummaries = currentLineSummaryByID()
        let beforeSelection = captureDebugSelectionSnapshot(using: beforeSummaries)

        guard !lines.isEmpty else { return 0 }
        guard !ids.isEmpty else { return 0 }
        let idSet = Set(ids)
        let targetIndices = lines.indices.filter { idSet.contains(lines[$0].id) }
        guard !targetIndices.isEmpty else { return 0 }
        let targetIDs = Set(targetIndices.map { lines[$0].id })

        flushPendingHistory()

        let deletedItems = targetIndices.map { index in
            DeletedLineChange(line: lines[index], index: index)
        }
        let firstSelectedIndex = targetIndices.first ?? 0
        var remaining = lines.filter { !targetIDs.contains($0.id) }
        let deletedCount = lines.count - remaining.count
        guard deletedCount > 0 else { return 0 }

        normalizeLineIndices(&remaining)

        pendingExplicitHistoryEntry = .delete(items: deletedItems)
        lines = remaining

        if remaining.isEmpty {
            selectedLineID = nil
            selectedLineIDs = []
            selectionAnchorLineID = nil
            highlightedLineID = nil
            editingLineID = nil
            isLoopEnabled = false
            return deletedCount
        }

        let nextIndex = min(firstSelectedIndex, remaining.count - 1)
        let nextLine = remaining[nextIndex]
        selectedLineID = nextLine.id
        selectedLineIDs = [nextLine.id]
        selectionAnchorLineID = nextLine.id
        highlightedLineID = nextLine.id
        if let editingLineID, targetIDs.contains(editingLineID) {
            self.editingLineID = nil
        }

        let afterSummaries = currentLineSummaryByID()
        let afterSelection = captureDebugSelectionSnapshot(using: afterSummaries)
        let deletedDetails = deletedItems
            .compactMap { item in
                beforeSummaries[item.line.id]
            }
            .joined(separator: " | ")
        logStructureDebug(
            event: "deleteLines(withIDs:)",
            beforeCount: beforeCount,
            afterCount: lines.count,
            beforeSelection: beforeSelection,
            afterSelection: afterSelection,
            details: "deletedCount=\(deletedCount) targets=\(deletedDetails)"
        )

        return deletedCount
    }

    func canCopySelectedLines() -> Bool {
        !orderedSelectedLineIndices().isEmpty
    }

    func canPasteReplicasFromClipboard() -> Bool {
        let pasteboard = NSPasteboard.general
        return pasteboard.availableType(from: [Self.replicaClipboardType]) != nil
    }

    @discardableResult
    func copySelectedLinesToClipboard() -> Int {
        let indices = orderedSelectedLineIndices()
        guard !indices.isEmpty else { return 0 }

        let payload = indices.map { index in
            let line = lines[index]
            return ClipboardLinePayload(
                speaker: line.speaker,
                text: line.text,
                startTimecode: line.startTimecode,
                endTimecode: line.endTimecode
            )
        }

        let encoder = JSONEncoder()
        guard let data = try? encoder.encode(payload) else {
            return 0
        }

        let plainText = payload.map { line in
            "\(line.speaker)\t\(line.startTimecode)\t\(line.endTimecode)\t\(line.text)"
        }.joined(separator: "\n")

        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setData(data, forType: Self.replicaClipboardType)
        pasteboard.setString(plainText, forType: .string)
        return payload.count
    }

    @discardableResult
    func pasteReplicasFromClipboard() -> Int {
        let beforeCount = lines.count
        let beforeSummaries = currentLineSummaryByID()
        let beforeSelection = captureDebugSelectionSnapshot(using: beforeSummaries)

        let pasteboard = NSPasteboard.general
        guard
            let data = pasteboard.data(forType: Self.replicaClipboardType),
            let payload = try? JSONDecoder().decode([ClipboardLinePayload].self, from: data),
            !payload.isEmpty
        else {
            return 0
        }

        flushPendingHistory()

        let insertionIndex: Int
        if
            let selectedLineID,
            let selectedIndex = indexOfLine(withID: selectedLineID)
        {
            insertionIndex = min(lines.count, selectedIndex + 1)
        } else {
            insertionIndex = lines.count
        }

        let newLines = payload.enumerated().map { offset, row in
            DialogueLine(
                index: insertionIndex + offset + 1,
                speaker: row.speaker,
                text: row.text,
                startTimecode: row.startTimecode,
                endTimecode: row.endTimecode
            )
        }

        var updated = lines
        updated.insert(contentsOf: newLines, at: insertionIndex)
        normalizeLineIndices(&updated)

        pendingExplicitHistoryEntry = .insert(lines: newLines, index: insertionIndex)
        lines = updated

        let selectedIDs = Set(newLines.map(\.id))
        selectedLineIDs = selectedIDs
        selectedLineID = newLines.last?.id
        selectionAnchorLineID = newLines.first?.id
        highlightedLineID = newLines.last?.id
        pendingRestoreLineID = newLines.last?.id
        editingLineID = nil

        let afterSummaries = currentLineSummaryByID()
        let afterSelection = captureDebugSelectionSnapshot(using: afterSummaries)
        let insertedDetails = newLines.map { line in
            afterSummaries[line.id] ?? "<missing \(line.id.uuidString)>"
        }.joined(separator: " | ")
        logStructureDebug(
            event: "pasteReplicasFromClipboard",
            beforeCount: beforeCount,
            afterCount: lines.count,
            beforeSelection: beforeSelection,
            afterSelection: afterSelection,
            details: "insertedCount=\(newLines.count) inserted=\(insertedDetails)"
        )

        return newLines.count
    }

    func finishEditing() {
        flushPendingHistory()
        editingLineID = nil
    }

    func startEditingSelectedLine() {
        guard !isTimecodeModeEnabled else { return }
        guard let selectedLineID else { return }
        guard indexOfLine(withID: selectedLineID) != nil else { return }
        cancelPendingSelectionSeek()
        selectedLineIDs = [selectedLineID]
        selectionAnchorLineID = selectedLineID
        highlightedLineID = selectedLineID
        editingLineID = selectedLineID
    }

    func setStartFromCurrentTime(lineID: DialogueLine.ID) {
        guard let index = indexOfLine(withID: lineID) else {
            return
        }
        if let timecode = currentInsertionStartTimecode() {
            lines[index].startTimecode = timecode
        }
    }

    func setEndFromCurrentTime(lineID: DialogueLine.ID) {
        guard let index = indexOfLine(withID: lineID) else {
            return
        }
        if let timecode = currentPlaybackTimecodeString(hideFrames: false) {
            lines[index].endTimecode = timecode
        }
    }

    @discardableResult
    func applySpeakerAutocompleteSuggestion(lineID: DialogueLine.ID, suggestion: String) -> Bool {
        guard let index = indexOfLine(withID: lineID) else {
            return false
        }

        let normalizedSuggestion = suggestion.trimmingCharacters(in: .whitespacesAndNewlines)
        if lines[index].speaker == normalizedSuggestion {
            return true
        }

        lines[index].speaker = normalizedSuggestion
        return true
    }

    func speakerAppearance(for speaker: String) -> SpeakerAppearance? {
        SpeakerAppearanceService.resolvedAppearance(
            for: speaker,
            overridesByKey: speakerColorOverridesByKey
        )
    }

    func speakerColorOverridePaletteID(for speaker: String) -> SpeakerColorPaletteID? {
        SpeakerAppearanceService.overridePaletteID(
            for: speaker,
            overridesByKey: speakerColorOverridesByKey
        )
    }

    func setSpeakerColorOverride(for speaker: String, paletteID rawPaletteID: String) {
        let normalizedKey = SpeakerAppearanceService.normalizedSpeakerKey(speaker)
        guard !normalizedKey.isEmpty else { return }
        guard let paletteID = SpeakerColorPaletteID(rawValue: rawPaletteID) else { return }

        var updatedOverrides = speakerColorOverridesByKey
        if SpeakerAppearanceService.defaultPaletteID(forNormalizedSpeakerKey: normalizedKey) == paletteID {
            updatedOverrides.removeValue(forKey: normalizedKey)
        } else {
            updatedOverrides[normalizedKey] = paletteID.rawValue
        }

        guard updatedOverrides != speakerColorOverridesByKey else { return }
        speakerColorOverridesByKey = updatedOverrides
        markProjectDirty()
        scheduleAutosave()
    }

    func resetSpeakerColorOverride(for speaker: String) {
        let normalizedKey = SpeakerAppearanceService.normalizedSpeakerKey(speaker)
        guard !normalizedKey.isEmpty else { return }
        guard speakerColorOverridesByKey[normalizedKey] != nil else { return }

        speakerColorOverridesByKey.removeValue(forKey: normalizedKey)
        markProjectDirty()
        scheduleAutosave()
    }

    func currentPlaybackTimecodeString(
        hideFrames: Bool,
        playbackSecondsOverride: Double? = nil
    ) -> String? {
        guard let timelineSeconds = currentTimelinePlaybackSeconds(playbackSecondsOverride: playbackSecondsOverride) else {
            return nil
        }

        if hideFrames {
            return TimecodeService.timecodeWithoutFrames(from: timelineSeconds)
        }
        return TimecodeService.timecode(from: timelineSeconds, fps: fps)
    }

    func captureStartTimecodeForSelectedLine(advanceToNext: Bool) {
        timecodeCaptureTarget = .start
        guard let lineID = resolveSelectedLineForTimecodeCapture() else {
            return
        }
        setStartFromCurrentTime(lineID: lineID)
        if advanceToNext {
            moveSelection(step: 1)
        } else if isTimecodeAutoSwitchTargetEnabled {
            timecodeCaptureTarget = .end
        }
    }

    func captureEndTimecodeForSelectedLine(advanceToNext: Bool) {
        timecodeCaptureTarget = .end
        guard let lineID = resolveSelectedLineForTimecodeCapture() else {
            return
        }
        setEndFromCurrentTime(lineID: lineID)
        if advanceToNext {
            moveSelection(step: 1)
        }
        if isTimecodeAutoSwitchTargetEnabled {
            timecodeCaptureTarget = .start
        }
    }

    func captureActiveTimecodeForSelectedLine(advanceToNext: Bool) {
        switch timecodeCaptureTarget {
        case .start:
            captureStartTimecodeForSelectedLine(advanceToNext: advanceToNext)
        case .end:
            captureEndTimecodeForSelectedLine(advanceToNext: advanceToNext)
        }
    }

    @discardableResult
    func prefillEmptyTimecodeWithPreviousHourMinute(
        lineID: DialogueLine.ID,
        target: TimecodeCaptureTarget,
        allowOutsideTimecodeMode: Bool = false
    ) -> Bool {
        guard isTimecodeModeEnabled || allowOutsideTimecodeMode else { return false }
        guard let lineIndex = indexOfLine(withID: lineID), lines.indices.contains(lineIndex) else {
            return false
        }

        let currentRawValue: String
        switch target {
        case .start:
            currentRawValue = lines[lineIndex].startTimecode
        case .end:
            currentRawValue = lines[lineIndex].endTimecode
        }
        if !currentRawValue.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return false
        }

        let previousIndex = lineIndex - 1
        guard lines.indices.contains(previousIndex) else { return false }

        let previousRawValue: String
        switch target {
        case .start:
            previousRawValue = lines[previousIndex].startTimecode
        case .end:
            previousRawValue = lines[previousIndex].endTimecode
        }
        guard let prefix = hourMinutePrefix(from: previousRawValue) else {
            return false
        }

        switch target {
        case .start:
            lines[lineIndex].startTimecode = prefix
        case .end:
            lines[lineIndex].endTimecode = prefix
        }
        return true
    }

    @discardableResult
    func fillMissingStartTimecodesWithPreviousHourMinute() -> Int {
        guard !lines.isEmpty else { return 0 }

        var updatedLines = lines
        var previousPrefix: String?
        var filledCount = 0

        for index in updatedLines.indices {
            let currentStart = updatedLines[index].startTimecode
            if let prefix = hourMinutePrefix(from: currentStart) {
                previousPrefix = prefix
                continue
            }

            let trimmed = currentStart.trimmingCharacters(in: .whitespacesAndNewlines)
            guard trimmed.isEmpty else { continue }
            guard let previousPrefix else { continue }

            updatedLines[index].startTimecode = previousPrefix
            filledCount += 1
        }

        guard filledCount > 0 else {
            return 0
        }

        lines = updatedLines
        return filledCount
    }

    func missingTimecodeCount(for target: TimecodeCaptureTarget) -> Int {
        lines.reduce(into: 0) { count, line in
            if isMissingTimecode(in: line, for: target) {
                count += 1
            }
        }
    }

    @discardableResult
    func selectNextLineMissingTimecodeForActiveTarget() -> Bool {
        selectNextLineMissingTimecode(for: timecodeCaptureTarget)
    }

    @discardableResult
    func selectNextLineMissingTimecode(for target: TimecodeCaptureTarget) -> Bool {
        guard !lines.isEmpty else { return false }

        let startIndex = selectedLineID.flatMap { indexOfLine(withID: $0) } ?? -1
        for offset in 1...lines.count {
            let index = (startIndex + offset + lines.count) % lines.count
            let line = lines[index]
            if isMissingTimecode(in: line, for: target) {
                selectLine(line)
                return true
            }
        }

        return false
    }

    @discardableResult
    func insertNewLineAfterSelection(currentPlaybackSecondsOverride: Double? = nil) -> DialogueLine.ID {
        let beforeCount = lines.count
        let beforeSummaries = currentLineSummaryByID()
        let beforeSelection = captureDebugSelectionSnapshot(using: beforeSummaries)

        flushPendingHistory()

        let insertionIndex: Int
        if
            let selectedLineID,
            let selectedIndex = indexOfLine(withID: selectedLineID)
        {
            insertionIndex = min(lines.count, selectedIndex + 1)
        } else {
            insertionIndex = lines.count
        }

        var updated = lines
        let autoStartTimecode = currentInsertionStartTimecode(playbackSecondsOverride: currentPlaybackSecondsOverride)
            ?? autoStartTimecodeForInsertedLine(in: updated, insertionIndex: insertionIndex)
        let newLine = DialogueLine(
            index: insertionIndex + 1,
            speaker: "",
            text: "",
            startTimecode: autoStartTimecode,
            endTimecode: ""
        )
        updated.insert(newLine, at: insertionIndex)
        normalizeLineIndices(&updated)

        pendingExplicitHistoryEntry = .insert(lines: [newLine], index: insertionIndex)
        lines = updated
        selectedLineID = newLine.id
        selectedLineIDs = [newLine.id]
        selectionAnchorLineID = newLine.id
        highlightedLineID = newLine.id
        editingLineID = newLine.id

        let afterSummaries = currentLineSummaryByID()
        let afterSelection = captureDebugSelectionSnapshot(using: afterSummaries)
        let insertedDetails = afterSummaries[newLine.id] ?? "<missing \(newLine.id.uuidString)>"
        logStructureDebug(
            event: "insertNewLineAfterSelection",
            beforeCount: beforeCount,
            afterCount: lines.count,
            beforeSelection: beforeSelection,
            afterSelection: afterSelection,
            details: "inserted=\(insertedDetails)"
        )

        return newLine.id
    }

    @discardableResult
    func moveLine(draggedLineID: DialogueLine.ID, before targetLineID: DialogueLine.ID?) -> Bool {
        guard !lines.isEmpty else { return false }
        guard let sourceIndex = indexOfLine(withID: draggedLineID) else { return false }

        let targetIndex: Int
        if let targetLineID {
            guard let resolvedTargetIndex = indexOfLine(withID: targetLineID) else { return false }
            if resolvedTargetIndex == sourceIndex {
                return false
            }
            targetIndex = resolvedTargetIndex
        } else {
            targetIndex = lines.count
        }

        flushPendingHistory()

        var updated = lines
        let moving = updated.remove(at: sourceIndex)
        let destinationIndex: Int
        if sourceIndex < targetIndex {
            destinationIndex = max(0, min(updated.count, targetIndex - 1))
        } else {
            destinationIndex = max(0, min(updated.count, targetIndex))
        }
        updated.insert(moving, at: destinationIndex)

        normalizeLineIndices(&updated)

        pendingExplicitHistoryEntry = .move(
            lineID: moving.id,
            fromIndex: sourceIndex,
            toIndex: destinationIndex
        )
        lines = updated
        return true
    }

    private func autoStartTimecodeForInsertedLine(in currentLines: [DialogueLine], insertionIndex: Int) -> String {
        guard !currentLines.isEmpty else {
            return "00:00:"
        }

        let previousIndex = min(max(0, insertionIndex - 1), currentLines.count - 1)
        if let prefix = hourMinutePrefix(from: currentLines[previousIndex].startTimecode) {
            return prefix
        }

        var scanIndex = previousIndex - 1
        while scanIndex >= 0 {
            if let prefix = hourMinutePrefix(from: currentLines[scanIndex].startTimecode) {
                return prefix
            }
            scanIndex -= 1
        }

        return "00:00:"
    }

    func seekToCurrentSelection() {
        guard
            let selectedLineID,
            let selectedIndex = indexOfLine(withID: selectedLineID)
        else {
            return
        }
        selectLine(lines[selectedIndex])
    }

    private func resolveSelectedLineForTimecodeCapture() -> DialogueLine.ID? {
        if let selectedLineID, indexOfLine(withID: selectedLineID) != nil {
            selectedLineIDs = [selectedLineID]
            selectionAnchorLineID = selectedLineID
            highlightedLineID = selectedLineID
            return selectedLineID
        }

        guard let first = lines.first else {
            return nil
        }
        selectedLineID = first.id
        selectedLineIDs = [first.id]
        selectionAnchorLineID = first.id
        highlightedLineID = first.id
        return first.id
    }

    private func orderedSelectedLineIndices() -> [Int] {
        guard !lines.isEmpty else { return [] }
        let targetIDs = resolvedSelectionTargetIDs()
        guard !targetIDs.isEmpty else { return [] }
        return lines.indices.filter { targetIDs.contains(lines[$0].id) }
    }

    private func resolvedSelectionTargetIDs() -> Set<DialogueLine.ID> {
        guard !lines.isEmpty else { return [] }

        let validIDs = Set(lines.map(\.id))
        let sanitizedSelectedIDs = selectedLineIDs.intersection(validIDs)
        let selectedIsValid = selectedLineID.flatMap { validIDs.contains($0) ? $0 : nil }
        let highlightedIsValid = highlightedLineID.flatMap { validIDs.contains($0) ? $0 : nil }

        if sanitizedSelectedIDs.count == 1 {
            return sanitizedSelectedIDs
        }

        if sanitizedSelectedIDs.count > 1 {
            if
                let selectedIsValid,
                sanitizedSelectedIDs.contains(selectedIsValid),
                let anchor = selectionAnchorLineID,
                validIDs.contains(anchor),
                anchor != selectedIsValid
            {
                return sanitizedSelectedIDs
            }

            if let selectedIsValid, sanitizedSelectedIDs.contains(selectedIsValid) {
                return [selectedIsValid]
            }
            if let highlightedIsValid, sanitizedSelectedIDs.contains(highlightedIsValid) {
                return [highlightedIsValid]
            }
            if let firstID = firstLineIDInCurrentOrder(from: sanitizedSelectedIDs) {
                return [firstID]
            }
        }

        if let selectedIsValid {
            return [selectedIsValid]
        }
        if let highlightedIsValid {
            return [highlightedIsValid]
        }

        return []
    }

    private func isMissingTimecode(in line: DialogueLine, for target: TimecodeCaptureTarget) -> Bool {
        let rawValue: String
        switch target {
        case .start:
            rawValue = line.startTimecode
        case .end:
            rawValue = line.endTimecode
        }
        return TimecodeService.seconds(from: rawValue, fps: fps) == nil
    }

    func requestExportDocxFlow() {
        guard !lines.isEmpty else {
            alertMessage = String(localized: "alert.nothing_to_export_no_lines", bundle: .appBundle)
            return
        }

        guard let options = promptWordExportOptions() else {
            return
        }
        let draft = WordExportPipelineService().buildDraft(from: lines, options: options, fps: fps)
        guard !draft.rows.isEmpty else {
            alertMessage = String(localized: "alert.nothing_to_export_empty_lines", bundle: .appBundle)
            return
        }

        let panel = NSSavePanel()
        panel.allowedContentTypes = [UTType(filenameExtension: "docx")].compactMap { $0 }
        panel.canCreateDirectories = true
        panel.nameFieldStringValue = defaultWordExportFilename(for: options)

        guard panel.runModal() == .OK, let url = panel.url else {
            return
        }

        do {
            try WordExportService().exportDocx(draft: draft, to: url)
            alertMessage = String(format: String(localized: "alert.export_docx_done", bundle: .appBundle), draft.profile.displayName, draft.rows.count)
        } catch {
            alertMessage = String(format: String(localized: "alert.export_docx_failed", bundle: .appBundle), error.localizedDescription)
        }
    }

    private func promptWordExportOptions() -> WordExportOptions? {
        let previousOptions = loadWordExportOptions()

        let alert = NSAlert()
        alert.messageText = "Export DOCX"
        alert.informativeText = "Zvol typ exportu a format timecodu."
        alert.alertStyle = .informational
        alert.addButton(withTitle: "Pokracovat")
        alert.addButton(withTitle: "Zrusit")

        let profilePopup = NSPopUpButton(frame: .zero, pullsDown: false)
        WordExportProfile.allCases.forEach { profilePopup.addItem(withTitle: $0.displayName) }
        if let selectedIndex = WordExportProfile.allCases.firstIndex(of: previousOptions.profile) {
            profilePopup.selectItem(at: selectedIndex)
        }
        profilePopup.translatesAutoresizingMaskIntoConstraints = false
        profilePopup.widthAnchor.constraint(equalToConstant: 280).isActive = true

        let sourcePopup = NSPopUpButton(frame: .zero, pullsDown: false)
        sourcePopup.addItems(withTitles: ["Start TC", "End TC"])
        sourcePopup.selectItem(at: previousOptions.timecodeSource == .start ? 0 : 1)
        sourcePopup.translatesAutoresizingMaskIntoConstraints = false
        sourcePopup.widthAnchor.constraint(equalToConstant: 280).isActive = true

        let hoursButton = NSButton(checkboxWithTitle: "Hodiny", target: nil, action: nil)
        hoursButton.state = previousOptions.timecodeFormat.includeHours ? .on : .off
        let minutesButton = NSButton(checkboxWithTitle: "Minuty", target: nil, action: nil)
        minutesButton.state = previousOptions.timecodeFormat.includeMinutes ? .on : .off
        let secondsButton = NSButton(checkboxWithTitle: "Sekundy", target: nil, action: nil)
        secondsButton.state = previousOptions.timecodeFormat.includeSeconds ? .on : .off
        let framesButton = NSButton(checkboxWithTitle: "Framy", target: nil, action: nil)
        framesButton.state = previousOptions.timecodeFormat.includeFrames ? .on : .off

        let timecodePartsStack = NSStackView(views: [hoursButton, minutesButton, secondsButton, framesButton])
        timecodePartsStack.orientation = .horizontal
        timecodePartsStack.alignment = .centerY
        timecodePartsStack.spacing = 12
        timecodePartsStack.translatesAutoresizingMaskIntoConstraints = false

        let profileLabel = NSTextField(labelWithString: "Typ exportu")
        profileLabel.font = NSFont.systemFont(ofSize: 12, weight: .medium)
        profileLabel.textColor = .secondaryLabelColor
        let sourceLabel = NSTextField(labelWithString: "Zdroj TC")
        sourceLabel.font = NSFont.systemFont(ofSize: 12, weight: .medium)
        sourceLabel.textColor = .secondaryLabelColor
        let formatLabel = NSTextField(labelWithString: "Format TC")
        formatLabel.font = NSFont.systemFont(ofSize: 12, weight: .medium)
        formatLabel.textColor = .secondaryLabelColor

        let content = NSStackView(views: [
            profileLabel,
            profilePopup,
            sourceLabel,
            sourcePopup,
            formatLabel,
            timecodePartsStack
        ])
        content.orientation = .vertical
        content.alignment = .leading
        content.spacing = 6
        content.translatesAutoresizingMaskIntoConstraints = false
        content.edgeInsets = NSEdgeInsets(top: 2, left: 0, bottom: 0, right: 0)

        let accessory = NSView(frame: NSRect(x: 0, y: 0, width: 300, height: 190))
        accessory.addSubview(content)
        NSLayoutConstraint.activate([
            content.leadingAnchor.constraint(equalTo: accessory.leadingAnchor),
            content.trailingAnchor.constraint(equalTo: accessory.trailingAnchor),
            content.topAnchor.constraint(equalTo: accessory.topAnchor),
            content.bottomAnchor.constraint(equalTo: accessory.bottomAnchor)
        ])
        alert.accessoryView = accessory

        guard alert.runModal() == .alertFirstButtonReturn else {
            return nil
        }

        let selectedProfileIndex = max(0, min(profilePopup.indexOfSelectedItem, WordExportProfile.allCases.count - 1))
        let selectedProfile = WordExportProfile.allCases[selectedProfileIndex]
        let selectedSource: WordExportTimecodeSource = sourcePopup.indexOfSelectedItem == 0 ? .start : .end
        let options = WordExportOptions(
            profile: selectedProfile,
            timecodeSource: selectedSource,
            timecodeFormat: WordExportTimecodeFormat(
                includeHours: hoursButton.state == .on,
                includeMinutes: minutesButton.state == .on,
                includeSeconds: secondsButton.state == .on,
                includeFrames: framesButton.state == .on
            ),
            includeEmptyRows: false
        )
        persistWordExportOptions(options)
        return options
    }

    private func loadWordExportOptions() -> WordExportOptions {
        let defaults = UserDefaults.standard
        let profile: WordExportProfile = {
            guard
                let raw = defaults.string(forKey: Self.wordExportProfileDefaultsKey),
                let parsed = WordExportProfile(rawValue: raw)
            else {
                return .classic
            }
            return parsed
        }()
        let source: WordExportTimecodeSource = {
            guard
                let raw = defaults.string(forKey: Self.wordExportTimecodeSourceDefaultsKey),
                let parsed = WordExportTimecodeSource(rawValue: raw)
            else {
                return .start
            }
            return parsed
        }()

        let includeHours = defaults.object(forKey: Self.wordExportIncludeHoursDefaultsKey) == nil
            ? true
            : defaults.bool(forKey: Self.wordExportIncludeHoursDefaultsKey)
        let includeMinutes = defaults.object(forKey: Self.wordExportIncludeMinutesDefaultsKey) == nil
            ? true
            : defaults.bool(forKey: Self.wordExportIncludeMinutesDefaultsKey)
        let includeSeconds = defaults.object(forKey: Self.wordExportIncludeSecondsDefaultsKey) == nil
            ? true
            : defaults.bool(forKey: Self.wordExportIncludeSecondsDefaultsKey)
        let includeFrames = defaults.object(forKey: Self.wordExportIncludeFramesDefaultsKey) == nil
            ? true
            : defaults.bool(forKey: Self.wordExportIncludeFramesDefaultsKey)

        return WordExportOptions(
            profile: profile,
            timecodeSource: source,
            timecodeFormat: WordExportTimecodeFormat(
                includeHours: includeHours,
                includeMinutes: includeMinutes,
                includeSeconds: includeSeconds,
                includeFrames: includeFrames
            ),
            includeEmptyRows: false
        )
    }

    private func persistWordExportOptions(_ options: WordExportOptions) {
        let defaults = UserDefaults.standard
        defaults.set(options.profile.rawValue, forKey: Self.wordExportProfileDefaultsKey)
        defaults.set(options.timecodeSource.rawValue, forKey: Self.wordExportTimecodeSourceDefaultsKey)
        defaults.set(options.timecodeFormat.includeHours, forKey: Self.wordExportIncludeHoursDefaultsKey)
        defaults.set(options.timecodeFormat.includeMinutes, forKey: Self.wordExportIncludeMinutesDefaultsKey)
        defaults.set(options.timecodeFormat.includeSeconds, forKey: Self.wordExportIncludeSecondsDefaultsKey)
        defaults.set(options.timecodeFormat.includeFrames, forKey: Self.wordExportIncludeFramesDefaultsKey)
    }

    private func defaultWordExportFilename(for options: WordExportOptions) -> String {
        let suffix: String
        switch options.profile {
        case .classic:
            suffix = "-uprava"
        case .sdi:
            suffix = "-iyuno"
        }
        return "\(documentTitle)\(suffix).docx"
    }

    func promptExportSpeakerStatisticsCSV() {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [UTType.commaSeparatedText]
        panel.canCreateDirectories = true
        panel.nameFieldStringValue = "\(documentTitle)-postavy.csv"

        if panel.runModal() == .OK, let url = panel.url {
            exportSpeakerStatisticsCSV(to: url)
        }
    }

    func bugReportsRootURL() -> URL {
        BugReportService().reportsRootURL(preferredBaseDirectory: preferredBugReportsBaseDirectory())
    }

    func openBugReportsFolder() {
        let rootURL = bugReportsRootURL()
        do {
            try FileManager.default.createDirectory(at: rootURL, withIntermediateDirectories: true, attributes: nil)
            NSWorkspace.shared.open(rootURL)
        } catch {
            alertMessage = String(format: String(localized: "alert.open_report_folder_failed", bundle: .appBundle), error.localizedDescription)
        }
    }

    func openBugReportsDashboard() {
        do {
            let dashboardURL = try BugReportService().refreshDashboard(
                preferredBaseDirectory: preferredBugReportsBaseDirectory()
            )
            NSWorkspace.shared.open(dashboardURL)
        } catch {
            alertMessage = String(format: String(localized: "alert.open_bug_dashboard_failed", bundle: .appBundle), error.localizedDescription)
        }
    }

    func suggestedBugReportTitle() -> String {
        if let line = selectedLineForBugReportContext() {
            let speaker = line.speaker.trimmingCharacters(in: .whitespacesAndNewlines)
            if speaker.isEmpty {
                return "Bug u repliky \(line.index)"
            }
            return "Bug u repliky \(line.index) - \(speaker)"
        }
        return "Bug report - \(documentTitle)"
    }

    func createBugReport(
        draft: BugReportDraft,
        uiState: BugReportUIState,
        screenshotPNGData: Data?
    ) async throws -> URL {
        let editorState = buildBugReportEditorState()
        let projectSnapshot = draft.includeProjectSnapshot ? buildCurrentProjectFile() : nil
        let preferredBaseDirectory = preferredBugReportsBaseDirectory()
        let debugLogURLs = knownBugReportLogURLs()

        return try await Task.detached(priority: .utility) {
            try BugReportService().createReport(
                draft: draft,
                editorState: editorState,
                uiState: uiState,
                screenshotPNGData: screenshotPNGData,
                projectSnapshot: projectSnapshot,
                preferredBaseDirectory: preferredBaseDirectory,
                additionalLogURLs: debugLogURLs
            )
        }.value
    }

    func saveProject(to destinationURL: URL) {
        let payload = buildCurrentProjectFile()
        projectIOTask?.cancel()
        let operationID = UUID()
        activeProjectOperationID = operationID
        projectIOTask = Task.detached(priority: .utility) { [destinationURL, payload, operationID] in
            do {
                try ProjectService().save(payload, to: destinationURL)
                await MainActor.run { [weak self] in
                    guard let self else { return }
                    guard self.activeProjectOperationID == operationID else { return }
                    self.currentProjectURL = destinationURL
                    self.addRecentProjectURL(destinationURL)
                }
            } catch {
                await MainActor.run { [weak self] in
                    guard let self else { return }
                    guard self.activeProjectOperationID == operationID else { return }
                    self.alertMessage = String(format: String(localized: "alert.save_project_failed", bundle: .appBundle), error.localizedDescription)
                }
            }
        }
    }

    func openProject(from sourceURL: URL) {
        projectIOTask?.cancel()
        alertMessage = nil
        let operationID = UUID()
        activeProjectOperationID = operationID
        projectIOTask = Task.detached(priority: .userInitiated) { [sourceURL, operationID] in
            do {
                let project = try ProjectService().load(from: sourceURL)
                await MainActor.run { [weak self] in
                    guard let self else { return }
                    guard self.activeProjectOperationID == operationID else { return }
                    self.apply(project: project)
                    self.currentProjectURL = sourceURL
                    self.documentTitle = project.documentTitle
                    self.addRecentProjectURL(sourceURL)
                    self.scheduleAutosave()
                }
            } catch {
                await MainActor.run { [weak self] in
                    guard let self else { return }
                    guard self.activeProjectOperationID == operationID else { return }
                    self.alertMessage = String(format: String(localized: "alert.open_project_failed", bundle: .appBundle), error.localizedDescription)
                }
            }
        }
    }

    func promptImportWord() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [
            UTType(filenameExtension: "doc"),
            UTType(filenameExtension: "docx")
        ].compactMap { $0 }
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false

        if panel.runModal() == .OK, let url = panel.url {
            importWord(from: url)
        }
    }

    func promptImportVideo() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [
            .mpeg4Movie,
            .quickTimeMovie
        ]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false

        if panel.runModal() == .OK, let url = panel.url {
            importVideo(from: url)
        }
    }

    func promptImportExternalAudio() {
        guard videoURL != nil else {
            alertMessage = String(localized: "alert.video_required", bundle: .appBundle)
            return
        }

        let panel = NSOpenPanel()
        panel.allowedContentTypes = [
            .audio,
            .mpeg4Audio,
            .mp3,
            .wav,
            .aiff
        ]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false

        if panel.runModal() == .OK, let url = panel.url {
            importExternalAudio(from: url)
        }
    }

    func promptOpenProject() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [UTType(filenameExtension: "dbeproj")].compactMap { $0 }
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false

        if panel.runModal() == .OK, let url = panel.url {
            openProject(from: url)
        }
    }

    func openRecentProject(_ url: URL) {
        let canonical = url.standardizedFileURL
        guard FileManager.default.fileExists(atPath: canonical.path) else {
            removeRecentProjectURL(canonical)
            alertMessage = String(format: String(localized: "alert.project_not_found", bundle: .appBundle), canonical.path)
            return
        }
        openProject(from: canonical)
    }

    func clearRecentProjects() {
        recentProjectURLs = []
        UserDefaults.standard.set([], forKey: Self.recentProjectsDefaultsKey)
    }

    func exportSpeakerStatisticsCSV(to destinationURL: URL) {
        let stats = speakerStatistics()
        let formatter = NumberFormatter()
        formatter.locale = Locale(identifier: "cs_CZ")
        formatter.numberStyle = .decimal
        formatter.minimumFractionDigits = 1
        formatter.maximumFractionDigits = 1

        var lines: [String] = []
        lines.reserveCapacity(stats.count + 1)
        lines.append("Postava;Vstupy;Repliky")

        for row in stats {
            let replicas = formatter.string(from: NSNumber(value: row.replicaUnits))
                ?? String(format: "%.1f", row.replicaUnits)
            let speaker = csvEscaped(row.speaker, delimiter: ";")
            lines.append("\(speaker);\(row.entries);\(replicas)")
        }

        let body = lines.joined(separator: "\n")
        do {
            guard let data = body.data(using: .utf8) else {
                alertMessage = String(localized: "alert.csv_prepare_failed", bundle: .appBundle)
                return
            }
            try data.write(to: destinationURL, options: .atomic)
        } catch {
            alertMessage = String(format: String(localized: "alert.csv_export_failed", bundle: .appBundle), error.localizedDescription)
        }
    }

    func promptSaveProject() {
        promptSaveProjectAs()
    }

    func saveProject() {
        if let currentProjectURL {
            saveProject(to: currentProjectURL)
        } else {
            promptSaveProjectAs()
        }
    }

    func promptSaveProjectAs() {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [UTType(filenameExtension: "dbeproj")].compactMap { $0 }
        panel.canCreateDirectories = true
        panel.nameFieldStringValue = currentProjectURL?.lastPathComponent ?? "\(documentTitle).dbeproj"

        if panel.runModal() == .OK, let url = panel.url {
            saveProject(to: url)
        }
    }

    func applyOffset(rawValue: String) {
        guard !lines.isEmpty else {
            return
        }

        guard let offset = TimecodeService.offsetSeconds(from: rawValue, fps: fps) else {
            alertMessage = String(localized: "alert.invalid_offset", bundle: .appBundle)
            return
        }

        flushPendingHistory()

        let validIDs = Set(lines.map(\.id))
        let selectedIDs = selectedLineIDs.intersection(validIDs)
        let shouldApplyOnlySelected = selectedIDs.count > 1
        let targetIndices: [Int]
        if shouldApplyOnlySelected {
            targetIndices = lines.indices.filter { selectedIDs.contains(lines[$0].id) }
        } else {
            targetIndices = Array(lines.indices)
        }

        var changedCount = 0
        for index in targetIndices {
            if let startSeconds = TimecodeService.seconds(from: lines[index].startTimecode, fps: fps) {
                lines[index].startTimecode = TimecodeService.timecode(from: startSeconds + offset, fps: fps)
                changedCount += 1
            }

            if let endSeconds = TimecodeService.seconds(from: lines[index].endTimecode, fps: fps) {
                lines[index].endTimecode = TimecodeService.timecode(from: endSeconds + offset, fps: fps)
                changedCount += 1
            }
        }

        if changedCount == 0 {
            alertMessage = String(localized: "alert.offset_no_timecodes", bundle: .appBundle)
        }
    }

    func applyVideoOffset(rawValue: String) {
        let trimmed = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            videoOffsetSeconds = 0
            return
        }

        guard let offset = TimecodeService.offsetSeconds(from: trimmed, fps: fps) else {
            alertMessage = String(localized: "alert.invalid_video_offset", bundle: .appBundle)
            return
        }

        videoOffsetSeconds = offset

        guard
            let selectedLineID,
            let selectedIndex = indexOfLine(withID: selectedLineID),
            let selectedStart = TimecodeService.seconds(from: lines[selectedIndex].startTimecode, fps: fps)
        else {
            return
        }
        seekToTimeline(seconds: selectedStart, source: "video_offset_apply")
    }

    func recordDevClickToFocus(milliseconds: Double, label: String) {
        guard isDevModeEnabled else { return }
        devInteractionMetrics.clickToFocusMilliseconds = milliseconds
        devInteractionMetrics.clickToFocusLabel = label
        devInteractionMetrics.lastUpdated = Date()
    }

    func recordDevCommitToLinesChanged(milliseconds: Double, label: String) {
        guard isDevModeEnabled else { return }
        devInteractionMetrics.commitToLinesChangedMilliseconds = milliseconds
        devInteractionMetrics.commitToLinesChangedLabel = label
        devInteractionMetrics.lastUpdated = Date()
    }

    func recordDevLinesChangedToCacheDone(milliseconds: Double, label: String) {
        guard isDevModeEnabled else { return }
        devInteractionMetrics.linesChangedToCacheDoneMilliseconds = milliseconds
        devInteractionMetrics.linesChangedToCacheDoneLabel = label
        devInteractionMetrics.lastUpdated = Date()
    }

    func qualityIssues(for line: DialogueLine) -> [String] {
        var issues: [String] = []
        let speaker = line.speaker.trimmingCharacters(in: .whitespacesAndNewlines)
        let start = line.startTimecode.trimmingCharacters(in: .whitespacesAndNewlines)
        let end = line.endTimecode.trimmingCharacters(in: .whitespacesAndNewlines)

        if validateMissingSpeaker, speaker.isEmpty {
            issues.append("Chybejici charakter.")
        }
        if validateMissingStartTC, start.isEmpty {
            issues.append("Chybejici start TC.")
        }
        if validateMissingEndTC, end.isEmpty {
            issues.append("Chybejici end TC.")
        }
        if validateInvalidTC {
            let hasInvalidStart = !start.isEmpty && TimecodeService.seconds(from: start, fps: fps) == nil
            let hasInvalidEnd = !end.isEmpty && TimecodeService.seconds(from: end, fps: fps) == nil
            if hasInvalidStart || hasInvalidEnd {
                issues.append("Spatne zadany TC.")
            }
        }

        return issues
    }

    func issueLineCount() -> Int {
        lines.reduce(into: 0) { result, line in
            if !qualityIssues(for: line).isEmpty {
                result += 1
            }
        }
    }

    func speakerStatistics() -> [SpeakerStatistic] {
        if (speakerDatabaseNeedsRefresh || speakerDatabase.isEmpty), !lines.isEmpty, speakerDatabaseRebuildTask == nil {
            scheduleSpeakerDatabaseRebuild()
        }
        return speakerDatabase
    }

    private struct SpeakerAnalysisSnapshot: Sendable {
        let statistics: [SpeakerStatistic]
        let missingSpeakerCount: Int
    }

    private nonisolated static func analyzeSpeakers(in sourceLines: [DialogueLine]) -> SpeakerAnalysisSnapshot {
        struct Accumulator {
            var displaySpeaker: String
            var entries: Int
            var wordCount: Int
        }

        var buckets: [String: Accumulator] = [:]
        buckets.reserveCapacity(max(8, sourceLines.count / 4))
        var missingSpeakerCount = 0

        for line in sourceLines {
            let speakerTrimmed = line.speaker.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !speakerTrimmed.isEmpty else {
                missingSpeakerCount += 1
                continue
            }

            let key = SpeakerAppearanceService.normalizedSpeakerKey(speakerTrimmed)
            let words = countWords(in: line.text)
            if var existing = buckets[key] {
                existing.entries += 1
                existing.wordCount += words
                buckets[key] = existing
            } else {
                buckets[key] = Accumulator(
                    displaySpeaker: speakerTrimmed,
                    entries: 1,
                    wordCount: words
                )
            }
        }

        let statistics = buckets.values
            .map { item in
                SpeakerStatistic(
                    speaker: item.displaySpeaker,
                    entries: item.entries,
                    wordCount: item.wordCount
                )
            }
            .sorted { lhs, rhs in
                if lhs.entries != rhs.entries {
                    return lhs.entries > rhs.entries
                }
                return lhs.speaker.localizedCaseInsensitiveCompare(rhs.speaker) == .orderedAscending
            }

        return SpeakerAnalysisSnapshot(
            statistics: statistics,
            missingSpeakerCount: missingSpeakerCount
        )
    }

    private func rebuildSpeakerDatabase(from sourceLines: [DialogueLine]? = nil) {
        speakerDatabaseRebuildTask?.cancel()
        speakerDatabaseRebuildTask = nil
        speakerDatabaseNeedsRefresh = false
        let analysis = Self.analyzeSpeakers(in: sourceLines ?? lines)
        speakerDatabase = analysis.statistics
        missingSpeakerCount = analysis.missingSpeakerCount
    }

    private func scheduleSpeakerDatabaseRebuild() {
        if lines.isEmpty {
            rebuildSpeakerDatabase(from: [])
            return
        }

        speakerDatabaseNeedsRefresh = true
        speakerDatabaseRebuildTask?.cancel()
        let delay = editingLineID == nil
            ? speakerDatabaseRebuildDelayNanoseconds
            : max(speakerDatabaseRebuildDelayNanoseconds, 280_000_000)
        let snapshot = lines
        speakerDatabaseRebuildRevision &+= 1
        let revision = speakerDatabaseRebuildRevision

        speakerDatabaseRebuildTask = Task { [weak self, snapshot, revision] in
            guard let self else { return }
            try? await Task.sleep(nanoseconds: delay)
            guard !Task.isCancelled else { return }

            let analysis = await Task.detached(priority: .utility) {
                Self.analyzeSpeakers(in: snapshot)
            }.value

            guard !Task.isCancelled else { return }

            await MainActor.run {
                guard revision == self.speakerDatabaseRebuildRevision else { return }
                self.speakerDatabaseNeedsRefresh = false
                self.speakerDatabase = analysis.statistics
                self.missingSpeakerCount = analysis.missingSpeakerCount
                self.speakerDatabaseRebuildTask = nil
            }
        }
    }

    func chronologicalStartIssues() -> [ChronologicalStartIssue] {
        var issues: [ChronologicalStartIssue] = []
        issues.reserveCapacity(max(0, lines.count / 10))

        var previousValid: (line: DialogueLine, seconds: Double)?

        for line in lines {
            guard let currentSeconds = TimecodeService.seconds(from: line.startTimecode, fps: fps) else {
                continue
            }

            if
                let previousValid,
                currentSeconds < previousValid.seconds
            {
                issues.append(
                    ChronologicalStartIssue(
                        previousLineID: previousValid.line.id,
                        lineID: line.id,
                        previousLineIndex: previousValid.line.index,
                        lineIndex: line.index,
                        previousStartTimecode: previousValid.line.startTimecode,
                        startTimecode: line.startTimecode,
                        previousStartSeconds: previousValid.seconds,
                        startSeconds: currentSeconds
                    )
                )
            }

            previousValid = (line: line, seconds: currentSeconds)
        }

        return issues
    }

    @discardableResult
    func replaceInLine(lineID: DialogueLine.ID, query: String, replacement: String) -> Int {
        let target = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !target.isEmpty else { return 0 }
        guard let index = indexOfLine(withID: lineID) else { return 0 }

        let outcome = replacingOccurrences(in: lines[index].text, target: target, with: replacement)
        guard outcome.count > 0 else { return 0 }

        lines[index].text = outcome.value
        forceHistoryCheckpoint()
        return outcome.count
    }

    @discardableResult
    func replaceInAllLines(query: String, replacement: String, limitedTo lineIDs: Set<DialogueLine.ID>? = nil) -> Int {
        let target = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !target.isEmpty else { return 0 }

        var updated = lines
        var totalCount = 0

        for idx in updated.indices {
            if let lineIDs, !lineIDs.contains(updated[idx].id) {
                continue
            }
            let outcome = replacingOccurrences(in: updated[idx].text, target: target, with: replacement)
            if outcome.count > 0 {
                updated[idx].text = outcome.value
                totalCount += outcome.count
            }
        }

        guard totalCount > 0 else { return 0 }
        lines = updated
        forceHistoryCheckpoint()
        return totalCount
    }

    private func replacingOccurrences(in source: String, target: String, with replacement: String) -> (value: String, count: Int) {
        guard !target.isEmpty else { return (source, 0) }

        var output = ""
        var remainingRange: Range<String.Index>? = source.startIndex..<source.endIndex
        var replacedCount = 0

        while let searchRange = remainingRange,
            let match = source.range(
                of: target,
                options: [.caseInsensitive, .diacriticInsensitive],
                range: searchRange,
                locale: Locale(identifier: "cs_CZ")
            ) {
            output += source[searchRange.lowerBound..<match.lowerBound]
            output += replacement
            remainingRange = match.upperBound..<source.endIndex
            replacedCount += 1
        }

        if let trailing = remainingRange {
            output += source[trailing]
        }

        return (replacedCount > 0 ? output : source, replacedCount)
    }

    private nonisolated static func countWords(in text: String) -> Int {
        text.split(whereSeparator: { $0.isWhitespace }).count
    }

    func handleLinesDidChange() {
        guard !isApplyingHistoryState else { return }
        sanitizeSelectionForCurrentLines()
        let snapshot = lines
        let previous = lastObservedLines
        lastObservedLines = snapshot
        scheduleSpeakerDatabaseRebuild()

        if pendingBaselineLines == nil {
            pendingBaselineLines = lastCommittedLines
        }

        if let explicitHistoryEntry = pendingExplicitHistoryEntry {
            pendingExplicitHistoryEntry = nil
            let explicitChangeKind: LineChangeKind
            switch explicitHistoryEntry {
            case .insert, .delete, .move:
                explicitChangeKind = .structure
            case .lineUpdate(let change):
                explicitChangeKind = .singleLineMetadata(lineID: change.after.id)
            case .snapshot:
                explicitChangeKind = assessLineChanges(from: previous, to: snapshot).kind
            }
            lastLineChangeKind = explicitChangeKind
            if case .none = explicitChangeKind {
                scheduleAutosave()
                return
            }
            commitHistory(entry: explicitHistoryEntry, snapshot: snapshot)
            markProjectDirty()
            scheduleAutosave()
            return
        }

        if let fastAssessment = assessFastPathForActiveEditing(from: previous, to: snapshot) {
            lastLineChangeKind = fastAssessment.kind
            if fastAssessment.shouldCommitHistory {
                commitHistory(with: snapshot, changeKind: fastAssessment.kind)
            }
            if case .none = fastAssessment.kind {} else {
                markProjectDirty()
            }
            scheduleAutosave()
            return
        }

        let assessment = assessLineChanges(from: previous, to: snapshot)
        lastLineChangeKind = assessment.kind

        if assessment.shouldCommitHistory {
            commitHistory(with: snapshot, changeKind: assessment.kind)
        }
        if case .none = assessment.kind {} else {
            markProjectDirty()
        }

        scheduleAutosave()
    }

    private func assessFastPathForActiveEditing(from previous: [DialogueLine], to current: [DialogueLine]) -> ChangeAssessment? {
        guard let editingLineID else { return nil }
        guard previous.count == current.count, !previous.isEmpty else { return nil }
        guard let editingIndex = indexOfLine(withID: editingLineID) else { return nil }
        guard previous.indices.contains(editingIndex), current.indices.contains(editingIndex) else { return nil }

        let oldLine = previous[editingIndex]
        let newLine = current[editingIndex]
        guard oldLine.id == editingLineID, newLine.id == editingLineID else { return nil }

        // If non-text metadata changed, fall back to the full assessment.
        if oldLine.index != newLine.index ||
            oldLine.speaker != newLine.speaker ||
            oldLine.startTimecode != newLine.startTimecode ||
            oldLine.endTimecode != newLine.endTimecode {
            return nil
        }

        guard oldLine.text != newLine.text else {
            return ChangeAssessment(kind: .none, shouldCommitHistory: false)
        }

        return ChangeAssessment(
            kind: .singleLineText(lineID: editingLineID),
            shouldCommitHistory: isWordBoundaryTransition(old: oldLine.text, new: newLine.text)
        )
    }

    func consumeLastLineChangeKind() -> LineChangeKind {
        let value = lastLineChangeKind
        lastLineChangeKind = .none
        return value
    }

    private struct ChangeAssessment {
        let kind: LineChangeKind
        let shouldCommitHistory: Bool
    }

    private func assessLineChanges(from previous: [DialogueLine], to current: [DialogueLine]) -> ChangeAssessment {
        guard previous.count == current.count else {
            return ChangeAssessment(kind: .structure, shouldCommitHistory: true)
        }
        guard !previous.isEmpty else {
            return ChangeAssessment(kind: .none, shouldCommitHistory: false)
        }

        var textChangeLineID: DialogueLine.ID?
        var textChangeOld: String?
        var textChangeNew: String?
        var metadataChangeLineID: DialogueLine.ID?
        var changedLineCount = 0

        for idx in previous.indices {
            let oldLine = previous[idx]
            let newLine = current[idx]

            if oldLine.id != newLine.id {
                return ChangeAssessment(kind: .structure, shouldCommitHistory: true)
            }

            if oldLine.index != newLine.index ||
                oldLine.speaker != newLine.speaker ||
                oldLine.startTimecode != newLine.startTimecode ||
                oldLine.endTimecode != newLine.endTimecode {
                if metadataChangeLineID == nil {
                    metadataChangeLineID = newLine.id
                } else if metadataChangeLineID != newLine.id {
                    return ChangeAssessment(kind: .multiLine, shouldCommitHistory: true)
                }
                changedLineCount += 1
            }

            if oldLine.text != newLine.text {
                if textChangeLineID == nil {
                    textChangeLineID = newLine.id
                    textChangeOld = oldLine.text
                    textChangeNew = newLine.text
                } else if textChangeLineID != newLine.id {
                    return ChangeAssessment(kind: .multiLine, shouldCommitHistory: true)
                }
                changedLineCount += 1
            }
        }

        if changedLineCount == 0 {
            return ChangeAssessment(kind: .none, shouldCommitHistory: false)
        }

        if let metadataChangeLineID {
            return ChangeAssessment(kind: .singleLineMetadata(lineID: metadataChangeLineID), shouldCommitHistory: true)
        }

        if
            let lineID = textChangeLineID,
            let oldText = textChangeOld,
            let newText = textChangeNew
        {
            let shouldCommit = isWordBoundaryTransition(old: oldText, new: newText)
            return ChangeAssessment(kind: .singleLineText(lineID: lineID), shouldCommitHistory: shouldCommit)
        }

        return ChangeAssessment(kind: .multiLine, shouldCommitHistory: true)
    }

    private func isWordBoundaryTransition(old: String, new: String) -> Bool {
        if old == new { return false }

        let oldCount = old.count
        let newCount = new.count
        if abs(newCount - oldCount) > 1 {
            return true
        }

        if newCount > oldCount {
            guard new.hasPrefix(old) else { return true }
            let appended = String(new.dropFirst(oldCount))
            return appended.contains(where: isWordBoundaryCharacter)
        }

        if oldCount > newCount {
            guard old.hasPrefix(new) else { return true }
            let removed = String(old.dropFirst(newCount))
            return removed.contains(where: isWordBoundaryCharacter)
        }

        return true
    }

    private func isWordBoundaryCharacter(_ ch: Character) -> Bool {
        if ch.isWhitespace {
            return true
        }
        for scalar in ch.unicodeScalars {
            if CharacterSet.punctuationCharacters.contains(scalar) {
                return true
            }
            if CharacterSet.symbols.contains(scalar) {
                return true
            }
        }
        return false
    }

    func forceHistoryCheckpoint() {
        flushPendingHistory()
    }

    func undo() {
        let beforeCount = lines.count
        let beforeSummaries = currentLineSummaryByID()
        let beforeSelection = captureDebugSelectionSnapshot(using: beforeSummaries)

        flushPendingHistory()
        guard let entry = undoStack.popLast() else { return }

        let currentSnapshot = lines
        var updated = currentSnapshot
        let applied: Bool
        switch entry {
        case .snapshot(let previous):
            updated = previous
            redoStack.append(.snapshot(currentSnapshot))
            applied = true
        case .lineUpdate(let change):
            applied = applyLineUpdate(change, in: &updated, useAfterState: false)
            if applied {
                redoStack.append(entry)
            }
        case .insert(let insertedLines, _):
            applied = deleteLines(matching: insertedLines.map(\.id), from: &updated)
            if applied {
                redoStack.append(entry)
            }
        case .delete(let items):
            applied = restoreDeletedLines(items, in: &updated)
            if applied {
                redoStack.append(entry)
            }
        case .move(let lineID, let fromIndex, _):
            applied = moveLine(withID: lineID, to: fromIndex, in: &updated)
            if applied {
                redoStack.append(entry)
            }
        }

        guard applied else {
            pendingBaselineLines = nil
            updateHistoryFlags()
            return
        }

        isApplyingHistoryState = true
        lines = updated
        isApplyingHistoryState = false
        rebuildSpeakerDatabase(from: updated)

        lastCommittedLines = updated
        lastObservedLines = updated
        pendingBaselineLines = nil
        pendingExplicitHistoryEntry = nil
        rebuildLineIndexCache()
        trimHistoryIfNeeded()
        updateHistoryFlags()
        markProjectDirty()
        scheduleAutosave()

        let afterSummaries = currentLineSummaryByID()
        let afterSelection = captureDebugSelectionSnapshot(using: afterSummaries)
        logStructureDebug(
            event: "undo",
            beforeCount: beforeCount,
            afterCount: lines.count,
            beforeSelection: beforeSelection,
            afterSelection: afterSelection
        )
    }

    func redo() {
        let beforeCount = lines.count
        let beforeSummaries = currentLineSummaryByID()
        let beforeSelection = captureDebugSelectionSnapshot(using: beforeSummaries)

        flushPendingHistory()
        guard let entry = redoStack.popLast() else { return }

        let currentSnapshot = lines
        var updated = currentSnapshot
        let applied: Bool
        switch entry {
        case .snapshot(let next):
            updated = next
            undoStack.append(.snapshot(currentSnapshot))
            applied = true
        case .lineUpdate(let change):
            applied = applyLineUpdate(change, in: &updated, useAfterState: true)
            if applied {
                undoStack.append(entry)
            }
        case .insert(let insertedLines, let index):
            applied = insertLines(insertedLines, at: index, in: &updated)
            if applied {
                undoStack.append(entry)
            }
        case .delete(let items):
            applied = deleteLines(matching: items.map(\.line.id), from: &updated)
            if applied {
                undoStack.append(entry)
            }
        case .move(let lineID, _, let toIndex):
            applied = moveLine(withID: lineID, to: toIndex, in: &updated)
            if applied {
                undoStack.append(entry)
            }
        }

        guard applied else {
            pendingBaselineLines = nil
            updateHistoryFlags()
            return
        }

        isApplyingHistoryState = true
        lines = updated
        isApplyingHistoryState = false
        rebuildSpeakerDatabase(from: updated)

        lastCommittedLines = updated
        lastObservedLines = updated
        pendingBaselineLines = nil
        pendingExplicitHistoryEntry = nil
        rebuildLineIndexCache()
        trimHistoryIfNeeded()
        updateHistoryFlags()
        markProjectDirty()
        scheduleAutosave()

        let afterSummaries = currentLineSummaryByID()
        let afterSelection = captureDebugSelectionSnapshot(using: afterSummaries)
        logStructureDebug(
            event: "redo",
            beforeCount: beforeCount,
            afterCount: lines.count,
            beforeSelection: beforeSelection,
            afterSelection: afterSelection
        )
    }

    func togglePlayPause() {
        guard player.currentItem != nil else { return }
        if player.timeControlStatus == .playing {
            logPlaybackDebugEvent("PAUSE_REQUESTED", source: "toggle")
            player.pause()
        } else {
            let queuedUntilSeekEnd = requestPlaybackResumeAfterCurrentSeekIfNeeded()
            logPlaybackDebugEvent(
                "PLAY_REQUESTED",
                source: "toggle",
                extraFields: [("queuedUntilSeekEnd", playbackDebugBoolean(queuedUntilSeekEnd))]
            )
            if !queuedUntilSeekEnd {
                player.play()
            }
        }
    }

    func setPlaybackSeekStepSeconds(_ value: Double) {
        playbackSeekStepSeconds = value
    }

    func setLeftChannelMuted(_ muted: Bool) {
        updateChannelMuteState(muteLeftChannel: muted, muteRightChannel: isRightChannelMuted)
    }

    func setRightChannelMuted(_ muted: Bool) {
        updateChannelMuteState(muteLeftChannel: isLeftChannelMuted, muteRightChannel: muted)
    }

    func setVideoAudioMuted(_ muted: Bool) {
        guard isVideoAudioMuted != muted else { return }
        isVideoAudioMuted = muted
        notifyMetadataDidChange()
    }

    func setExternalAudioMuted(_ muted: Bool) {
        guard isExternalAudioMuted != muted else { return }
        isExternalAudioMuted = muted
        notifyMetadataDidChange()
    }

    var canControlStereoChannels: Bool {
        detectedAudioChannelCount >= 2
    }

    var hasExternalAudioTrack: Bool {
        playbackSourceState?.externalAudioTrackID != nil
    }

    var externalAudioDisplayName: String? {
        sourceExternalAudioURL?.lastPathComponent
    }

    private func currentRequestedVideoAudioVariant(
        muteLeftChannel: Bool? = nil,
        muteRightChannel: Bool? = nil
    ) -> VideoAudioChannelVariant {
        VideoAudioChannelVariant(
            muteLeftChannel: muteLeftChannel ?? isLeftChannelMuted,
            muteRightChannel: muteRightChannel ?? isRightChannelMuted
        )
    }

    private func updateChannelMuteState(
        muteLeftChannel: Bool,
        muteRightChannel: Bool
    ) {
        guard
            muteLeftChannel != isLeftChannelMuted ||
            muteRightChannel != isRightChannelMuted
        else {
            return
        }

        let previousLeftMute = isLeftChannelMuted
        let previousRightMute = isRightChannelMuted
        isLeftChannelMuted = muteLeftChannel
        isRightChannelMuted = muteRightChannel
        notifyMetadataDidChange()

        guard let videoURL else { return }
        let requestedVariant = currentRequestedVideoAudioVariant(
            muteLeftChannel: muteLeftChannel,
            muteRightChannel: muteRightChannel
        )
        rebuildPlaybackSource(
            videoURL: videoURL,
            externalAudioURL: sourceExternalAudioURL,
            videoAudioVariant: requestedVariant,
            preserveCurrentPlaybackPosition: true,
            queueWaveformRebuild: false,
            fallbackWithoutExternalAudio: true,
            alertPrefix: String(localized: "alert.channel_switch_failed", bundle: .appBundle),
            tracksChannelPreparationState: true,
            onFailure: { [weak self] in
                guard let self else { return }
                self.isLeftChannelMuted = previousLeftMute
                self.isRightChannelMuted = previousRightMute
            }
        )
    }

    func seekBackwardStep() {
        seekRelative(seconds: -playbackSeekStepSeconds, source: "step_backward")
    }

    func seekForwardStep() {
        seekRelative(seconds: playbackSeekStepSeconds, source: "step_forward")
    }

    func rewindOrReplayActiveLine() {
        guard player.currentItem != nil else { return }

        let targetID = editingLineID ?? highlightedLineID ?? selectedLineID
        guard
            let targetID,
            let targetIndex = indexOfLine(withID: targetID),
            let startTimelineSeconds = TimecodeService.seconds(from: lines[targetIndex].startTimecode, fps: fps)
        else {
            alertMessage = String(localized: "alert.loop_no_active_line", bundle: .appBundle)
            return
        }
        let startPlaybackSeconds = playbackSeconds(fromTimelineSeconds: startTimelineSeconds)
        let replayPreroll = isReplayPrerollEnabled ? max(0, playbackSeekStepSeconds) : 0
        let replayStartPlaybackSeconds = max(0, startPlaybackSeconds - replayPreroll)

        let line = lines[targetIndex]

        selectedLineID = line.id
        selectedLineIDs = [line.id]
        selectionAnchorLineID = line.id

        let current = player.currentTime().seconds
        let isNearStart = current.isFinite && abs(current - replayStartPlaybackSeconds) <= 0.08
        let isPlaying = player.timeControlStatus == .playing

        if isNearStart && !isPlaying {
            logPlaybackDebugEvent("PLAY_REQUESTED", source: "replay")
            player.play()
            return
        }

        logPlaybackDebugEvent("PAUSE_REQUESTED", source: "replay")
        player.pause()
        seek(to: replayStartPlaybackSeconds, source: "replay")
    }

    func setLoopEnabled(_ enabled: Bool) {
        if !enabled {
            isLoopEnabled = false
            return
        }

        guard highlightedLineID != nil else {
            alertMessage = String(localized: "alert.loop_no_line_selected", bundle: .appBundle)
            isLoopEnabled = false
            return
        }

        guard let range = currentLoopRange() else {
            alertMessage = String(localized: "alert.loop_invalid_start_tc", bundle: .appBundle)
            isLoopEnabled = false
            return
        }

        isLoopEnabled = true
        logPlaybackDebugEvent("PLAY_REQUESTED", source: "loop_start")
        seek(to: range.lowerBound, source: "loop_start", resumeAfterSeek: true)
    }

    func moveSelection(step: Int, extendSelection: Bool = false) {
        guard !lines.isEmpty else { return }
        guard editingLineID == nil else { return }

        let currentIndex: Int
        if let selectedLineID, let idx = indexOfLine(withID: selectedLineID) {
            currentIndex = idx
        } else {
            currentIndex = step > 0 ? -1 : lines.count
        }

        let nextIndex = max(0, min(lines.count - 1, currentIndex + step))
        let nextLine = lines[nextIndex]
        if extendSelection {
            extendSelectionRange(to: nextLine)
        } else {
            selectedLineID = nextLine.id
            selectedLineIDs = [nextLine.id]
            selectionAnchorLineID = nextLine.id
            highlightedLineID = nextLine.id
        }

        if let seconds = TimecodeService.seconds(from: nextLine.startTimecode, fps: fps) {
            seekToTimeline(seconds: seconds, source: "selection_seek")
        }
    }

    private func extendSelectionRange(to line: DialogueLine) {
        guard let targetIndex = indexOfLine(withID: line.id) else {
            return
        }

        let anchorID = selectionAnchorLineID ?? selectedLineID ?? line.id
        guard let anchorIndex = indexOfLine(withID: anchorID) else {
            selectedLineID = line.id
            selectedLineIDs = [line.id]
            selectionAnchorLineID = line.id
            highlightedLineID = line.id
            if editingLineID != line.id {
                editingLineID = nil
            }
            return
        }

        let lower = min(anchorIndex, targetIndex)
        let upper = max(anchorIndex, targetIndex)
        let rangeIDs = Set(lines[lower...upper].map(\.id))

        selectedLineID = line.id
        selectedLineIDs = rangeIDs
        selectionAnchorLineID = anchorID
        highlightedLineID = line.id
        if editingLineID != line.id {
            editingLineID = nil
        }
    }

    func handlePlaybackTick(currentSeconds: Double) {
        guard isLoopEnabled else { return }
        guard !isLoopSeekInFlight else { return }
        guard let range = currentLoopRange() else { return }

        if currentSeconds >= range.upperBound {
            isLoopSeekInFlight = true
            seek(to: range.lowerBound, source: "loop_jump", intent: .loopJump) { [weak self] _ in
                Task { @MainActor in
                    guard let self else { return }
                    self.isLoopSeekInFlight = false
                    if self.isLoopEnabled {
                        self.logPlaybackDebugEvent("PLAY_REQUESTED", source: "loop_jump")
                        self.player.play()
                    }
                }
            }
        }
    }

    private func seek(
        to seconds: Double,
        source: String,
        intent: SeekIntent = .interactiveJump,
        resumeAfterSeek: Bool = false,
        completion: (@Sendable (Bool) -> Void)? = nil
    ) {
        guard player.currentItem != nil else {
            completion?(false)
            return
        }

        let time = CMTime(seconds: max(0, seconds), preferredTimescale: 600)
        let tolerance = seekTolerance(for: intent)
        let previousActiveSeekGeneration = activeSeekGeneration
        let carryForwardResume = resumePlaybackAfterSeekGeneration == previousActiveSeekGeneration
        activeSeekGeneration &+= 1
        let seekGeneration = activeSeekGeneration
        if resumeAfterSeek || carryForwardResume {
            resumePlaybackAfterSeekGeneration = seekGeneration
        }
        logPlaybackDebugEvent(
            "SEEK_BEGIN",
            source: source,
            seekGeneration: seekGeneration,
            currentSecondsOverride: max(0, seconds),
            extraFields: [
                ("intent", String(describing: intent)),
                ("resumeAfterSeek", playbackDebugBoolean(resumeAfterSeek)),
                ("carryForwardResume", playbackDebugBoolean(carryForwardResume))
            ]
        )

        player.seek(to: time, toleranceBefore: tolerance, toleranceAfter: tolerance) { [weak self] finished in
            Task { @MainActor [weak self] in
                guard let self else {
                    completion?(finished)
                    return
                }

                if seekGeneration > self.completedSeekGeneration {
                    self.completedSeekGeneration = seekGeneration
                }

                let shouldResumePlayback = finished &&
                    seekGeneration == self.activeSeekGeneration &&
                    self.resumePlaybackAfterSeekGeneration == seekGeneration
                if self.resumePlaybackAfterSeekGeneration == seekGeneration {
                    self.resumePlaybackAfterSeekGeneration = nil
                }

                self.logPlaybackDebugEvent(
                    "SEEK_END",
                    source: source,
                    seekGeneration: seekGeneration,
                    currentSecondsOverride: self.player.currentTime().seconds,
                    extraFields: [
                        ("finished", self.playbackDebugBoolean(finished)),
                        ("willResumePlayback", self.playbackDebugBoolean(shouldResumePlayback))
                    ]
                )

                completion?(finished)

                if shouldResumePlayback {
                    self.logPlaybackDebugEvent("PLAY_REQUESTED", source: "\(source)_resume", seekGeneration: seekGeneration)
                    self.player.play()
                }
            }
        }
    }

    private func scheduleSelectionSeek(seconds: Double, for lineID: DialogueLine.ID) {
        cancelPendingSelectionSeek()
        pendingSelectionSeekLineID = lineID
        pendingSelectionSeekTask = Task { @MainActor [weak self] in
            guard let self else { return }
            try? await Task.sleep(nanoseconds: self.pointerSelectionSeekDebounceNanoseconds)
            guard !Task.isCancelled else { return }
            guard self.pendingSelectionSeekLineID == lineID else { return }
            guard self.selectedLineID == lineID else { return }
            guard self.editingLineID == nil else { return }
            self.pendingSelectionSeekTask = nil
            self.pendingSelectionSeekLineID = nil
            self.seekToTimeline(seconds: seconds, source: "selection_seek")
        }
    }

    private func cancelPendingSelectionSeek() {
        pendingSelectionSeekTask?.cancel()
        pendingSelectionSeekTask = nil
        pendingSelectionSeekLineID = nil
    }

    private func isLineStrictlySingleSelected(_ lineID: DialogueLine.ID) -> Bool {
        selectedLineID == lineID &&
            highlightedLineID == lineID &&
            selectedLineIDs.count == 1 &&
            selectedLineIDs.contains(lineID) &&
            selectionAnchorLineID == lineID
    }

    private func seekToTimeline(seconds: Double, source: String = "selection_seek") {
        seek(to: playbackSeconds(fromTimelineSeconds: seconds), source: source)
    }

    private func seekRelative(seconds: Double, source: String) {
        guard player.currentItem != nil else { return }
        let current = player.currentTime().seconds
        let target = max(0, (current.isFinite ? current : 0) + seconds)
        seek(to: target, source: source)
    }

    private func seekTolerance(for intent: SeekIntent) -> CMTime {
        switch intent {
        case .frameAccurate:
            return .zero
        case .loopJump:
            let oneFrame = max(1.0 / max(fps, 1), 0.02)
            return CMTime(seconds: oneFrame, preferredTimescale: 600)
        case .interactiveJump:
            // Lower decoder pressure during frequent jumps (selection/replay/scrub shortcuts).
            let oneFrame = 1.0 / max(fps, 1)
            let seconds = isLightModeEnabled
                ? max(oneFrame * 2.0, 0.08)
                : max(oneFrame * 1.0, 0.04)
            return CMTime(seconds: seconds, preferredTimescale: 600)
        }
    }

    private func installPlayerStateObservation() {
        playerTimeControlObservation?.invalidate()
        playerTimeControlObservation = player.observe(
            \.timeControlStatus,
            options: [.initial, .new]
        ) { [weak self] player, _ in
            Task { @MainActor [weak self] in
                guard let self else { return }
                self.isPlaybackActive = player.timeControlStatus == .playing
                self.logPlaybackDebugEvent("PLAYER_TIME_CONTROL_CHANGED", source: "kvo")
            }
        }
    }

    private static func sanitizePlaybackSeekStepSeconds(_ value: Double) -> Double {
        guard value.isFinite else {
            return defaultPlaybackSeekStepSeconds
        }
        if value <= 0 {
            return defaultPlaybackSeekStepSeconds
        }
        return max(minPlaybackSeekStepSeconds, min(maxPlaybackSeekStepSeconds, value))
    }

    private static func sanitizeVideoOffsetSeconds(_ value: Double) -> Double {
        guard value.isFinite else {
            return 0
        }
        return max(minVideoOffsetSeconds, min(maxVideoOffsetSeconds, value))
    }

    private static func sanitizeReplicaTextFontSize(_ value: Double) -> Double {
        guard value.isFinite else {
            return defaultReplicaTextFontSize
        }
        return max(minReplicaTextFontSize, min(maxReplicaTextFontSize, value))
    }

    func playbackSeconds(fromTimelineSeconds seconds: Double) -> Double {
        let timeline = max(0, seconds.isFinite ? seconds : 0)
        return max(0, timeline + videoOffsetSeconds)
    }

    func timelineSeconds(fromPlaybackSeconds seconds: Double) -> Double {
        let playback = max(0, seconds.isFinite ? seconds : 0)
        return max(0, playback - videoOffsetSeconds)
    }

    func currentInsertionStartTimecode(playbackSecondsOverride: Double? = nil) -> String? {
        currentPlaybackTimecodeString(
            hideFrames: false,
            playbackSecondsOverride: playbackSecondsOverride
        )
    }

    private func currentLoopRange() -> ClosedRange<Double>? {
        guard
            let highlightedLineID,
            let lineIndex = indexOfLine(withID: highlightedLineID),
            let startTimeline = TimecodeService.seconds(from: lines[lineIndex].startTimecode, fps: fps)
        else {
            return nil
        }

        let line = lines[lineIndex]
        let parsedEndTimeline = TimecodeService.seconds(from: line.endTimecode, fps: fps)
        let endTimeline = max(startTimeline + 0.05, parsedEndTimeline ?? (startTimeline + 5))
        let start = playbackSeconds(fromTimelineSeconds: startTimeline)
        let end = max(start + 0.05, playbackSeconds(fromTimelineSeconds: endTimeline))
        return start...end
    }

    private func hourMinutePrefix(from rawTimecode: String) -> String? {
        let trimmed = rawTimecode.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        // Normalize parseable timecodes first so `mm:ss` inputs also yield `HH:MM:`.
        let normalizedSource: String
        if let seconds = TimecodeService.seconds(from: trimmed, fps: fps) {
            normalizedSource = TimecodeService.timecode(from: seconds, fps: fps)
        } else {
            normalizedSource = trimmed
        }

        let range = NSRange(normalizedSource.startIndex..<normalizedSource.endIndex, in: normalizedSource)
        guard
            let match = hourMinutePrefixRegex.firstMatch(in: normalizedSource, range: range),
            match.numberOfRanges > 2,
            let hourRange = Range(match.range(at: 1), in: normalizedSource),
            let minuteRange = Range(match.range(at: 2), in: normalizedSource)
        else {
            return nil
        }

        let hour = String(normalizedSource[hourRange])
        let minute = String(normalizedSource[minuteRange])
        return "\(hour):\(minute):"
    }

    private func resetHistory(with snapshot: [DialogueLine]) {
        undoStack.removeAll()
        redoStack.removeAll()
        lastCommittedLines = snapshot
        lastObservedLines = snapshot
        pendingBaselineLines = nil
        pendingExplicitHistoryEntry = nil
        rebuildLineIndexCache()
        updateHistoryFlags()
    }

    private func flushPendingHistory() {
        commitHistory(with: lines, changeKind: .none)
    }

    private func commitHistory(with snapshot: [DialogueLine], changeKind: LineChangeKind) {
        guard !isApplyingHistoryState else { return }
        let baseline = pendingBaselineLines ?? lastCommittedLines
        guard baseline != snapshot else {
            pendingBaselineLines = nil
            lastCommittedLines = snapshot
            lastObservedLines = snapshot
            pendingExplicitHistoryEntry = nil
            return
        }
        let implicitEntry = makeImplicitHistoryEntry(
            baseline: baseline,
            snapshot: snapshot,
            changeKind: changeKind
        ) ?? .snapshot(baseline)
        commitHistory(entry: implicitEntry, snapshot: snapshot)
    }

    private func commitHistory(entry: HistoryEntry, snapshot: [DialogueLine]) {
        guard !isApplyingHistoryState else { return }

        defer {
            pendingBaselineLines = nil
            lastCommittedLines = snapshot
            lastObservedLines = snapshot
            pendingExplicitHistoryEntry = nil
            rebuildLineIndexCache()
            updateHistoryFlags()
        }

        undoStack.append(entry)
        trimHistoryIfNeeded()
        redoStack.removeAll()
    }

    private func trimHistoryIfNeeded() {
        if undoStack.count > historyLimit {
            undoStack.removeFirst(undoStack.count - historyLimit)
        }
        if redoStack.count > historyLimit {
            redoStack.removeFirst(redoStack.count - historyLimit)
        }
    }

    private func updateHistoryFlags() {
        canUndo = !undoStack.isEmpty
        canRedo = !redoStack.isEmpty
    }

    private func normalizeLineIndices(_ lines: inout [DialogueLine]) {
        for idx in lines.indices {
            lines[idx].index = idx + 1
        }
    }

    private func makeImplicitHistoryEntry(
        baseline: [DialogueLine],
        snapshot: [DialogueLine],
        changeKind: LineChangeKind
    ) -> HistoryEntry? {
        switch changeKind {
        case .singleLineText(let lineID), .singleLineMetadata(let lineID):
            guard
                let baselineIndex = baseline.firstIndex(where: { $0.id == lineID }),
                let snapshotIndex = snapshot.firstIndex(where: { $0.id == lineID }),
                baseline.indices.contains(baselineIndex),
                snapshot.indices.contains(snapshotIndex)
            else {
                return nil
            }

            let before = baseline[baselineIndex]
            let after = snapshot[snapshotIndex]
            guard before != after else { return nil }
            return .lineUpdate(change: LineUpdateChange(before: before, after: after))
        case .none, .structure, .multiLine:
            return nil
        }
    }

    private func applyLineUpdate(
        _ change: LineUpdateChange,
        in lines: inout [DialogueLine],
        useAfterState: Bool
    ) -> Bool {
        let targetID = change.after.id
        guard let index = lines.firstIndex(where: { $0.id == targetID }) else {
            return false
        }

        let replacementSource = useAfterState ? change.after : change.before
        var replacement = replacementSource
        replacement.index = lines[index].index
        lines[index] = replacement
        return true
    }

    private func insertLines(_ insertedLines: [DialogueLine], at index: Int, in lines: inout [DialogueLine]) -> Bool {
        guard !insertedLines.isEmpty else { return false }
        let existingIDs = Set(lines.map(\.id))
        let deduplicated = insertedLines.filter { !existingIDs.contains($0.id) }
        guard !deduplicated.isEmpty else { return false }
        let insertionIndex = max(0, min(lines.count, index))
        lines.insert(contentsOf: deduplicated, at: insertionIndex)
        normalizeLineIndices(&lines)
        return true
    }

    private func restoreDeletedLines(_ items: [DeletedLineChange], in lines: inout [DialogueLine]) -> Bool {
        guard !items.isEmpty else { return false }
        let sortedItems = items.sorted { $0.index < $1.index }
        var insertedAny = false
        for item in sortedItems {
            guard !lines.contains(where: { $0.id == item.line.id }) else { continue }
            let insertionIndex = max(0, min(lines.count, item.index))
            lines.insert(item.line, at: insertionIndex)
            insertedAny = true
        }
        if insertedAny {
            normalizeLineIndices(&lines)
        }
        return insertedAny
    }

    private func deleteLines(matching ids: [DialogueLine.ID], from lines: inout [DialogueLine]) -> Bool {
        let idSet = Set(ids)
        let previousCount = lines.count
        lines.removeAll { idSet.contains($0.id) }
        guard lines.count != previousCount else { return false }
        normalizeLineIndices(&lines)
        return true
    }

    private func moveLine(withID lineID: DialogueLine.ID, to targetIndex: Int, in lines: inout [DialogueLine]) -> Bool {
        guard let sourceIndex = lines.firstIndex(where: { $0.id == lineID }) else {
            return false
        }

        let moving = lines.remove(at: sourceIndex)
        let destinationIndex = max(0, min(lines.count, targetIndex))
        lines.insert(moving, at: destinationIndex)
        normalizeLineIndices(&lines)
        return sourceIndex != destinationIndex
    }

    private func apply(project: DubbingProjectFile) {
        applySpeakerColorOverrides(project.settings?.speakerColorOverridesByKey)
        apply(projectSettings: project.settings)

        documentTitle = project.documentTitle
        fps = Self.sanitizedFPS(project.fps)
        lines = project.lines
        rebuildSpeakerDatabase(from: project.lines)

        if let savedSelection = project.selectedLineID, indexOfLine(withID: savedSelection) != nil {
            selectedLineID = savedSelection
        } else {
            selectedLineID = lines.first?.id
        }
        if let selectedLineID {
            selectedLineIDs = [selectedLineID]
            selectionAnchorLineID = selectedLineID
        } else {
            selectedLineIDs = []
            selectionAnchorLineID = nil
        }

        if let savedHighlight = project.highlightedLineID, indexOfLine(withID: savedHighlight) != nil {
            highlightedLineID = savedHighlight
        } else {
            highlightedLineID = selectedLineID
        }
        pendingRestoreLineID = selectedLineID

        editingLineID = nil
        isLoopEnabled = false
        sourceWordURL = project.sourceWordPath.flatMap { URL(fileURLWithPath: $0) }
        pendingPlaybackRestoreTimelineSeconds = project.playbackPositionSeconds
        let restoredExternalAudioURL = project.sourceExternalAudioPath.flatMap { URL(fileURLWithPath: $0) }

        if let videoPath = project.sourceVideoPath {
            let restoredVideoURL = URL(fileURLWithPath: videoPath)
            if FileManager.default.fileExists(atPath: restoredVideoURL.path) {
                let externalAudioURL: URL?
                if let restoredExternalAudioURL {
                    if FileManager.default.fileExists(atPath: restoredExternalAudioURL.path) {
                        externalAudioURL = restoredExternalAudioURL
                    } else {
                        alertMessage = String(localized: "alert.external_audio_restored_without_file", bundle: .appBundle)
                        externalAudioURL = nil
                    }
                } else {
                    externalAudioURL = nil
                }

                rebuildPlaybackSource(
                    videoURL: restoredVideoURL,
                    externalAudioURL: externalAudioURL,
                    videoAudioVariant: .stereo,
                    preserveCurrentPlaybackPosition: false,
                    queueWaveformRebuild: true,
                    fallbackWithoutExternalAudio: true,
                    alertPrefix: String(localized: "alert.project_opened_playback_failed", bundle: .appBundle)
                )
            } else {
                resetPlaybackState(alertMessage: String(localized: "alert.project_opened_video_missing", bundle: .appBundle))
            }
        } else {
            resetPlaybackState()
        }

        resetHistory(with: lines)
        markAutosaveStateAsClean()
    }

    private func apply(snapshot: AutosaveSnapshot) {
        applySpeakerColorOverrides(snapshot.speakerColorOverridesByKey)
        documentTitle = snapshot.documentTitle
        fps = Self.sanitizedFPS(snapshot.fps)
        lines = snapshot.lines
        rebuildSpeakerDatabase(from: snapshot.lines)

        if let savedSelection = snapshot.selectedLineID, indexOfLine(withID: savedSelection) != nil {
            selectedLineID = savedSelection
        } else {
            selectedLineID = lines.first?.id
        }
        if let selectedLineID {
            selectedLineIDs = [selectedLineID]
            selectionAnchorLineID = selectedLineID
        } else {
            selectedLineIDs = []
            selectionAnchorLineID = nil
        }

        if let savedHighlight = snapshot.highlightedLineID, indexOfLine(withID: savedHighlight) != nil {
            highlightedLineID = savedHighlight
        } else {
            highlightedLineID = selectedLineID
        }
        pendingRestoreLineID = selectedLineID

        editingLineID = nil
        isLoopEnabled = false
        sourceWordURL = snapshot.sourceWordPath.flatMap { URL(fileURLWithPath: $0) }
        if let muteVideoAudio = snapshot.muteVideoAudio {
            isVideoAudioMuted = muteVideoAudio
        }
        if let muteExternalAudio = snapshot.muteExternalAudio {
            isExternalAudioMuted = muteExternalAudio
        }
        let restoredExternalAudioURL = snapshot.sourceExternalAudioPath.flatMap { URL(fileURLWithPath: $0) }

        if let videoPath = snapshot.sourceVideoPath {
            let restoredVideoURL = URL(fileURLWithPath: videoPath)
            if FileManager.default.fileExists(atPath: restoredVideoURL.path) {
                let externalAudioURL: URL?
                if let restoredExternalAudioURL {
                    if FileManager.default.fileExists(atPath: restoredExternalAudioURL.path) {
                        externalAudioURL = restoredExternalAudioURL
                    } else {
                        alertMessage = String(localized: "alert.autosave_restored_without_external", bundle: .appBundle)
                        externalAudioURL = nil
                    }
                } else {
                    externalAudioURL = nil
                }

                rebuildPlaybackSource(
                    videoURL: restoredVideoURL,
                    externalAudioURL: externalAudioURL,
                    videoAudioVariant: .stereo,
                    preserveCurrentPlaybackPosition: false,
                    queueWaveformRebuild: true,
                    fallbackWithoutExternalAudio: true,
                    alertPrefix: String(localized: "alert.autosave_restored_playback_failed", bundle: .appBundle)
                )
            } else {
                resetPlaybackState(alertMessage: String(localized: "alert.autosave_restored_video_missing", bundle: .appBundle))
            }
        } else {
            resetPlaybackState()
        }

        resetHistory(with: lines)
        markAutosaveStateAsClean()
        lastAutosaveDate = snapshot.savedAt
    }

    private func scheduleAutosave(immediate: Bool = false) {
        autosaveTask?.cancel()
        autosaveTask = Task { [weak self] in
            guard let self else { return }
            if !immediate {
                try? await Task.sleep(nanoseconds: currentAutosaveDelayNanoseconds())
            }
            guard !Task.isCancelled else { return }
            await performAutosaveIfNeeded()
        }
    }

    private func currentAutosaveDelayNanoseconds() -> UInt64 {
        if editingLineID != nil {
            return autosaveDelayWhileEditingNanoseconds
        }
        switch lastLineChangeKind {
        case .structure, .multiLine:
            return autosaveDelayForStructureNanoseconds
        case .singleLineText, .singleLineMetadata, .none:
            return autosaveDelayNanoseconds
        }
    }

    private func performAutosaveIfNeeded() async {
        guard autosaveRevision != lastAutosavedRevision else {
            return
        }

        guard let snapshot = buildAutosaveSnapshot() else {
            lastAutosavedRevision = autosaveRevision
            return
        }

        do {
            try await autosaveService.saveSnapshot(snapshot)
            lastAutosavedRevision = autosaveRevision
            lastAutosaveDate = snapshot.savedAt
        } catch {
            alertMessage = String(format: String(localized: "alert.autosave_failed", bundle: .appBundle), error.localizedDescription)
        }
    }

    private func buildAutosaveSnapshot() -> AutosaveSnapshot? {
        guard !lines.isEmpty || videoURL != nil else {
            return nil
        }

        return AutosaveSnapshot(
            savedAt: Date(),
            documentTitle: documentTitle,
            fps: fps,
            lines: lines,
            selectedLineID: selectedLineID,
            highlightedLineID: highlightedLineID,
            sourceWordPath: sourceWordURL?.path,
            sourceVideoPath: videoURL?.path,
            sourceExternalAudioPath: sourceExternalAudioURL?.path,
            muteVideoAudio: isVideoAudioMuted,
            muteExternalAudio: isExternalAudioMuted,
            speakerColorOverridesByKey: speakerColorOverridesByKey.isEmpty ? nil : speakerColorOverridesByKey
        )
    }

    private func buildCurrentProjectFile() -> DubbingProjectFile {
        DubbingProjectFile(
            documentTitle: documentTitle,
            fps: fps,
            lines: lines,
            selectedLineID: selectedLineID,
            highlightedLineID: highlightedLineID,
            playbackPositionSeconds: currentTimelinePlaybackSeconds(),
            sourceWordPath: sourceWordURL?.path,
            sourceVideoPath: videoURL?.path,
            sourceExternalAudioPath: sourceExternalAudioURL?.path,
            settings: buildProjectSettingsSnapshot()
        )
    }

    private func buildBugReportEditorState() -> BugReportEditorState {
        BugReportEditorState(
            documentTitle: documentTitle,
            lineCount: lines.count,
            selectedLineCount: selectedLineIDs.count,
            fps: fps,
            playbackPositionSeconds: currentTimelinePlaybackSeconds(),
            isLoopEnabled: isLoopEnabled,
            isPlaybackActive: isPlaybackActive,
            isTimecodeModeEnabled: isTimecodeModeEnabled,
            timecodeCaptureTarget: timecodeCaptureTarget.rawValue,
            playbackSeekStepSeconds: playbackSeekStepSeconds,
            videoOffsetSeconds: videoOffsetSeconds,
            isReplayPrerollEnabled: isReplayPrerollEnabled,
            isLightModeEnabled: isLightModeEnabled,
            showValidationIssues: showValidationIssues,
            showOnlyIssues: showOnlyIssues,
            validateMissingSpeaker: validateMissingSpeaker,
            validateMissingStartTC: validateMissingStartTC,
            validateMissingEndTC: validateMissingEndTC,
            validateInvalidTC: validateInvalidTC,
            currentProjectPath: currentProjectURL?.path,
            sourceWordPath: sourceWordURL?.path,
            sourceVideoPath: videoURL?.path,
            selectedLine: selectedLineForBugReportContext(),
            highlightedLine: lineContextForBugReport(highlightedLineID),
            editingLine: lineContextForBugReport(editingLineID)
        )
    }

    private func selectedLineForBugReportContext() -> BugReportLineContext? {
        if let selectedLineID, let context = lineContextForBugReport(selectedLineID) {
            return context
        }
        return selectedLineIDs
            .compactMap { lineContextForBugReport($0) }
            .sorted { $0.index < $1.index }
            .first
    }

    private func lineContextForBugReport(_ lineID: DialogueLine.ID?) -> BugReportLineContext? {
        guard let lineID, let index = indexOfLine(withID: lineID) else {
            return nil
        }

        let line = lines[index]
        return BugReportLineContext(
            id: line.id,
            index: line.index,
            speaker: line.speaker,
            startTimecode: line.startTimecode,
            endTimecode: line.endTimecode,
            textPreview: String(line.text.prefix(240))
        )
    }

    private func preferredBugReportsBaseDirectory() -> URL? {
        if let currentProjectURL {
            return currentProjectURL.deletingLastPathComponent()
        }
        if let sourceWordURL {
            return sourceWordURL.deletingLastPathComponent()
        }
        if let videoURL {
            return videoURL.deletingLastPathComponent()
        }
        return nil
    }

    private func knownBugReportLogURLs() -> [URL] {
        [
            Self.backspaceDebugLogURL,
            Self.backspaceDebugAltLogURL,
            URL(fileURLWithPath: "/tmp/dubbingeditor-cmd-enter-focus.log")
        ]
    }

    private func markProjectDirty() {
        autosaveRevision &+= 1
    }

    private func markAutosaveStateAsClean() {
        autosaveRevision &+= 1
        lastAutosavedRevision = autosaveRevision
    }

    private func buildProjectSettingsSnapshot() -> DubbingProjectSettings {
        DubbingProjectSettings(
            shortcuts: currentShortcutSettings(),
            view: DubbingProjectViewSettings(
                isLightModeEnabled: isLightModeEnabled,
                showValidationIssues: showValidationIssues,
                showOnlyIssues: showOnlyIssues,
                isEditModeTimecodePrefillEnabled: isEditModeTimecodePrefillEnabled,
                isEndTimecodeFieldHidden: isEndTimecodeFieldHidden,
                validateMissingSpeaker: validateMissingSpeaker,
                validateMissingStartTC: validateMissingStartTC,
                validateMissingEndTC: validateMissingEndTC,
                validateInvalidTC: validateInvalidTC
            ),
            playbackSeekStepSeconds: playbackSeekStepSeconds,
            isReplayPrerollEnabled: isReplayPrerollEnabled,
            videoOffsetSeconds: videoOffsetSeconds,
            muteLeftChannel: isLeftChannelMuted,
            muteRightChannel: isRightChannelMuted,
            muteVideoAudio: isVideoAudioMuted,
            muteExternalAudio: isExternalAudioMuted,
            speakerColorOverridesByKey: speakerColorOverridesByKey.isEmpty ? nil : speakerColorOverridesByKey
        )
    }

    private func applySpeakerColorOverrides(_ overridesByKey: [String: String]?) {
        speakerColorOverridesByKey = SpeakerAppearanceService.sanitizedOverrides(overridesByKey ?? [:])
    }

    private func currentShortcutSettings() -> DubbingProjectShortcutSettings {
        DubbingProjectShortcutSettings(
            addLine: shortcutValue(forKey: "shortcut_add_line", fallback: "cmd+shift+n"),
            enterEdit: shortcutValue(forKey: "shortcut_enter_edit", fallback: "enter"),
            openReplicaStartTC: shortcutValue(forKey: "shortcut_open_replica_start_tc", fallback: "cmd+enter"),
            playPause: shortcutValue(forKey: "shortcut_play_pause", fallback: "space"),
            rewindReplay: shortcutValue(forKey: "shortcut_rewind_replay", fallback: "option+space"),
            seekBackward: shortcutValue(forKey: "shortcut_seek_backward", fallback: "option+left"),
            seekForward: shortcutValue(forKey: "shortcut_seek_forward", fallback: "option+right"),
            captureStartTC: shortcutValue(forKey: "shortcut_capture_start_tc", fallback: "enter"),
            captureEndTC: shortcutValue(forKey: "shortcut_capture_end_tc", fallback: "shift+enter"),
            moveUp: shortcutValue(forKey: "shortcut_move_up", fallback: "up"),
            moveDown: shortcutValue(forKey: "shortcut_move_down", fallback: "down"),
            toggleLoop: shortcutValue(forKey: "shortcut_toggle_loop", fallback: "option+l"),
            undo: shortcutValue(forKey: "shortcut_undo", fallback: "cmd+z"),
            redo: shortcutValue(forKey: "shortcut_redo", fallback: "cmd+shift+z")
        )
    }

    private func shortcutValue(forKey key: String, fallback: String) -> String {
        let value = UserDefaults.standard.string(forKey: key)?.trimmingCharacters(in: .whitespacesAndNewlines)
        if let value, !value.isEmpty {
            return value
        }
        return fallback
    }

    private func appendBackspaceDebugReport(_ report: String) {
        let payload = report + "\n\n"
        guard let data = payload.data(using: .utf8) else { return }

        let urls: [URL]
        if Self.backspaceDebugLogURL.path == Self.backspaceDebugAltLogURL.path {
            urls = [Self.backspaceDebugLogURL]
        } else {
            urls = [Self.backspaceDebugLogURL, Self.backspaceDebugAltLogURL]
        }
        for url in urls {
            if FileManager.default.fileExists(atPath: url.path) {
                do {
                    let handle = try FileHandle(forWritingTo: url)
                    defer { try? handle.close() }
                    try handle.seekToEnd()
                    handle.write(data)
                } catch {
                    print("Backspace debug log append failed (\(url.path)): \(error.localizedDescription)")
                }
                continue
            }

            do {
                try payload.write(to: url, atomically: true, encoding: .utf8)
            } catch {
                print("Backspace debug log write failed (\(url.path)): \(error.localizedDescription)")
            }
        }
    }

    private func currentLineSummaryByID() -> [DialogueLine.ID: String] {
        var summaryByID: [DialogueLine.ID: String] = [:]
        summaryByID.reserveCapacity(lines.count)
        for line in lines {
            summaryByID[line.id] = debugLineSummary(line)
        }
        return summaryByID
    }

    private func debugSummary(for id: DialogueLine.ID?, using summaries: [DialogueLine.ID: String]) -> String {
        guard let id else { return "<nil>" }
        return summaries[id] ?? "<missing \(id.uuidString)>"
    }

    private func debugSummary(for id: DialogueLine.ID, using summaries: [DialogueLine.ID: String]) -> String {
        summaries[id] ?? "<missing \(id.uuidString)>"
    }

    private func debugLineSummary(_ line: DialogueLine) -> String {
        let idShort = String(line.id.uuidString.prefix(8))
        let speaker = line.speaker.trimmingCharacters(in: .whitespacesAndNewlines)
        let normalizedText = line.text
            .replacingOccurrences(of: "\n", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let textPreview = normalizedText.isEmpty ? "<empty>" : String(normalizedText.prefix(48))
        return "#\(line.index) [\(idShort)] spk='\(speaker)' tc='\(line.startTimecode)' txt='\(textPreview)'"
    }

    private func csvEscaped(_ value: String, delimiter: String) -> String {
        let normalized = value.replacingOccurrences(of: "\"", with: "\"\"")
        let needsQuotes = normalized.contains(delimiter) || normalized.contains("\n") || normalized.contains("\r") || normalized.contains("\"")
        if needsQuotes {
            return "\"\(normalized)\""
        }
        return normalized
    }

    private func apply(projectSettings: DubbingProjectSettings?) {
        guard let projectSettings else { return }

        if let view = projectSettings.view {
            isApplyingProjectSettings = true
            defer { isApplyingProjectSettings = false }
            isLightModeEnabled = view.isLightModeEnabled
            showValidationIssues = view.showValidationIssues
            showOnlyIssues = view.showOnlyIssues
            isEditModeTimecodePrefillEnabled = view.isEditModeTimecodePrefillEnabled
            isEndTimecodeFieldHidden = view.isEndTimecodeFieldHidden
            validateMissingSpeaker = view.validateMissingSpeaker
            validateMissingStartTC = view.validateMissingStartTC
            validateMissingEndTC = view.validateMissingEndTC
            validateInvalidTC = view.validateInvalidTC
        }

        if let shortcuts = projectSettings.shortcuts {
            UserDefaults.standard.set(shortcuts.addLine, forKey: "shortcut_add_line")
            UserDefaults.standard.set(shortcuts.enterEdit, forKey: "shortcut_enter_edit")
            UserDefaults.standard.set(shortcuts.openReplicaStartTC, forKey: "shortcut_open_replica_start_tc")
            UserDefaults.standard.set(shortcuts.playPause, forKey: "shortcut_play_pause")
            UserDefaults.standard.set(shortcuts.rewindReplay, forKey: "shortcut_rewind_replay")
            UserDefaults.standard.set(shortcuts.seekBackward, forKey: "shortcut_seek_backward")
            UserDefaults.standard.set(shortcuts.seekForward, forKey: "shortcut_seek_forward")
            UserDefaults.standard.set(shortcuts.captureStartTC, forKey: "shortcut_capture_start_tc")
            UserDefaults.standard.set(shortcuts.captureEndTC, forKey: "shortcut_capture_end_tc")
            UserDefaults.standard.set(shortcuts.moveUp, forKey: "shortcut_move_up")
            UserDefaults.standard.set(shortcuts.moveDown, forKey: "shortcut_move_down")
            UserDefaults.standard.set(shortcuts.toggleLoop, forKey: "shortcut_toggle_loop")
            UserDefaults.standard.set(shortcuts.undo, forKey: "shortcut_undo")
            UserDefaults.standard.set(shortcuts.redo, forKey: "shortcut_redo")
        }

        if let seekStepSeconds = projectSettings.playbackSeekStepSeconds {
            playbackSeekStepSeconds = seekStepSeconds
        }
        if let replayPrerollEnabled = projectSettings.isReplayPrerollEnabled {
            isReplayPrerollEnabled = replayPrerollEnabled
        }
        if let videoOffsetSeconds = projectSettings.videoOffsetSeconds {
            self.videoOffsetSeconds = videoOffsetSeconds
        }
        if let muteLeftChannel = projectSettings.muteLeftChannel {
            isLeftChannelMuted = muteLeftChannel
        }
        if let muteRightChannel = projectSettings.muteRightChannel {
            isRightChannelMuted = muteRightChannel
        }
        if let muteVideoAudio = projectSettings.muteVideoAudio {
            isVideoAudioMuted = muteVideoAudio
        }
        if let muteExternalAudio = projectSettings.muteExternalAudio {
            isExternalAudioMuted = muteExternalAudio
        }
    }

    private func queueWaveformBuild(
        for url: URL,
        externalAudioURL: URL? = nil,
        forceRebuild: Bool = false
    ) {
        waveformTask?.cancel()
        waveformTask = Task(priority: .utility) { [weak self] in
            guard let self else { return }
            await self.buildWaveforms(
                for: url,
                externalAudioURL: externalAudioURL,
                forceRebuild: forceRebuild
            )
        }
    }

    private func buildWaveforms(
        for url: URL,
        externalAudioURL: URL?,
        forceRebuild: Bool
    ) async {
        isBuildingWaveform = true
        waveformLoadSource = nil
        externalWaveformLoadSource = nil
        let startedAt = Date()
        defer { isBuildingWaveform = false }

        let sampleCount = isLightModeEnabled ? 60_000 : 240_000
        var firstErrorMessage: String?
        var videoTimelineDurationSeconds: Double?

        do {
            let result = try await WaveformService.buildWaveform(
                from: url,
                sampleCount: sampleCount,
                preferCache: !forceRebuild
            )
            guard !Task.isCancelled else { return }
            waveform = result.samples
            waveformLeft = result.leftSamples
            waveformRight = result.rightSamples
            waveformLoadSource = result.source
            videoTimelineDurationSeconds = result.durationSeconds
            refreshWaveformCacheMetadata(for: url, externalAudioURL: externalAudioURL)
            if waveform.isEmpty {
                firstErrorMessage = "Waveform se nepodarilo vytvorit pro tento soubor."
            }
        } catch is CancellationError {
            return
        } catch {
            guard !Task.isCancelled else { return }
            clearPrimaryWaveformState()
            refreshWaveformCacheMetadata(for: url, externalAudioURL: externalAudioURL)
            firstErrorMessage = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        }

        if let externalAudioURL {
            do {
                let result = try await WaveformService.buildWaveform(
                    from: externalAudioURL,
                    sampleCount: sampleCount,
                    preferCache: !forceRebuild
                )
                guard !Task.isCancelled else { return }
                externalWaveform = PlaybackWaveformProjectionService.projectToTimeline(
                    samples: result.samples,
                    mediaDurationSeconds: result.durationSeconds,
                    timelineDurationSeconds: videoTimelineDurationSeconds
                )
                externalWaveformLoadSource = result.source
                refreshWaveformCacheMetadata(for: url, externalAudioURL: externalAudioURL)
                if externalWaveform.isEmpty, firstErrorMessage == nil {
                    firstErrorMessage = "Waveform externiho audia se nepodarilo vytvorit."
                }
            } catch is CancellationError {
                return
            } catch {
                guard !Task.isCancelled else { return }
                clearExternalWaveformState()
                refreshWaveformCacheMetadata(for: url, externalAudioURL: externalAudioURL)
                if firstErrorMessage == nil {
                    let description = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
                    firstErrorMessage = "Waveform externiho audia selhal: \(description)"
                }
            }
        } else {
            clearExternalWaveformState()
            refreshWaveformCacheMetadata(for: url, externalAudioURL: nil)
        }

        lastWaveformBuildDuration = Date().timeIntervalSince(startedAt)
        if let firstErrorMessage {
            alertMessage = firstErrorMessage
        }
    }

    private func handleVideoItemStatusChange(_ item: AVPlayerItem) {
        let status = item.status
        logPlaybackDebugEvent(
            "PLAYER_ITEM_STATUS_CHANGED",
            source: "item_kvo",
            itemOverride: item,
            extraFields: [("status", playbackDebugItemStatus(status))]
        )
        guard let startedAt = videoLoadStartedAt else { return }
        switch status {
        case .readyToPlay:
            lastVideoLoadDuration = Date().timeIntervalSince(startedAt)
            videoLoadStartedAt = nil
            restorePendingPlaybackPositionIfNeeded()
        case .failed:
            lastVideoLoadDuration = Date().timeIntervalSince(startedAt)
            videoLoadStartedAt = nil
            pendingPlaybackRestoreTimelineSeconds = nil
            pendingPlaybackResumeAfterRestore = false
        case .unknown:
            break
        @unknown default:
            break
        }
    }

    private func restorePendingPlaybackPositionIfNeeded() {
        guard let timelineSeconds = pendingPlaybackRestoreTimelineSeconds else { return }
        pendingPlaybackRestoreTimelineSeconds = nil
        let shouldResumePlayback = pendingPlaybackResumeAfterRestore
        pendingPlaybackResumeAfterRestore = false
        seek(
            to: playbackSeconds(fromTimelineSeconds: timelineSeconds),
            source: "restore",
            resumeAfterSeek: shouldResumePlayback
        )
    }

    private func configurePlayerItemForSmoothPlayback(_ item: AVPlayerItem) {
        // Local dubbing workflows favor fast seeking over aggressive forward buffering.
        item.preferredForwardBufferDuration = isLightModeEnabled ? 0.6 : 0.2
        item.canUseNetworkResourcesForLiveStreamingWhilePaused = false
        if #available(macOS 10.15, *) {
            item.seekingWaitsForVideoCompositionRendering = false
        }
    }

    private func applyVideoBufferingPreferences() {
        guard let currentItem = player.currentItem else { return }
        configurePlayerItemForSmoothPlayback(currentItem)
    }

    private func requestPlaybackResumeAfterCurrentSeekIfNeeded() -> Bool {
        guard activeSeekGeneration != completedSeekGeneration else { return false }
        resumePlaybackAfterSeekGeneration = activeSeekGeneration
        return true
    }

    private func resetSeekPlaybackState() {
        activeSeekGeneration = 0
        completedSeekGeneration = 0
        resumePlaybackAfterSeekGeneration = nil
    }

    private func currentTimelinePlaybackSeconds(playbackSecondsOverride: Double? = nil) -> Double? {
        guard player.currentItem != nil else { return nil }
        let playbackSeconds = playbackSecondsOverride ?? player.currentTime().seconds
        guard playbackSeconds.isFinite else { return nil }
        return timelineSeconds(fromPlaybackSeconds: playbackSeconds)
    }

    private func refreshWaveformCacheMetadata(for url: URL?, externalAudioURL: URL?) {
        guard let url else {
            waveformCacheExists = false
            waveformCacheSizeBytes = nil
            externalWaveformCacheExists = false
            externalWaveformCacheSizeBytes = nil
            return
        }
        waveformCacheExists = WaveformService.cacheExists(for: url)
        waveformCacheSizeBytes = WaveformService.cacheSizeBytes(for: url)
        if let externalAudioURL {
            externalWaveformCacheExists = WaveformService.cacheExists(for: externalAudioURL)
            externalWaveformCacheSizeBytes = WaveformService.cacheSizeBytes(for: externalAudioURL)
        } else {
            externalWaveformCacheExists = false
            externalWaveformCacheSizeBytes = nil
        }
    }

    private func clearPrimaryWaveformState() {
        waveform = []
        waveformLeft = []
        waveformRight = []
        waveformLoadSource = nil
    }

    private func clearExternalWaveformState() {
        externalWaveform = []
        externalWaveformLoadSource = nil
    }

    private func sanitizeSelectionForCurrentLines() {
        let validIDs = Set(lines.map(\.id))

        selectedLineIDs = selectedLineIDs.intersection(validIDs)

        if let selectedLineID, !validIDs.contains(selectedLineID) {
            self.selectedLineID = nil
        }
        if selectedLineID == nil {
            if let selectedFromSet = selectedLineIDs.first {
                selectedLineID = selectedFromSet
            } else {
                selectedLineID = lines.first?.id
            }
        }

        if selectedLineIDs.isEmpty, let selectedLineID {
            selectedLineIDs = [selectedLineID]
        }

        if
            let selectedLineID,
            !selectedLineIDs.isEmpty,
            !selectedLineIDs.contains(selectedLineID)
        {
            if let highlightedLineID, selectedLineIDs.contains(highlightedLineID) {
                self.selectedLineID = highlightedLineID
            } else if let firstSelected = firstLineIDInCurrentOrder(from: selectedLineIDs) {
                self.selectedLineID = firstSelected
            } else {
                self.selectedLineID = nil
            }
        }

        if let selectedLineID {
            selectedLineIDs.insert(selectedLineID)
            if let anchor = selectionAnchorLineID, validIDs.contains(anchor) {
                selectionAnchorLineID = anchor
            } else {
                selectionAnchorLineID = selectedLineID
            }
        } else {
            selectionAnchorLineID = nil
        }

        if let highlightedLineID, !validIDs.contains(highlightedLineID) {
            self.highlightedLineID = selectedLineID
        }

        if let editingLineID, !validIDs.contains(editingLineID) {
            self.editingLineID = nil
        }
    }

    private func indexOfLine(withID lineID: DialogueLine.ID) -> Int? {
        if
            let cachedIndex = lineIndexByID[lineID],
            cachedIndex >= 0,
            cachedIndex < lines.count,
            lines[cachedIndex].id == lineID
        {
            return cachedIndex
        }

        rebuildLineIndexCache()
        return lineIndexByID[lineID]
    }

    private func firstLineIDInCurrentOrder(from ids: Set<DialogueLine.ID>) -> DialogueLine.ID? {
        lines.first { ids.contains($0.id) }?.id
    }

    private func rebuildLineIndexCache() {
        var map: [DialogueLine.ID: Int] = [:]
        map.reserveCapacity(lines.count)
        for (index, line) in lines.enumerated() {
            map[line.id] = index
        }
        lineIndexByID = map
    }

    private func loadRecentProjectURLs() {
        let storedPaths = UserDefaults.standard.stringArray(forKey: Self.recentProjectsDefaultsKey) ?? []
        var seen = Set<String>()
        var restored: [URL] = []
        restored.reserveCapacity(min(storedPaths.count, Self.maxRecentProjectsCount))

        for path in storedPaths {
            let trimmed = path.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { continue }

            let canonical = URL(fileURLWithPath: trimmed).standardizedFileURL
            let canonicalPath = canonical.path
            guard !seen.contains(canonicalPath) else { continue }
            guard FileManager.default.fileExists(atPath: canonicalPath) else { continue }

            seen.insert(canonicalPath)
            restored.append(canonical)
            if restored.count >= Self.maxRecentProjectsCount {
                break
            }
        }

        recentProjectURLs = restored
        persistRecentProjectURLs()
    }

    private func addRecentProjectURL(_ url: URL) {
        let canonical = url.standardizedFileURL
        let canonicalPath = canonical.path

        var updated: [URL] = [canonical]
        updated.reserveCapacity(Self.maxRecentProjectsCount)
        for existing in recentProjectURLs {
            let existingCanonical = existing.standardizedFileURL
            if existingCanonical.path == canonicalPath {
                continue
            }
            guard FileManager.default.fileExists(atPath: existingCanonical.path) else {
                continue
            }
            updated.append(existingCanonical)
            if updated.count >= Self.maxRecentProjectsCount {
                break
            }
        }

        recentProjectURLs = updated
        persistRecentProjectURLs()
    }

    private func removeRecentProjectURL(_ url: URL) {
        let canonicalPath = url.standardizedFileURL.path
        recentProjectURLs.removeAll { $0.standardizedFileURL.path == canonicalPath }
        persistRecentProjectURLs()
    }

    private func persistRecentProjectURLs() {
        let paths = recentProjectURLs.map { $0.standardizedFileURL.path }
        UserDefaults.standard.set(paths, forKey: Self.recentProjectsDefaultsKey)
    }

    func consumePendingRestoreLineID() -> DialogueLine.ID? {
        let value = pendingRestoreLineID
        pendingRestoreLineID = nil
        return value
    }

    func lineIndex(for lineID: DialogueLine.ID) -> Int? {
        indexOfLine(withID: lineID)
    }

    private static func sanitizedFPS(_ value: Double) -> Double {
        guard value.isFinite else { return fixedFPS }
        let clamped = min(max(value, minSupportedFPS), maxSupportedFPS)
        if clamped <= 0 {
            return fixedFPS
        }
        return clamped
    }

    private static func closestFPSPreset(for value: Double) -> FPSPreset? {
        let sanitized = sanitizedFPS(value)
        return FPSPreset.allCases.first { abs($0.value - sanitized) <= fpsPresetSnapTolerance }
    }

    private static func normalizedDetectedFPS(_ value: Double) -> Double {
        if let preset = closestFPSPreset(for: value) {
            return preset.value
        }
        return sanitizedFPS(value)
    }

    private static func formattedFPSValue(_ value: Double) -> String {
        let rounded = value.rounded()
        if abs(rounded - value) < 0.000_001 {
            return String(Int(rounded))
        }

        let formatted = String(format: "%.3f", value)
        let withoutTrailingZeros = formatted.replacingOccurrences(
            of: #"0+$"#,
            with: "",
            options: .regularExpression
        )
        return withoutTrailingZeros.replacingOccurrences(
            of: #"\.$"#,
            with: "",
            options: .regularExpression
        )
    }

    private static func resolveVideoFPS(from asset: AVAsset) async -> Double? {
        do {
            let tracks = try await asset.loadTracks(withMediaType: .video)
            guard let track = tracks.first else { return nil }

            let nominal = Double(try await track.load(.nominalFrameRate))
            if nominal.isFinite, nominal > 0 {
                return nominal
            }

            let minDuration = try await track.load(.minFrameDuration)
            if minDuration.isValid, minDuration.seconds.isFinite, minDuration.seconds > 0 {
                return 1.0 / minDuration.seconds
            }
        } catch {
            return nil
        }
        return nil
    }
}
