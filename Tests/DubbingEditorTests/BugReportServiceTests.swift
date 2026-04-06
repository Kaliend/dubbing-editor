import Foundation
#if canImport(XCTest)
import XCTest
@testable import DubbingEditor

final class BugReportServiceTests: XCTestCase {
    func testReportsRootURLUsesPreferredBaseDirectory() {
        let baseURL = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        let service = makeService()

        let rootURL = service.reportsRootURL(preferredBaseDirectory: baseURL)

        XCTAssertEqual(rootURL, baseURL.appendingPathComponent("Bug Reports", isDirectory: true))
    }

    func testCreateReportWritesExpectedBundleFiles() throws {
        let tempRootURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("bug-report-tests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempRootURL, withIntermediateDirectories: true, attributes: nil)
        defer { try? FileManager.default.removeItem(at: tempRootURL) }

        let logURL = tempRootURL.appendingPathComponent("focus.log")
        try "focus debug".write(to: logURL, atomically: true, encoding: .utf8)

        let service = makeService(appSupportRootURL: tempRootURL)
        let reportURL = try service.createReport(
            draft: BugReportDraft(
                title: "Mazani repliky maze spatny radek",
                reproductionSteps: "1. Oznac repliku\n2. Stiskni Backspace",
                expectedBehavior: "Smaze se vybrana replika",
                actualBehavior: "Smaze se jina replika",
                includeWindowScreenshot: true,
                includeLogs: true,
                includeProjectSnapshot: true
            ),
            editorState: sampleEditorState(projectPath: "/tmp/project.dbeproj"),
            uiState: BugReportUIState(
                rightPaneTab: "text",
                findQuery: "sheriff",
                replaceQuery: "",
                showOnlyChronologyIssues: false,
                showOnlyMissingSpeakerIssues: true,
                selectedCharacterFilters: ["ETTA", "SHERIFF TAYLOR"]
            ),
            screenshotPNGData: Data("fake-png".utf8),
            projectSnapshot: sampleProjectSnapshot(),
            preferredBaseDirectory: tempRootURL,
            additionalLogURLs: [logURL]
        )

        XCTAssertTrue(FileManager.default.fileExists(atPath: reportURL.appendingPathComponent("report.json").path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: reportURL.appendingPathComponent("note.md").path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: reportURL.appendingPathComponent("README.md").path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: reportURL.appendingPathComponent("window.png").path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: reportURL.appendingPathComponent("project-snapshot.dbeproj").path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: reportURL.appendingPathComponent("logs/focus.log").path))

        let rootURL = tempRootURL.appendingPathComponent("Bug Reports", isDirectory: true)
        XCTAssertTrue(FileManager.default.fileExists(atPath: rootURL.appendingPathComponent("index.json").path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: rootURL.appendingPathComponent("INDEX.md").path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: rootURL.appendingPathComponent("index.html").path))

        let readme = try String(contentsOf: reportURL.appendingPathComponent("README.md"))
        XCTAssertTrue(readme.contains("Mazani repliky maze spatny radek"))
        XCTAssertTrue(readme.contains("project-snapshot.dbeproj"))
        XCTAssertTrue(readme.contains("logs/focus.log"))

        let indexHTML = try String(contentsOf: rootURL.appendingPathComponent("index.html"))
        XCTAssertTrue(indexHTML.contains("DubbingEditor Bug Reports"))
        XCTAssertTrue(indexHTML.contains("README"))
        XCTAssertTrue(indexHTML.contains("window.png"))
    }

    private func makeService(appSupportRootURL: URL? = nil) -> BugReportService {
        BugReportService(
            environment: BugReportServiceEnvironment(
                appVersion: "1.0",
                buildNumber: "42",
                osVersion: "macOS test"
            ),
            appSupportRootURL: appSupportRootURL,
            dateProvider: { Date(timeIntervalSince1970: 1_700_000_000) }
        )
    }

    private func sampleEditorState(projectPath: String?) -> BugReportEditorState {
        BugReportEditorState(
            documentTitle: "Kangaroo",
            lineCount: 455,
            selectedLineCount: 1,
            fps: 25,
            playbackPositionSeconds: 63.12,
            isLoopEnabled: false,
            isPlaybackActive: false,
            isTimecodeModeEnabled: false,
            timecodeCaptureTarget: "start",
            playbackSeekStepSeconds: 1,
            videoOffsetSeconds: 0,
            isReplayPrerollEnabled: true,
            isLightModeEnabled: false,
            showValidationIssues: true,
            showOnlyIssues: false,
            validateMissingSpeaker: true,
            validateMissingStartTC: true,
            validateMissingEndTC: true,
            validateInvalidTC: true,
            currentProjectPath: projectPath,
            sourceWordPath: "/tmp/source.docx",
            sourceVideoPath: "/tmp/video.mp4",
            selectedLine: BugReportLineContext(
                id: UUID(uuidString: "AAAAAAAA-BBBB-CCCC-DDDD-EEEEEEEEEEEE")!,
                index: 12,
                speaker: "SHERIFF TAYLOR",
                startTimecode: "01:00:00:00",
                endTimecode: "",
                textPreview: "Neni ti zima? Prinesl jsem deku."
            ),
            highlightedLine: nil,
            editingLine: nil
        )
    }

    private func sampleProjectSnapshot() -> DubbingProjectFile {
        let line = DialogueLine(
            id: UUID(uuidString: "AAAAAAAA-BBBB-CCCC-DDDD-EEEEEEEEEEEE")!,
            index: 12,
            speaker: "SHERIFF TAYLOR",
            text: "Neni ti zima? Prinesl jsem deku.",
            startTimecode: "01:00:00:00",
            endTimecode: ""
        )
        return DubbingProjectFile(
            savedAt: Date(timeIntervalSince1970: 1_700_000_000),
            documentTitle: "Kangaroo",
            fps: 25,
            lines: [line],
            selectedLineID: line.id,
            highlightedLineID: line.id,
            playbackPositionSeconds: 63.12,
            sourceWordPath: "/tmp/source.docx",
            sourceVideoPath: "/tmp/video.mp4",
            settings: nil
        )
    }
}
#endif
