import AppKit
import Foundation

enum BugReportEmailServiceError: LocalizedError {
    case missingRecipient
    case emailComposeUnavailable
    case archiveCreationFailed(String)

    var errorDescription: String? {
        switch self {
        case .missingRecipient:
            return "Neni nastaven zadny e-mail pro bug reporty."
        case .emailComposeUnavailable:
            return "Nepodarilo se otevrit e-mail draft. Zkontroluj, ze je v macOS dostupna Mail sluzba."
        case let .archiveCreationFailed(message):
            return "Nepodarilo se vytvorit ZIP reportu: \(message)"
        }
    }
}

struct BugReportEmailService {
    func createArchive(for reportDirectoryURL: URL) throws -> URL {
        let parentDirectoryURL = reportDirectoryURL.deletingLastPathComponent()
        let archiveURL = parentDirectoryURL
            .appendingPathComponent(reportDirectoryURL.lastPathComponent)
            .appendingPathExtension("zip")

        if FileManager.default.fileExists(atPath: archiveURL.path) {
            try FileManager.default.removeItem(at: archiveURL)
        }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/ditto")
        process.currentDirectoryURL = parentDirectoryURL
        process.arguments = [
            "-c",
            "-k",
            "--sequesterRsrc",
            "--keepParent",
            reportDirectoryURL.lastPathComponent,
            archiveURL.lastPathComponent
        ]

        let stderrPipe = Pipe()
        process.standardError = stderrPipe

        try process.run()
        process.waitUntilExit()

        guard process.terminationStatus == 0 else {
            let data = stderrPipe.fileHandleForReading.readDataToEndOfFile()
            let message = String(data: data, encoding: .utf8)?
                .trimmingCharacters(in: .whitespacesAndNewlines)
            throw BugReportEmailServiceError.archiveCreationFailed(message?.isEmpty == false ? message! : "neznamy duvod")
        }

        return archiveURL
    }

    @MainActor
    func composeEmail(
        recipients: [String],
        subject: String,
        body: String,
        attachmentURL: URL
    ) throws {
        let sanitizedRecipients = recipients
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        guard !sanitizedRecipients.isEmpty else {
            throw BugReportEmailServiceError.missingRecipient
        }

        guard let service = NSSharingService(named: .composeEmail) else {
            throw BugReportEmailServiceError.emailComposeUnavailable
        }

        service.recipients = sanitizedRecipients
        service.subject = subject
        service.perform(withItems: [body, attachmentURL])
    }
}
