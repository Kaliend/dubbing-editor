import Foundation

struct AutosaveSnapshot: Codable {
    let schemaVersion: Int
    let savedAt: Date
    let documentTitle: String
    let fps: Double
    let lines: [DialogueLine]
    let selectedLineID: DialogueLine.ID?
    let highlightedLineID: DialogueLine.ID?
    let sourceWordPath: String?
    let sourceVideoPath: String?
    let sourceExternalAudioPath: String?
    let muteVideoAudio: Bool?
    let muteExternalAudio: Bool?
    let speakerColorOverridesByKey: [String: String]?

    init(
        savedAt: Date,
        documentTitle: String,
        fps: Double,
        lines: [DialogueLine],
        selectedLineID: DialogueLine.ID?,
        highlightedLineID: DialogueLine.ID?,
        sourceWordPath: String?,
        sourceVideoPath: String?,
        sourceExternalAudioPath: String? = nil,
        muteVideoAudio: Bool? = nil,
        muteExternalAudio: Bool? = nil,
        speakerColorOverridesByKey: [String: String]? = nil
    ) {
        self.schemaVersion = 2
        self.savedAt = savedAt
        self.documentTitle = documentTitle
        self.fps = fps
        self.lines = lines
        self.selectedLineID = selectedLineID
        self.highlightedLineID = highlightedLineID
        self.sourceWordPath = sourceWordPath
        self.sourceVideoPath = sourceVideoPath
        self.sourceExternalAudioPath = sourceExternalAudioPath
        self.muteVideoAudio = muteVideoAudio
        self.muteExternalAudio = muteExternalAudio
        self.speakerColorOverridesByKey = speakerColorOverridesByKey
    }
}

actor AutosaveService {
    private let fileManager = FileManager.default
    private let maxVersionCount: Int
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder
    private let versionDateFormatter: DateFormatter

    init(maxVersionCount: Int = 50) {
        self.maxVersionCount = maxVersionCount

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        self.encoder = encoder

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        self.decoder = decoder

        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "yyyy-MM-dd_HH-mm-ss-SSS"
        self.versionDateFormatter = formatter
    }

    func loadLatestSnapshot() throws -> AutosaveSnapshot? {
        let url = latestSnapshotURL()
        guard fileManager.fileExists(atPath: url.path) else {
            return nil
        }
        let data = try Data(contentsOf: url)
        return try decoder.decode(AutosaveSnapshot.self, from: data)
    }

    func discardLatestSnapshot() throws {
        let url = latestSnapshotURL()
        guard fileManager.fileExists(atPath: url.path) else {
            return
        }
        try fileManager.removeItem(at: url)
    }

    func saveSnapshot(_ snapshot: AutosaveSnapshot) throws {
        try ensureDirectories()
        let data = try encoder.encode(snapshot)

        try data.write(to: latestSnapshotURL(), options: .atomic)

        let versionURL = versionsDirectoryURL()
            .appendingPathComponent(versionFilename(for: snapshot.savedAt))
        try data.write(to: versionURL, options: .atomic)

        try trimVersionedBackupsIfNeeded()
    }

    func startSession() throws -> Bool {
        try ensureDirectories()
        let lockURL = sessionLockURL()
        let hadPreviousLock = fileManager.fileExists(atPath: lockURL.path)
        let marker = "session-started:\(Date().timeIntervalSince1970)"
        try Data(marker.utf8).write(to: lockURL, options: .atomic)
        return hadPreviousLock
    }

    func endSession() throws {
        let lockURL = sessionLockURL()
        guard fileManager.fileExists(atPath: lockURL.path) else {
            return
        }
        try fileManager.removeItem(at: lockURL)
    }

    private func ensureDirectories() throws {
        try fileManager.createDirectory(at: autosaveDirectoryURL(), withIntermediateDirectories: true)
        try fileManager.createDirectory(at: versionsDirectoryURL(), withIntermediateDirectories: true)
    }

    private func trimVersionedBackupsIfNeeded() throws {
        let directory = versionsDirectoryURL()
        let keys: [URLResourceKey] = [.contentModificationDateKey]
        let files = try fileManager.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: keys,
            options: [.skipsHiddenFiles]
        )

        if files.count <= maxVersionCount {
            return
        }

        let sorted = try files.sorted { lhs, rhs in
            let leftDate = try lhs.resourceValues(forKeys: Set(keys)).contentModificationDate ?? .distantPast
            let rightDate = try rhs.resourceValues(forKeys: Set(keys)).contentModificationDate ?? .distantPast
            return leftDate > rightDate
        }

        for fileURL in sorted.dropFirst(maxVersionCount) {
            try? fileManager.removeItem(at: fileURL)
        }
    }

    private func autosaveDirectoryURL() -> URL {
        let base = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? fileManager.homeDirectoryForCurrentUser
        return base
            .appendingPathComponent("DubbingEditor", isDirectory: true)
            .appendingPathComponent("Autosaves", isDirectory: true)
    }

    private func versionsDirectoryURL() -> URL {
        autosaveDirectoryURL().appendingPathComponent("versions", isDirectory: true)
    }

    private func latestSnapshotURL() -> URL {
        autosaveDirectoryURL().appendingPathComponent("latest.json")
    }

    private func sessionLockURL() -> URL {
        autosaveDirectoryURL().appendingPathComponent("session.lock")
    }

    private func versionFilename(for date: Date) -> String {
        "autosave-\(versionDateFormatter.string(from: date)).json"
    }
}
