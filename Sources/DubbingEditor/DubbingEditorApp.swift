import AppKit
import SwiftUI

@main
struct DubbingEditorApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var model = EditorViewModel()
    @AppStorage("ui_color_scheme_mode") private var colorSchemeModeRaw = "system"

    private var preferredColorScheme: ColorScheme? {
        switch colorSchemeModeRaw {
        case "light":
            return .light
        case "dark":
            return .dark
        default:
            return nil
        }
    }

    var body: some Scene {
        WindowGroup {
            ContentView(model: model)
                .frame(minWidth: 1280, minHeight: 760)
                .preferredColorScheme(preferredColorScheme)
        }
        .windowResizability(.contentMinSize)
        .defaultSize(width: 1500, height: 900)
        .commands {
            EditorMenuCommands(model: model)
        }
        Settings {
            AppSettingsView(model: model, colorSchemeModeRaw: $colorSchemeModeRaw)
                .frame(width: 640, height: 560)
                .preferredColorScheme(preferredColorScheme)
        }
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)
        DispatchQueue.main.async {
            NSApp.activate(ignoringOtherApps: true)
        }
    }
}

private struct EditorMenuCommands: Commands {
    @ObservedObject var model: EditorViewModel
    @AppStorage("shortcut_add_line") private var shortcutAddLine = "cmd+shift+n"

    var body: some Commands {
        CommandGroup(after: .newItem) {
            Button("Import Word...") {
                model.promptImportWord()
            }
            .disabled(model.isImportingWord)

            Button("Import Video...") {
                model.promptImportVideo()
            }

            Button("Import External Audio...") {
                model.promptImportExternalAudio()
            }
            .disabled(model.videoURL == nil)

            Divider()

            Button("Nova replika") {
                model.insertNewLineAfterSelection()
            }
            .keyboardShortcutIfValid(shortcutAddLine)
            .disabled(model.isImportingWord)

            Divider()

            Button("Rebuild Waveform") {
                model.rebuildWaveformForCurrentVideo()
            }
            .disabled(model.videoURL == nil || model.isBuildingWaveform)

            Button("Delete Waveform Cache") {
                model.deleteWaveformCacheForCurrentVideo()
            }
            .disabled(model.videoURL == nil || !model.hasAnyWaveformCache || model.isBuildingWaveform)

            Divider()

            Button("Open Project...") {
                model.promptOpenProject()
            }

            Menu("Open Recent...") {
                if model.recentProjectURLs.isEmpty {
                    Text("Zadne nedavne projekty")
                } else {
                    ForEach(model.recentProjectURLs, id: \.path) { url in
                        Button(url.lastPathComponent) {
                            model.openRecentProject(url)
                        }
                        .help(url.path)
                    }
                    Divider()
                    Button("Clear Menu") {
                        model.clearRecentProjects()
                    }
                }
            }

            Button("Ulozit") {
                model.saveProject()
            }
            .keyboardShortcut("s", modifiers: [.command])
            .disabled(model.lines.isEmpty && model.videoURL == nil)

            Button("Ulozit jako...") {
                model.promptSaveProjectAs()
            }
            .keyboardShortcut("s", modifiers: [.command, .shift])
            .disabled(model.lines.isEmpty && model.videoURL == nil)

            Divider()

            Button("Export DOCX...") {
                model.requestExportDocxFlow()
            }
            .disabled(model.lines.isEmpty || model.isImportingWord)
        }

        CommandGroup(after: .toolbar) {
            Divider()
            Button("Najit a nahradit...") {
                NotificationCenter.default.post(name: .openFindReplacePanel, object: nil)
            }
            .keyboardShortcut("f", modifiers: [.command])
            Button("TC Chrono chyby...") {
                NotificationCenter.default.post(name: .openTCChronologyPanel, object: nil)
            }
            Button("Postavy...") {
                NotificationCenter.default.post(name: .openSpeakerStatsPanel, object: nil)
            }
            Button("Barvy postav...") {
                NotificationCenter.default.post(name: .openSpeakerColorsPanel, object: nil)
            }
            Button("Export postav do CSV...") {
                model.promptExportSpeakerStatisticsCSV()
            }
            .disabled(model.lines.isEmpty || model.isImportingWord)
            Divider()
            Button("Nastaveni...") {
                SettingsWindowPresenter.show(model: model)
            }
        }

        CommandMenu("Support") {
            Button("Nahlasit bug...") {
                NotificationCenter.default.post(name: .openBugReportSheet, object: nil)
            }
            .disabled(model.isImportingWord)

            Button("Otevrit bug dashboard") {
                model.openBugReportsDashboard()
            }

            Button("Otevrit slozku reportu") {
                model.openBugReportsFolder()
            }
        }

        CommandGroup(after: .pasteboard) {
            Button("Kopirovat repliky") {
                _ = model.copySelectedLinesToClipboard()
            }
            .disabled(!model.canCopySelectedLines())

            Button("Vlozit repliky") {
                _ = model.pasteReplicasFromClipboard()
            }
            .disabled(!model.canPasteReplicasFromClipboard())

            Divider()
            Button("Doplnit Start TC z predchozi (H:M)") {
                _ = model.fillMissingStartTimecodesWithPreviousHourMinute()
            }
            .disabled(model.lines.isEmpty || model.isImportingWord)
        }
    }
}
