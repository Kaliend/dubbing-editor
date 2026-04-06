import Foundation
#if canImport(XCTest)
import XCTest
@testable import DubbingEditor

final class ProjectServiceTests: XCTestCase {
    func testSaveAndLoadV5PreservesSettingsAndSpeakerColorOverrides() throws {
        let service = ProjectService()
        let lineID = UUID(uuidString: "AAAAAAAA-BBBB-CCCC-DDDD-EEEEEEEEEEEE")!
        let line = DialogueLine(
            id: lineID,
            index: 1,
            speaker: "TRINITY",
            text: "Ahoj",
            startTimecode: "00:00:01:00",
            endTimecode: "00:00:02:00"
        )
        let payload = DubbingProjectFile(
            savedAt: Date(timeIntervalSince1970: 1_700_000_000),
            documentTitle: "Test Project",
            fps: 25,
            lines: [line],
            selectedLineID: lineID,
            highlightedLineID: lineID,
            playbackPositionSeconds: 123.45,
            sourceWordPath: "/tmp/source.docm",
            sourceVideoPath: "/tmp/source.mp4",
            sourceExternalAudioPath: "/tmp/source.wav",
            settings: DubbingProjectSettings(
                shortcuts: DubbingProjectShortcutSettings(
                    addLine: "cmd+shift+n",
                    enterEdit: "enter",
                    playPause: "space",
                    rewindReplay: "option+space",
                    seekBackward: "option+left",
                    seekForward: "option+right",
                    captureStartTC: "enter",
                    captureEndTC: "shift+enter",
                    moveUp: "up",
                    moveDown: "down",
                    toggleLoop: "option+l",
                    undo: "cmd+z",
                    redo: "cmd+shift+z"
                ),
                view: DubbingProjectViewSettings(
                    isLightModeEnabled: true,
                    showValidationIssues: false,
                    showOnlyIssues: false
                ),
                playbackSeekStepSeconds: 0.5,
                videoOffsetSeconds: -1.25,
                muteVideoAudio: true,
                muteExternalAudio: false,
                speakerColorOverridesByKey: [
                    "TRINITY": SpeakerColorPaletteID.cobalt.rawValue
                ]
            )
        )

        let url = makeTemporaryProjectURL(name: "v2-roundtrip")
        defer { try? FileManager.default.removeItem(at: url) }

        try service.save(payload, to: url)
        let loaded = try service.load(from: url)

        XCTAssertEqual(loaded.schemaVersion, 5)
        XCTAssertEqual(loaded.documentTitle, payload.documentTitle)
        XCTAssertEqual(loaded.fps, payload.fps)
        XCTAssertEqual(loaded.lines, payload.lines)
        XCTAssertEqual(loaded.selectedLineID, payload.selectedLineID)
        XCTAssertEqual(loaded.highlightedLineID, payload.highlightedLineID)
        XCTAssertEqual(loaded.playbackPositionSeconds, payload.playbackPositionSeconds, accuracy: 0.0001)
        XCTAssertEqual(loaded.sourceWordPath, payload.sourceWordPath)
        XCTAssertEqual(loaded.sourceVideoPath, payload.sourceVideoPath)
        XCTAssertEqual(loaded.sourceExternalAudioPath, payload.sourceExternalAudioPath)
        XCTAssertEqual(loaded.settings?.view?.isLightModeEnabled, true)
        XCTAssertEqual(loaded.settings?.shortcuts?.toggleLoop, "option+l")
        XCTAssertEqual(loaded.settings?.shortcuts?.addLine, "cmd+shift+n")
        XCTAssertEqual(loaded.settings?.shortcuts?.seekBackward, "option+left")
        XCTAssertEqual(loaded.settings?.shortcuts?.seekForward, "option+right")
        XCTAssertEqual(loaded.settings?.shortcuts?.captureStartTC, "enter")
        XCTAssertEqual(loaded.settings?.shortcuts?.captureEndTC, "shift+enter")
        XCTAssertEqual(loaded.settings?.playbackSeekStepSeconds, 0.5, accuracy: 0.0001)
        XCTAssertEqual(loaded.settings?.videoOffsetSeconds, -1.25, accuracy: 0.0001)
        XCTAssertEqual(loaded.settings?.muteVideoAudio, true)
        XCTAssertEqual(loaded.settings?.muteExternalAudio, false)
        XCTAssertEqual(
            loaded.settings?.speakerColorOverridesByKey?["TRINITY"],
            SpeakerColorPaletteID.cobalt.rawValue
        )
    }

    func testLoadV1ProjectWithoutSettings() throws {
        let lineID = UUID(uuidString: "11111111-2222-3333-4444-555555555555")!
        let v1JSON = """
        {
          "schemaVersion": 1,
          "savedAt": "2026-02-13T10:15:30Z",
          "documentTitle": "Legacy Project",
          "fps": 25,
          "lines": [
            {
              "id": "\(lineID.uuidString)",
              "index": 1,
              "speaker": "CYPHER",
              "text": "Legacy text",
              "startTimecode": "00:00:03:00",
              "endTimecode": "00:00:05:00"
            }
          ],
          "selectedLineID": "\(lineID.uuidString)",
          "highlightedLineID": "\(lineID.uuidString)",
          "sourceWordPath": "/tmp/legacy.docm",
          "sourceVideoPath": "/tmp/legacy.mp4"
        }
        """

        let url = makeTemporaryProjectURL(name: "v1-compat")
        defer { try? FileManager.default.removeItem(at: url) }
        try v1JSON.data(using: .utf8)?.write(to: url, options: .atomic)

        let loaded = try ProjectService().load(from: url)

        XCTAssertEqual(loaded.schemaVersion, 1)
        XCTAssertEqual(loaded.documentTitle, "Legacy Project")
        XCTAssertEqual(loaded.lines.count, 1)
        XCTAssertEqual(loaded.lines[0].text, "Legacy text")
        XCTAssertNil(loaded.settings)
    }

    func testLoadLegacyViewSettingsDefaultsNewValidationFlagsToTrue() throws {
        let lineID = UUID(uuidString: "99999999-2222-3333-4444-555555555555")!
        let json = """
        {
          "schemaVersion": 3,
          "savedAt": "2026-02-13T10:15:30Z",
          "documentTitle": "Legacy View Settings",
          "fps": 25,
          "lines": [
            {
              "id": "\(lineID.uuidString)",
              "index": 1,
              "speaker": "A",
              "text": "Text",
              "startTimecode": "00:00:03:00",
              "endTimecode": "00:00:05:00"
            }
          ],
          "settings": {
            "view": {
              "isLightModeEnabled": true,
              "showValidationIssues": true,
              "showOnlyIssues": false
            }
          }
        }
        """

        let url = makeTemporaryProjectURL(name: "legacy-view-v3")
        defer { try? FileManager.default.removeItem(at: url) }
        try json.data(using: .utf8)?.write(to: url, options: .atomic)

        let loaded = try ProjectService().load(from: url)
        XCTAssertEqual(loaded.settings?.view?.validateMissingSpeaker, true)
        XCTAssertEqual(loaded.settings?.view?.validateMissingStartTC, true)
        XCTAssertEqual(loaded.settings?.view?.validateMissingEndTC, true)
        XCTAssertEqual(loaded.settings?.view?.validateInvalidTC, true)
    }

    private func makeTemporaryProjectURL(name: String) -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("\(name)-\(UUID().uuidString)")
            .appendingPathExtension("dbeproj")
    }
}
#endif
