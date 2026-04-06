import Foundation

struct BugReportServiceEnvironment: Sendable {
    let appVersion: String
    let buildNumber: String
    let osVersion: String

    static func live(bundle: Bundle = .main, processInfo: ProcessInfo = .processInfo) -> Self {
        let infoDictionary = bundle.infoDictionary ?? [:]
        let appVersion = (infoDictionary["CFBundleShortVersionString"] as? String)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let buildNumber = (infoDictionary["CFBundleVersion"] as? String)?
            .trimmingCharacters(in: .whitespacesAndNewlines)

        return Self(
            appVersion: (appVersion?.isEmpty == false ? appVersion : nil) ?? "dev",
            buildNumber: (buildNumber?.isEmpty == false ? buildNumber : nil) ?? "dev",
            osVersion: processInfo.operatingSystemVersionString
        )
    }
}

struct BugReportService {
    private let projectService: ProjectService
    private let environment: BugReportServiceEnvironment
    private let fileManager: FileManager
    private let appSupportRootURL: URL
    private let dateProvider: @Sendable () -> Date
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder
    private let dashboardDateFormatter: DateFormatter

    init(
        projectService: ProjectService = ProjectService(),
        environment: BugReportServiceEnvironment = .live(),
        fileManager: FileManager = .default,
        appSupportRootURL: URL? = nil,
        dateProvider: @escaping @Sendable () -> Date = { Date() }
    ) {
        self.projectService = projectService
        self.environment = environment
        self.fileManager = fileManager
        if let appSupportRootURL {
            self.appSupportRootURL = appSupportRootURL
        } else if let defaultURL = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first {
            self.appSupportRootURL = defaultURL
        } else {
            self.appSupportRootURL = fileManager.temporaryDirectory
        }
        self.dateProvider = dateProvider

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        self.encoder = encoder

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        self.decoder = decoder

        let dashboardDateFormatter = DateFormatter()
        dashboardDateFormatter.locale = Locale(identifier: "cs_CZ")
        dashboardDateFormatter.dateStyle = .medium
        dashboardDateFormatter.timeStyle = .short
        self.dashboardDateFormatter = dashboardDateFormatter
    }

    func reportsRootURL(preferredBaseDirectory: URL?) -> URL {
        if let preferredBaseDirectory {
            return preferredBaseDirectory.appendingPathComponent("Bug Reports", isDirectory: true)
        }

        return appSupportRootURL
            .appendingPathComponent("DubbingEditor", isDirectory: true)
            .appendingPathComponent("Bug Reports", isDirectory: true)
    }

    @discardableResult
    func refreshDashboard(preferredBaseDirectory: URL?) throws -> URL {
        let rootURL = reportsRootURL(preferredBaseDirectory: preferredBaseDirectory)
        try fileManager.createDirectory(at: rootURL, withIntermediateDirectories: true, attributes: nil)
        try rebuildIndex(in: rootURL)
        return rootURL.appendingPathComponent("index.html")
    }

    func createReport(
        draft: BugReportDraft,
        editorState: BugReportEditorState,
        uiState: BugReportUIState,
        screenshotPNGData: Data?,
        projectSnapshot: DubbingProjectFile?,
        preferredBaseDirectory: URL?,
        additionalLogURLs: [URL]
    ) throws -> URL {
        let createdAt = dateProvider()
        let identifier = makeIdentifier(from: createdAt)
        let title = sanitizeTitle(draft.title, fallback: defaultTitle(for: editorState))
        let rootURL = reportsRootURL(preferredBaseDirectory: preferredBaseDirectory)
        try fileManager.createDirectory(at: rootURL, withIntermediateDirectories: true, attributes: nil)

        let folderName = makeFolderName(identifier: identifier, title: title)
        let reportDirectoryURL = rootURL.appendingPathComponent(folderName, isDirectory: true)
        try fileManager.createDirectory(at: reportDirectoryURL, withIntermediateDirectories: true, attributes: nil)

        let context = BugReportContext(
            createdAt: createdAt,
            appVersion: environment.appVersion,
            buildNumber: environment.buildNumber,
            osVersion: environment.osVersion,
            reportIdentifier: identifier,
            draft: BugReportDraftPayload(draft: draft),
            editor: editorState,
            ui: uiState
        )

        var attachmentLines: [String] = []
        attachmentLines.reserveCapacity(8)

        let reportJSONURL = reportDirectoryURL.appendingPathComponent("report.json")
        let reportJSONData = try encoder.encode(context)
        try reportJSONData.write(to: reportJSONURL, options: .atomic)
        attachmentLines.append("- `report.json`")

        let noteURL = reportDirectoryURL.appendingPathComponent("note.md")
        let noteContents = buildNoteMarkdown(for: context)
        try noteContents.write(to: noteURL, atomically: true, encoding: .utf8)
        attachmentLines.append("- `note.md`")

        if draft.includeWindowScreenshot, let screenshotPNGData {
            let screenshotURL = reportDirectoryURL.appendingPathComponent("window.png")
            try screenshotPNGData.write(to: screenshotURL, options: .atomic)
            attachmentLines.append("- `window.png`")
        }

        if draft.includeProjectSnapshot, let projectSnapshot {
            let snapshotURL = reportDirectoryURL.appendingPathComponent("project-snapshot.dbeproj")
            try projectService.save(projectSnapshot, to: snapshotURL)
            attachmentLines.append("- `project-snapshot.dbeproj`")
        }

        if draft.includeLogs {
            let copiedLogLines = try copyLogs(additionalLogURLs, into: reportDirectoryURL)
            attachmentLines.append(contentsOf: copiedLogLines)
        }

        let readmeURL = reportDirectoryURL.appendingPathComponent("README.md")
        let readmeContents = buildReadmeMarkdown(for: context, attachmentLines: attachmentLines)
        try readmeContents.write(to: readmeURL, atomically: true, encoding: .utf8)

        try rebuildIndex(in: rootURL)
        return reportDirectoryURL
    }

    private func copyLogs(_ urls: [URL], into reportDirectoryURL: URL) throws -> [String] {
        let uniqueURLs = deduplicateExistingFileURLs(urls)
        guard !uniqueURLs.isEmpty else { return [] }

        let logsDirectoryURL = reportDirectoryURL.appendingPathComponent("logs", isDirectory: true)
        try fileManager.createDirectory(at: logsDirectoryURL, withIntermediateDirectories: true, attributes: nil)

        var lines: [String] = []
        for url in uniqueURLs {
            let destinationURL = logsDirectoryURL.appendingPathComponent(url.lastPathComponent)
            if fileManager.fileExists(atPath: destinationURL.path) {
                try fileManager.removeItem(at: destinationURL)
            }
            try fileManager.copyItem(at: url, to: destinationURL)
            lines.append("- `logs/\(url.lastPathComponent)`")
        }
        return lines
    }

    private func deduplicateExistingFileURLs(_ urls: [URL]) -> [URL] {
        var seen = Set<String>()
        var uniqueURLs: [URL] = []
        for url in urls {
            let standardized = url.standardizedFileURL
            let path = standardized.path
            guard !seen.contains(path) else { continue }
            guard fileManager.fileExists(atPath: path) else { continue }
            seen.insert(path)
            uniqueURLs.append(standardized)
        }
        return uniqueURLs
    }

    private func rebuildIndex(in rootURL: URL) throws {
        let candidateDirectories = try fileManager.contentsOfDirectory(
            at: rootURL,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        )

        var entries: [BugReportIndexEntry] = []
        for directoryURL in candidateDirectories {
            let values = try directoryURL.resourceValues(forKeys: [.isDirectoryKey])
            guard values.isDirectory == true else { continue }

            let reportJSONURL = directoryURL.appendingPathComponent("report.json")
            guard fileManager.fileExists(atPath: reportJSONURL.path) else { continue }

            do {
                let data = try Data(contentsOf: reportJSONURL, options: [.mappedIfSafe])
                let context = try decoder.decode(BugReportContext.self, from: data)
                entries.append(
                    BugReportIndexEntry(
                        identifier: context.reportIdentifier,
                        createdAt: context.createdAt,
                        title: sanitizeTitle(context.draft.title, fallback: defaultTitle(for: context.editor)),
                        folderName: directoryURL.lastPathComponent,
                        documentTitle: context.editor.documentTitle,
                        projectPath: context.editor.currentProjectPath,
                        selectedLineIndex: context.editor.selectedLine?.index,
                        selectedLineSpeaker: context.editor.selectedLine?.speaker,
                        hasWindowScreenshot: fileManager.fileExists(atPath: directoryURL.appendingPathComponent("window.png").path),
                        hasProjectSnapshot: fileManager.fileExists(atPath: directoryURL.appendingPathComponent("project-snapshot.dbeproj").path),
                        hasLogs: fileManager.fileExists(atPath: directoryURL.appendingPathComponent("logs").path),
                        hasArchive: fileManager.fileExists(
                            atPath: rootURL
                                .appendingPathComponent(directoryURL.lastPathComponent)
                                .appendingPathExtension("zip")
                                .path
                        )
                    )
                )
            } catch {
                continue
            }
        }

        entries.sort { lhs, rhs in
            if lhs.createdAt == rhs.createdAt {
                return lhs.folderName > rhs.folderName
            }
            return lhs.createdAt > rhs.createdAt
        }

        let indexJSONURL = rootURL.appendingPathComponent("index.json")
        let indexJSONData = try encoder.encode(entries)
        try indexJSONData.write(to: indexJSONURL, options: .atomic)

        let indexMarkdownURL = rootURL.appendingPathComponent("INDEX.md")
        let indexMarkdown = buildIndexMarkdown(entries: entries)
        try indexMarkdown.write(to: indexMarkdownURL, atomically: true, encoding: .utf8)

        let indexHTMLURL = rootURL.appendingPathComponent("index.html")
        let indexHTML = buildIndexHTML(entries: entries)
        try indexHTML.write(to: indexHTMLURL, atomically: true, encoding: .utf8)
    }

    private func buildNoteMarkdown(for context: BugReportContext) -> String {
        var lines: [String] = []
        lines.append("# \(sanitizeTitle(context.draft.title, fallback: defaultTitle(for: context.editor)))")
        lines.append("")

        if !context.draft.reproductionSteps.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            lines.append("## Kroky k reprodukci")
            lines.append(context.draft.reproductionSteps)
            lines.append("")
        }

        if !context.draft.expectedBehavior.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            lines.append("## Ocekavane chovani")
            lines.append(context.draft.expectedBehavior)
            lines.append("")
        }

        if !context.draft.actualBehavior.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            lines.append("## Skutecne chovani")
            lines.append(context.draft.actualBehavior)
            lines.append("")
        }

        if lines.last?.isEmpty == true {
            lines.removeLast()
        }
        return lines.joined(separator: "\n")
    }

    private func buildReadmeMarkdown(
        for context: BugReportContext,
        attachmentLines: [String]
    ) -> String {
        let title = sanitizeTitle(context.draft.title, fallback: defaultTitle(for: context.editor))
        let selectionSummary = lineSummary(context.editor.selectedLine) ?? "zadna"
        var lines: [String] = [
            "# \(title)",
            "",
            "- ID: `\(context.reportIdentifier)`",
            "- Vytvoreno: `\(context.createdAt.ISO8601Format())`",
            "- App verze: `\(context.appVersion) (\(context.buildNumber))`",
            "- OS: `\(context.osVersion)`",
            "- Dokument: `\(context.editor.documentTitle)`",
            "- Replik: `\(context.editor.lineCount)`",
            "- Vybrana replika: \(selectionSummary)",
            ""
        ]

        if let projectPath = context.editor.currentProjectPath {
            lines.append("- Projekt: `\(projectPath)`")
        }
        if let sourceWordPath = context.editor.sourceWordPath {
            lines.append("- Word: `\(sourceWordPath)`")
        }
        if let sourceVideoPath = context.editor.sourceVideoPath {
            lines.append("- Video: `\(sourceVideoPath)`")
        }
        lines.append("")

        if !attachmentLines.isEmpty {
            lines.append("## Prilohy")
            lines.append(contentsOf: attachmentLines)
            lines.append("")
        }

        lines.append("## UI stav")
        lines.append("- Pravý panel: `\(context.ui.rightPaneTab)`")
        lines.append("- Find query: `\(context.ui.findQuery)`")
        lines.append("- Replace query: `\(context.ui.replaceQuery)`")
        lines.append("- Jen chrono chyby: `\(context.ui.showOnlyChronologyIssues)`")
        lines.append("- Jen bez charakteru: `\(context.ui.showOnlyMissingSpeakerIssues)`")
        lines.append("- Filtr postav: `\(context.ui.selectedCharacterFilters.joined(separator: ", "))`")

        return lines.joined(separator: "\n")
    }

    private func buildIndexMarkdown(entries: [BugReportIndexEntry]) -> String {
        var lines = [
            "# DubbingEditor Bug Reports",
            "",
            "Celkem reportu: \(entries.count)",
            ""
        ]

        for entry in entries {
            lines.append(
                "- [\(entry.identifier) - \(entry.title)](./\(entry.folderName)/README.md) | dokument: `\(entry.documentTitle)`"
            )
        }

        return lines.joined(separator: "\n")
    }

    private func buildIndexHTML(entries: [BugReportIndexEntry]) -> String {
        let cardsHTML = entries.map { entry in
            buildIndexCardHTML(for: entry)
        }.joined(separator: "\n")

        return """
        <!doctype html>
        <html lang="cs">
        <head>
          <meta charset="utf-8">
          <meta name="viewport" content="width=device-width, initial-scale=1">
          <title>DubbingEditor Bug Reports</title>
          <style>
            :root {
              color-scheme: light dark;
              --bg: #111318;
              --panel: #1a1f29;
              --panel-alt: #232a36;
              --text: #eef2f7;
              --muted: #a4afbf;
              --accent: #4f8cff;
              --border: rgba(255,255,255,0.08);
            }
            * { box-sizing: border-box; }
            body {
              margin: 0;
              font-family: -apple-system, BlinkMacSystemFont, sans-serif;
              background: linear-gradient(180deg, #0f131a 0%, #151b25 100%);
              color: var(--text);
            }
            .wrap {
              max-width: 1440px;
              margin: 0 auto;
              padding: 32px 24px 48px;
            }
            .hero {
              display: flex;
              align-items: end;
              justify-content: space-between;
              gap: 24px;
              margin-bottom: 24px;
            }
            h1 {
              margin: 0;
              font-size: 32px;
              line-height: 1.1;
            }
            .meta {
              margin-top: 8px;
              color: var(--muted);
              font-size: 14px;
            }
            .controls {
              display: flex;
              gap: 12px;
              align-items: center;
              margin-bottom: 20px;
              flex-wrap: wrap;
            }
            .search {
              min-width: 280px;
              flex: 1;
              background: var(--panel);
              border: 1px solid var(--border);
              color: var(--text);
              padding: 12px 14px;
              border-radius: 12px;
              outline: none;
            }
            .button {
              display: inline-flex;
              align-items: center;
              justify-content: center;
              gap: 8px;
              padding: 12px 14px;
              border-radius: 12px;
              color: var(--text);
              text-decoration: none;
              background: var(--panel);
              border: 1px solid var(--border);
            }
            .grid {
              display: grid;
              grid-template-columns: repeat(auto-fill, minmax(360px, 1fr));
              gap: 16px;
            }
            .card {
              background: rgba(18, 22, 29, 0.92);
              border: 1px solid var(--border);
              border-radius: 18px;
              overflow: hidden;
              box-shadow: 0 18px 40px rgba(0,0,0,0.22);
            }
            .thumb {
              display: block;
              width: 100%;
              aspect-ratio: 16 / 9;
              object-fit: cover;
              background: #0b0e14;
              border-bottom: 1px solid var(--border);
            }
            .thumb-placeholder {
              display: flex;
              align-items: center;
              justify-content: center;
              width: 100%;
              aspect-ratio: 16 / 9;
              color: var(--muted);
              background: linear-gradient(135deg, #182132 0%, #0c1018 100%);
              border-bottom: 1px solid var(--border);
              font-size: 14px;
              letter-spacing: 0.02em;
            }
            .content {
              padding: 16px;
            }
            .title {
              margin: 0 0 6px;
              font-size: 18px;
              line-height: 1.25;
            }
            .subtitle {
              margin: 0 0 12px;
              color: var(--muted);
              font-size: 13px;
            }
            .chips {
              display: flex;
              flex-wrap: wrap;
              gap: 8px;
              margin-bottom: 14px;
            }
            .chip {
              padding: 6px 9px;
              border-radius: 999px;
              background: var(--panel-alt);
              color: var(--muted);
              font-size: 12px;
              border: 1px solid var(--border);
            }
            .links {
              display: flex;
              flex-wrap: wrap;
              gap: 10px;
            }
            .links a {
              color: var(--accent);
              text-decoration: none;
              font-size: 14px;
            }
            .empty {
              padding: 32px;
              border-radius: 18px;
              background: rgba(18, 22, 29, 0.72);
              border: 1px dashed var(--border);
              color: var(--muted);
              text-align: center;
            }
          </style>
        </head>
        <body>
          <div class="wrap">
            <div class="hero">
              <div>
                <h1>DubbingEditor Bug Reports</h1>
                <div class="meta">Celkem reportu: \(entries.count)</div>
              </div>
              <a class="button" href="./INDEX.md">Otevrit markdown index</a>
            </div>

            <div class="controls">
              <input id="search" class="search" type="search" placeholder="Filtrovat podle nazvu, dokumentu nebo speakeru..." oninput="filterCards()">
            </div>

            <div id="grid" class="grid">
              \(cardsHTML.isEmpty ? "<div class=\"empty\">Zatim tu nejsou zadne bug reporty.</div>" : cardsHTML)
            </div>
          </div>

          <script>
            function filterCards() {
              const query = document.getElementById('search').value.toLowerCase().trim();
              for (const card of document.querySelectorAll('.card')) {
                const haystack = (card.dataset.search || '').toLowerCase();
                card.style.display = haystack.includes(query) ? '' : 'none';
              }
            }
          </script>
        </body>
        </html>
        """
    }

    private func buildIndexCardHTML(for entry: BugReportIndexEntry) -> String {
        let searchTokens = [
            entry.identifier,
            entry.title,
            entry.documentTitle,
            entry.selectedLineSpeaker ?? "",
            entry.selectedLineIndex.map(String.init) ?? ""
        ].joined(separator: " ").htmlEscaped()

        let thumbHTML: String
        if entry.hasWindowScreenshot {
            thumbHTML = """
            <a href="./\(entry.folderName)/window.png">
              <img class="thumb" src="./\(entry.folderName)/window.png" alt="Screenshot \(entry.identifier)">
            </a>
            """
        } else {
            thumbHTML = "<div class=\"thumb-placeholder\">Bez screenshotu</div>"
        }

        var chips: [String] = [
            "<span class=\"chip\">\(dashboardDateFormatter.string(from: entry.createdAt).htmlEscaped())</span>",
            "<span class=\"chip\">\(entry.documentTitle.htmlEscaped())</span>"
        ]

        if let selectedLineIndex = entry.selectedLineIndex {
            let speaker = (entry.selectedLineSpeaker?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false)
                ? " · \(entry.selectedLineSpeaker!.htmlEscaped())"
                : ""
            chips.append("<span class=\"chip\">Replika \(selectedLineIndex)\(speaker)</span>")
        }
        if entry.hasLogs {
            chips.append("<span class=\"chip\">Logy</span>")
        }
        if entry.hasProjectSnapshot {
            chips.append("<span class=\"chip\">Snapshot projektu</span>")
        }
        if entry.hasArchive {
            chips.append("<span class=\"chip\">ZIP</span>")
        }

        var links: [String] = [
            "<a href=\"./\(entry.folderName)/README.md\">README</a>",
            "<a href=\"./\(entry.folderName)/note.md\">Poznamka</a>",
            "<a href=\"./\(entry.folderName)/report.json\">JSON</a>"
        ]
        if entry.hasWindowScreenshot {
            links.append("<a href=\"./\(entry.folderName)/window.png\">Screenshot</a>")
        }
        if entry.hasProjectSnapshot {
            links.append("<a href=\"./\(entry.folderName)/project-snapshot.dbeproj\">Snapshot projektu</a>")
        }
        if entry.hasArchive {
            links.append("<a href=\"./\(entry.folderName).zip\">ZIP</a>")
        }

        return """
        <article class="card" data-search="\(searchTokens)">
          \(thumbHTML)
          <div class="content">
            <h2 class="title">\(entry.title.htmlEscaped())</h2>
            <p class="subtitle">\(entry.identifier.htmlEscaped())</p>
            <div class="chips">\(chips.joined(separator: ""))</div>
            <div class="links">\(links.joined(separator: ""))</div>
          </div>
        </article>
        """
    }

    private func defaultTitle(for editorState: BugReportEditorState) -> String {
        if let selectedLine = editorState.selectedLine {
            if !selectedLine.speaker.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                return "Bug u repliky \(selectedLine.index) - \(selectedLine.speaker)"
            }
            return "Bug u repliky \(selectedLine.index)"
        }
        return "Bug report - \(editorState.documentTitle)"
    }

    private func sanitizeTitle(_ title: String, fallback: String) -> String {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? fallback : trimmed
    }

    private func makeIdentifier(from date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "yyyyMMdd-HHmmss"
        return "BR-\(formatter.string(from: date))-\(UUID().uuidString.prefix(8))"
    }

    private func makeFolderName(identifier: String, title: String) -> String {
        let normalizedTitle = title.lowercased()
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-"))
        let slug = normalizedTitle
            .folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .current)
            .replacingOccurrences(of: " ", with: "-")
            .unicodeScalars
            .map { allowed.contains($0) ? Character($0) : "-" }
            .reduce(into: "") { partialResult, character in
                if character == "-", partialResult.last == "-" {
                    return
                }
                partialResult.append(character)
            }
            .trimmingCharacters(in: CharacterSet(charactersIn: "-"))

        let suffix = slug.isEmpty ? "report" : String(slug.prefix(48))
        return "\(identifier)-\(suffix)"
    }

    private func lineSummary(_ line: BugReportLineContext?) -> String? {
        guard let line else { return nil }
        let speaker = line.speaker.trimmingCharacters(in: .whitespacesAndNewlines)
        if speaker.isEmpty {
            return "`#\(line.index)`"
        }
        return "`#\(line.index)` `\(speaker)`"
    }
}

private extension String {
    func htmlEscaped() -> String {
        self
            .replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
            .replacingOccurrences(of: "\"", with: "&quot;")
            .replacingOccurrences(of: "'", with: "&#39;")
    }
}
