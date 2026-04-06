import Foundation

struct PlaybackDebugSnapshot {
    let item: String?
    let timeControlStatus: String?
    let currentSeconds: String?
    let audioMix: String?
    let videoMuted: String?
    let externalMuted: String?
    let muteL: String?
    let muteR: String?
    let hasExternalAudio: String?
    let tapActive: String?
    let tapForcedOff: String?
    let videoTrackID: String?
    let externalTrackID: String?
}

enum PlaybackDebugLogger {
    static let logURL = URL(fileURLWithPath: "/tmp/dubbingeditor-playback-audio.log")

    private static let dateFormatter: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()

    private static let queue = DispatchQueue(label: "PlaybackDebugLogger")

    static func append(
        enabled: Bool,
        event: String,
        source: String,
        seekGeneration: UInt64?,
        snapshot: PlaybackDebugSnapshot,
        extraFields: [(String, String?)] = []
    ) {
        guard enabled else { return }

        let timestamp = dateFormatter.string(from: Date())
        let fields: [(String, String?)] = [
            ("source", source),
            ("seekGen", seekGeneration.map(String.init)),
            ("item", snapshot.item),
            ("timeControlStatus", snapshot.timeControlStatus),
            ("currentSeconds", snapshot.currentSeconds),
            ("audioMix", snapshot.audioMix),
            ("videoMuted", snapshot.videoMuted),
            ("externalMuted", snapshot.externalMuted),
            ("muteL", snapshot.muteL),
            ("muteR", snapshot.muteR),
            ("hasExternalAudio", snapshot.hasExternalAudio),
            ("tapActive", snapshot.tapActive),
            ("tapForcedOff", snapshot.tapForcedOff),
            ("videoTrackID", snapshot.videoTrackID),
            ("externalTrackID", snapshot.externalTrackID)
        ] + extraFields

        let renderedFields = fields
            .map { key, value in "\(key)=\(render(value))" }
            .joined(separator: " ")
        let line = renderedFields.isEmpty
            ? "\(timestamp) \(event)\n"
            : "\(timestamp) \(event) \(renderedFields)\n"

        guard let data = line.data(using: .utf8) else { return }

        queue.async {
            if FileManager.default.fileExists(atPath: logURL.path) {
                do {
                    let handle = try FileHandle(forWritingTo: logURL)
                    defer { try? handle.close() }
                    try handle.seekToEnd()
                    handle.write(data)
                } catch {
                    print("Playback debug log append failed: \(error.localizedDescription)")
                }
                return
            }

            do {
                try line.write(to: logURL, atomically: true, encoding: .utf8)
            } catch {
                print("Playback debug log write failed: \(error.localizedDescription)")
            }
        }
    }

    private static func render(_ value: String?) -> String {
        guard let value else { return "<nil>" }
        guard !value.isEmpty else { return "''" }

        let escaped = value
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "'", with: "\\'")
            .replacingOccurrences(of: "\n", with: "\\n")

        let requiresQuotes = escaped.contains(where: { $0.isWhitespace }) || escaped.contains("'")
        return requiresQuotes ? "'\(escaped)'" : escaped
    }
}
