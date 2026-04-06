import Foundation

struct DubbingProjectShortcutSettings: Codable, Hashable, Sendable {
    let addLine: String
    let enterEdit: String
    let openReplicaStartTC: String
    let playPause: String
    let rewindReplay: String
    let seekBackward: String
    let seekForward: String
    let captureStartTC: String
    let captureEndTC: String
    let moveUp: String
    let moveDown: String
    let toggleLoop: String
    let undo: String
    let redo: String

    init(
        addLine: String = "cmd+shift+n",
        enterEdit: String,
        openReplicaStartTC: String = "cmd+enter",
        playPause: String,
        rewindReplay: String,
        seekBackward: String = "option+left",
        seekForward: String = "option+right",
        captureStartTC: String = "enter",
        captureEndTC: String = "shift+enter",
        moveUp: String,
        moveDown: String,
        toggleLoop: String,
        undo: String,
        redo: String
    ) {
        self.addLine = addLine
        self.enterEdit = enterEdit
        self.openReplicaStartTC = openReplicaStartTC
        self.playPause = playPause
        self.rewindReplay = rewindReplay
        self.seekBackward = seekBackward
        self.seekForward = seekForward
        self.captureStartTC = captureStartTC
        self.captureEndTC = captureEndTC
        self.moveUp = moveUp
        self.moveDown = moveDown
        self.toggleLoop = toggleLoop
        self.undo = undo
        self.redo = redo
    }

    private enum CodingKeys: String, CodingKey {
        case addLine
        case enterEdit
        case openReplicaStartTC
        case playPause
        case rewindReplay
        case seekBackward
        case seekForward
        case captureStartTC
        case captureEndTC
        case moveUp
        case moveDown
        case toggleLoop
        case undo
        case redo
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        addLine = try container.decodeIfPresent(String.self, forKey: .addLine) ?? "cmd+shift+n"
        enterEdit = try container.decodeIfPresent(String.self, forKey: .enterEdit) ?? "enter"
        openReplicaStartTC = try container.decodeIfPresent(String.self, forKey: .openReplicaStartTC) ?? "cmd+enter"
        playPause = try container.decodeIfPresent(String.self, forKey: .playPause) ?? "space"
        rewindReplay = try container.decodeIfPresent(String.self, forKey: .rewindReplay) ?? "option+space"
        seekBackward = try container.decodeIfPresent(String.self, forKey: .seekBackward) ?? "option+left"
        seekForward = try container.decodeIfPresent(String.self, forKey: .seekForward) ?? "option+right"
        captureStartTC = try container.decodeIfPresent(String.self, forKey: .captureStartTC) ?? "enter"
        captureEndTC = try container.decodeIfPresent(String.self, forKey: .captureEndTC) ?? "shift+enter"
        moveUp = try container.decodeIfPresent(String.self, forKey: .moveUp) ?? "up"
        moveDown = try container.decodeIfPresent(String.self, forKey: .moveDown) ?? "down"
        toggleLoop = try container.decodeIfPresent(String.self, forKey: .toggleLoop) ?? "option+l"
        undo = try container.decodeIfPresent(String.self, forKey: .undo) ?? "cmd+z"
        redo = try container.decodeIfPresent(String.self, forKey: .redo) ?? "cmd+shift+z"
    }
}

struct DubbingProjectViewSettings: Codable, Hashable, Sendable {
    let isLightModeEnabled: Bool
    let showValidationIssues: Bool
    let showOnlyIssues: Bool
    let isEditModeTimecodePrefillEnabled: Bool
    let isEndTimecodeFieldHidden: Bool
    let validateMissingSpeaker: Bool
    let validateMissingStartTC: Bool
    let validateMissingEndTC: Bool
    let validateInvalidTC: Bool

    init(
        isLightModeEnabled: Bool,
        showValidationIssues: Bool,
        showOnlyIssues: Bool,
        isEditModeTimecodePrefillEnabled: Bool = false,
        isEndTimecodeFieldHidden: Bool = false,
        validateMissingSpeaker: Bool = true,
        validateMissingStartTC: Bool = true,
        validateMissingEndTC: Bool = true,
        validateInvalidTC: Bool = true
    ) {
        self.isLightModeEnabled = isLightModeEnabled
        self.showValidationIssues = showValidationIssues
        self.showOnlyIssues = showOnlyIssues
        self.isEditModeTimecodePrefillEnabled = isEditModeTimecodePrefillEnabled
        self.isEndTimecodeFieldHidden = isEndTimecodeFieldHidden
        self.validateMissingSpeaker = validateMissingSpeaker
        self.validateMissingStartTC = validateMissingStartTC
        self.validateMissingEndTC = validateMissingEndTC
        self.validateInvalidTC = validateInvalidTC
    }

    private enum CodingKeys: String, CodingKey {
        case isLightModeEnabled
        case showValidationIssues
        case showOnlyIssues
        case isEditModeTimecodePrefillEnabled
        case isEndTimecodeFieldHidden
        case validateMissingSpeaker
        case validateMissingStartTC
        case validateMissingEndTC
        case validateInvalidTC
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        isLightModeEnabled = try container.decode(Bool.self, forKey: .isLightModeEnabled)
        showValidationIssues = try container.decodeIfPresent(Bool.self, forKey: .showValidationIssues) ?? false
        showOnlyIssues = try container.decodeIfPresent(Bool.self, forKey: .showOnlyIssues) ?? false
        isEditModeTimecodePrefillEnabled = try container.decodeIfPresent(Bool.self, forKey: .isEditModeTimecodePrefillEnabled) ?? false
        isEndTimecodeFieldHidden = try container.decodeIfPresent(Bool.self, forKey: .isEndTimecodeFieldHidden) ?? false
        validateMissingSpeaker = try container.decodeIfPresent(Bool.self, forKey: .validateMissingSpeaker) ?? true
        validateMissingStartTC = try container.decodeIfPresent(Bool.self, forKey: .validateMissingStartTC) ?? true
        validateMissingEndTC = try container.decodeIfPresent(Bool.self, forKey: .validateMissingEndTC) ?? true
        validateInvalidTC = try container.decodeIfPresent(Bool.self, forKey: .validateInvalidTC) ?? true
    }
}

struct DubbingProjectSettings: Codable, Hashable, Sendable {
    let shortcuts: DubbingProjectShortcutSettings?
    let view: DubbingProjectViewSettings?
    let playbackSeekStepSeconds: Double?
    let isReplayPrerollEnabled: Bool?
    let videoOffsetSeconds: Double?
    let muteLeftChannel: Bool?
    let muteRightChannel: Bool?
    let muteVideoAudio: Bool?
    let muteExternalAudio: Bool?
    let speakerColorOverridesByKey: [String: String]?

    init(
        shortcuts: DubbingProjectShortcutSettings?,
        view: DubbingProjectViewSettings?,
        playbackSeekStepSeconds: Double? = nil,
        isReplayPrerollEnabled: Bool? = nil,
        videoOffsetSeconds: Double? = nil,
        muteLeftChannel: Bool? = nil,
        muteRightChannel: Bool? = nil,
        muteVideoAudio: Bool? = nil,
        muteExternalAudio: Bool? = nil,
        speakerColorOverridesByKey: [String: String]? = nil
    ) {
        self.shortcuts = shortcuts
        self.view = view
        self.playbackSeekStepSeconds = playbackSeekStepSeconds
        self.isReplayPrerollEnabled = isReplayPrerollEnabled
        self.videoOffsetSeconds = videoOffsetSeconds
        self.muteLeftChannel = muteLeftChannel
        self.muteRightChannel = muteRightChannel
        self.muteVideoAudio = muteVideoAudio
        self.muteExternalAudio = muteExternalAudio
        self.speakerColorOverridesByKey = speakerColorOverridesByKey
    }
}

struct DubbingProjectFile: Codable, Sendable {
    let schemaVersion: Int
    let savedAt: Date
    let documentTitle: String
    let fps: Double
    let lines: [DialogueLine]
    let selectedLineID: DialogueLine.ID?
    let highlightedLineID: DialogueLine.ID?
    let playbackPositionSeconds: Double?
    let sourceWordPath: String?
    let sourceVideoPath: String?
    let sourceExternalAudioPath: String?
    let settings: DubbingProjectSettings?

    init(
        savedAt: Date = Date(),
        documentTitle: String,
        fps: Double,
        lines: [DialogueLine],
        selectedLineID: DialogueLine.ID?,
        highlightedLineID: DialogueLine.ID?,
        playbackPositionSeconds: Double?,
        sourceWordPath: String?,
        sourceVideoPath: String?,
        sourceExternalAudioPath: String? = nil,
        settings: DubbingProjectSettings?
    ) {
        self.schemaVersion = 5
        self.savedAt = savedAt
        self.documentTitle = documentTitle
        self.fps = fps
        self.lines = lines
        self.selectedLineID = selectedLineID
        self.highlightedLineID = highlightedLineID
        self.playbackPositionSeconds = playbackPositionSeconds
        self.sourceWordPath = sourceWordPath
        self.sourceVideoPath = sourceVideoPath
        self.sourceExternalAudioPath = sourceExternalAudioPath
        self.settings = settings
    }

    private enum CodingKeys: String, CodingKey {
        case schemaVersion
        case savedAt
        case documentTitle
        case fps
        case lines
        case selectedLineID
        case highlightedLineID
        case playbackPositionSeconds
        case sourceWordPath
        case sourceVideoPath
        case sourceExternalAudioPath
        case settings
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        schemaVersion = try container.decodeIfPresent(Int.self, forKey: .schemaVersion) ?? 1
        savedAt = try container.decode(Date.self, forKey: .savedAt)
        documentTitle = try container.decode(String.self, forKey: .documentTitle)
        fps = try container.decode(Double.self, forKey: .fps)
        lines = try container.decode([DialogueLine].self, forKey: .lines)
        selectedLineID = try container.decodeIfPresent(DialogueLine.ID.self, forKey: .selectedLineID)
        highlightedLineID = try container.decodeIfPresent(DialogueLine.ID.self, forKey: .highlightedLineID)
        playbackPositionSeconds = try container.decodeIfPresent(Double.self, forKey: .playbackPositionSeconds)
        sourceWordPath = try container.decodeIfPresent(String.self, forKey: .sourceWordPath)
        sourceVideoPath = try container.decodeIfPresent(String.self, forKey: .sourceVideoPath)
        sourceExternalAudioPath = try container.decodeIfPresent(String.self, forKey: .sourceExternalAudioPath)
        settings = try container.decodeIfPresent(DubbingProjectSettings.self, forKey: .settings)
    }
}

final class ProjectService {
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder

    init() {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        self.encoder = encoder

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        self.decoder = decoder
    }

    func save(_ project: DubbingProjectFile, to url: URL) throws {
        let data = try encoder.encode(project)
        try data.write(to: url, options: .atomic)
    }

    func load(from url: URL) throws -> DubbingProjectFile {
        let data = try Data(contentsOf: url, options: [.mappedIfSafe])
        return try decoder.decode(DubbingProjectFile.self, from: data)
    }
}
