import Foundation

enum SpeakerAutocompleteDebugLog {
    static let logURL = URL(fileURLWithPath: "/tmp/dubbingeditor-speaker-autocomplete.log")

    private static let dateFormatter: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()

    static func append(
        enabled: Bool,
        event: String,
        fields: [(String, String?)]
    ) {
        guard enabled else { return }

        let timestamp = dateFormatter.string(from: Date())
        let renderedFields = fields
            .map { key, value in "\(key)=\(render(value))" }
            .joined(separator: " ")
        let line = renderedFields.isEmpty
            ? "\(timestamp) \(event)\n"
            : "\(timestamp) \(event) \(renderedFields)\n"

        guard let data = line.data(using: .utf8) else { return }

        if FileManager.default.fileExists(atPath: logURL.path) {
            do {
                let handle = try FileHandle(forWritingTo: logURL)
                defer { try? handle.close() }
                try handle.seekToEnd()
                handle.write(data)
            } catch {
                print("Speaker autocomplete debug log append failed: \(error.localizedDescription)")
            }
            return
        }

        do {
            try line.write(to: logURL, atomically: true, encoding: .utf8)
        } catch {
            print("Speaker autocomplete debug log write failed: \(error.localizedDescription)")
        }
    }

    static func shortID(_ uuid: UUID?) -> String? {
        guard let uuid else { return nil }
        return String(uuid.uuidString.prefix(8))
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
