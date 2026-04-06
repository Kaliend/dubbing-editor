import AppKit
import Combine
import OSLog
import SwiftUI
import UniformTypeIdentifiers

struct ContentView: View {
    private enum RightPaneTab: String {
        case text
        case characters
    }

    @ObservedObject var model: EditorViewModel
    @State private var keyMonitor: Any?
    @State private var mouseMonitor: Any?
    @State private var findQuery: String = ""
    @State private var replaceQuery: String = ""
    @State private var replaceStatus: String = ""
    @State private var searchMatchCursor: Int = -1
    @State private var chronoIssueCursor: Int = -1
    @State private var showOnlyChronologyIssues: Bool = false
    @State private var showOnlyMissingSpeakerIssues: Bool = false
    @State private var scrollTargetLineID: DialogueLine.ID?
    @State private var projectionResult = EditorProjectionResult()
    @State private var searchRebuildTask: Task<Void, Never>?
    @State private var lineCacheRebuildTask: Task<Void, Never>?
    @State private var metadataCacheUpdateTask: Task<Void, Never>?
    @State private var pendingDirtyLineIDs: Set<DialogueLine.ID> = []
    @State private var pendingDirtyNeedsChronologyRebuild = false
    @State private var visibleLineIDs: Set<DialogueLine.ID> = []
    @State private var devPendingClickToFocus: (lineID: DialogueLine.ID, source: String, startedAt: CFTimeInterval)?
    @State private var devPendingCommitToLinesChanged: (lineID: DialogueLine.ID, field: String, startedAt: CFTimeInterval)?
    @State private var devPendingLinesChangedToCacheDone: (kindLabel: String, startedAt: CFTimeInterval)?
    @State private var previousLineCount: Int = 0
    @State private var deferredCacheRebuildAfterEditing = false
    @State private var deferredNeedsFullCacheRebuildAfterEditing = false
    @State private var deferredSearchRebuildAfterEditing = false
    @State private var draggedLineID: DialogueLine.ID?
    @State private var dropTargetLineID: DialogueLine.ID?
    @State private var isDropAtEndActive = false
    @State private var findReplacePanel: NSPanel?
    @State private var tcChronologyPanel: NSPanel?
    @State private var speakerStatsPanel: NSPanel?
    @State private var speakerColorsPanel: NSPanel?
    @State private var isPresentingBugReportSheet = false
    @State private var bugReportSuccessMessage: String?
    @State private var findReplaceZOrderObserver: NSObjectProtocol?
    @State private var rightPaneTab: RightPaneTab = .text
    @State private var showCharacterFilterPopover = false
    @State private var selectedCharacterFilterKeys: Set<String> = []
    @State private var characterFilterQuery: String = ""
    @State private var replicaTextFocusRequestLineID: DialogueLine.ID?
    @State private var replicaTextFocusRequestToken = UUID()
    @State private var replicaTextFocusRetryTask: Task<Void, Never>?
    @State private var startTimecodeFocusRequestLineID: DialogueLine.ID?
    @State private var startTimecodeFocusRequestToken = UUID()
    @State private var startTimecodeFocusRetryTask: Task<Void, Never>?
    @State private var speakerSuggestionSelection: SpeakerSuggestionSelection?
    @State private var speakerAutocompleteState = SpeakerAutocompleteState()
    @AppStorage("shortcut_enter_edit") private var shortcutEnterEdit = "enter"
    @AppStorage("shortcut_open_replica_start_tc") private var shortcutOpenReplicaStartTC = "cmd+enter"
    @AppStorage("shortcut_add_line") private var shortcutAddLine = "cmd+shift+n"
    @AppStorage("shortcut_play_pause") private var shortcutPlayPause = "space"
    @AppStorage("shortcut_rewind_replay") private var shortcutRewindReplay = "option+space"
    @AppStorage("shortcut_seek_backward") private var shortcutSeekBackward = "option+left"
    @AppStorage("shortcut_seek_forward") private var shortcutSeekForward = "option+right"
    @AppStorage("shortcut_move_up") private var shortcutMoveUp = "up"
    @AppStorage("shortcut_move_down") private var shortcutMoveDown = "down"
    @AppStorage("shortcut_toggle_loop") private var shortcutToggleLoop = "option+l"
    @AppStorage("shortcut_capture_start_tc") private var shortcutCaptureStartTC = "enter"
    @AppStorage("shortcut_capture_end_tc") private var shortcutCaptureEndTC = "shift+enter"
    @AppStorage("shortcut_undo") private var shortcutUndo = "cmd+z"
    @AppStorage("shortcut_redo") private var shortcutRedo = "cmd+shift+z"
    @AppStorage("bug_report_recipient_email") private var bugReportRecipientEmail = "info@kiulpekidis.me"
    private let shortcutCopyReplicas = "cmd+c"
    private let shortcutPasteReplicas = "cmd+v"
    private let shortcutChronoPrev = "cmd+option+up"
    private let shortcutChronoNext = "cmd+option+down"
    private static let focusDebugLogURL = URL(fileURLWithPath: "/tmp/dubbingeditor-cmd-enter-focus.log")
    private static let focusDebugDateFormatter: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()
    private static let autosaveTimeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "cs_CZ")
        formatter.dateStyle = .none
        formatter.timeStyle = .medium
        return formatter
    }()
    private static let autosaveDateTimeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "cs_CZ")
        formatter.dateStyle = .medium
        formatter.timeStyle = .medium
        return formatter
    }()
    private static let devLogger = Logger(subsystem: "local.dubbingeditor.bundle", category: "dev.metrics")
    @State private var projectionCoordinator = EditorProjectionCoordinator()

    var body: some View {
        VStack(spacing: 0) {
            topBar
            Divider()

            HSplitView {
                leftPane
                    .frame(minWidth: 760)
                rightPane
                    .frame(minWidth: 450)
            }
        }
        .background(Color(nsColor: .windowBackgroundColor))
        .alert(
            "Chyba",
            isPresented: Binding(
                get: { model.alertMessage != nil },
                set: { visible in
                    if !visible {
                        model.alertMessage = nil
                    }
                }
            ),
            actions: {
                Button("OK", role: .cancel) {}
                    .keyboardShortcut(.defaultAction)
            },
            message: {
                Text(model.alertMessage ?? "")
            }
        )
        .alert(
            "Bug report",
            isPresented: Binding(
                get: { bugReportSuccessMessage != nil },
                set: { visible in
                    if !visible {
                        bugReportSuccessMessage = nil
                    }
                }
            ),
            actions: {
                Button("OK", role: .cancel) {}
            },
            message: {
                Text(bugReportSuccessMessage ?? "")
            }
        )
        .sheet(isPresented: $isPresentingBugReportSheet) {
            BugReportSheetView(
                destinationURL: model.bugReportsRootURL(),
                initialDraft: BugReportDraft(title: model.suggestedBugReportTitle()),
                onCreate: { draft in
                    let screenshotData = draft.includeWindowScreenshot
                        ? WindowSnapshotService.captureMainWindowPNGData()
                        : nil
                    let reportURL = try await model.createBugReport(
                        draft: draft,
                        uiState: buildBugReportUIState(),
                        screenshotPNGData: screenshotData
                    )
                    bugReportSuccessMessage = "Report byl ulozen do:\n\(reportURL.path)"
                    return reportURL
                },
                onCreateAndEmail: { draft in
                    let screenshotData = draft.includeWindowScreenshot
                        ? WindowSnapshotService.captureMainWindowPNGData()
                        : nil
                    let reportURL = try await model.createBugReport(
                        draft: draft,
                        uiState: buildBugReportUIState(),
                        screenshotPNGData: screenshotData
                    )
                    let archiveURL = try await Task.detached(priority: .utility) {
                        try BugReportEmailService().createArchive(for: reportURL)
                    }.value
                    try BugReportEmailService().composeEmail(
                        recipients: bugReportEmailRecipients(),
                        subject: bugReportEmailSubject(for: draft),
                        body: bugReportEmailBody(for: reportURL),
                        attachmentURL: archiveURL
                    )
                    bugReportSuccessMessage = "Report byl pripraven a draft e-mailu se otevrel v Mailu."
                    return reportURL
                }
            )
        }
        .onAppear {
            installKeyMonitor()
            installMouseMonitor()
            model.checkAutosaveRecoveryIfNeeded()
            previousLineCount = model.lines.count
            sanitizeCharacterFilterSelection()
            rebuildLineDependentCaches()
        }
        .onDisappear {
            removeKeyMonitor()
            removeMouseMonitor()
            searchRebuildTask?.cancel()
            lineCacheRebuildTask?.cancel()
            metadataCacheUpdateTask?.cancel()
            pendingDirtyLineIDs.removeAll()
            pendingDirtyNeedsChronologyRebuild = false
            deferredNeedsFullCacheRebuildAfterEditing = false
            deferredSearchRebuildAfterEditing = false
            devPendingClickToFocus = nil
            devPendingCommitToLinesChanged = nil
            devPendingLinesChangedToCacheDone = nil
            closeFindReplacePanel()
            closeTCChronologyPanel()
            closeSpeakerStatsPanel()
            closeSpeakerColorsPanel()
            removeFindReplaceZOrderObserver()
            replicaTextFocusRetryTask?.cancel()
            replicaTextFocusRetryTask = nil
            startTimecodeFocusRetryTask?.cancel()
            startTimecodeFocusRetryTask = nil
        }
        .onChange(of: shortcutEnterEdit) { _ in resetKeyMonitor() }
        .onChange(of: shortcutOpenReplicaStartTC) { _ in resetKeyMonitor() }
        .onChange(of: shortcutAddLine) { _ in resetKeyMonitor() }
        .onChange(of: shortcutPlayPause) { _ in resetKeyMonitor() }
        .onChange(of: shortcutRewindReplay) { _ in resetKeyMonitor() }
        .onChange(of: shortcutSeekBackward) { _ in resetKeyMonitor() }
        .onChange(of: shortcutSeekForward) { _ in resetKeyMonitor() }
        .onChange(of: shortcutMoveUp) { _ in resetKeyMonitor() }
        .onChange(of: shortcutMoveDown) { _ in resetKeyMonitor() }
        .onChange(of: shortcutToggleLoop) { _ in resetKeyMonitor() }
        .onChange(of: shortcutCaptureStartTC) { _ in resetKeyMonitor() }
        .onChange(of: shortcutCaptureEndTC) { _ in resetKeyMonitor() }
        .onChange(of: shortcutUndo) { _ in resetKeyMonitor() }
        .onChange(of: shortcutRedo) { _ in resetKeyMonitor() }
        .onChange(of: model.editingLineID) { editingLineID in
            if editingLineID == nil, deferredCacheRebuildAfterEditing {
                deferredCacheRebuildAfterEditing = false
                if deferredNeedsFullCacheRebuildAfterEditing {
                    deferredNeedsFullCacheRebuildAfterEditing = false
                    deferredSearchRebuildAfterEditing = false
                    scheduleLineDependentRebuild()
                } else if !pendingDirtyLineIDs.isEmpty {
                    flushPendingDirtyLineUpdates()
                    if deferredSearchRebuildAfterEditing {
                        deferredSearchRebuildAfterEditing = false
                        scheduleSearchCacheRebuild()
                    }
                } else if deferredSearchRebuildAfterEditing {
                    deferredSearchRebuildAfterEditing = false
                    scheduleSearchCacheRebuild()
                } else {
                    scheduleLineDependentRebuild()
                }
            }
        }
        .onChange(of: model.pendingRestoreLineID) { _ in
            if let restoreLineID = model.consumePendingRestoreLineID() {
                scrollTargetLineID = restoreLineID
            }
        }
        .onChange(of: model.lines) { _ in
            model.handleLinesDidChange()
            let changeKind = model.consumeLastLineChangeKind()
            markDevLinesChangedObserved(changeKind)
            sanitizeIndexCaches()
            let countChanged = model.lines.count != previousLineCount
            previousLineCount = model.lines.count
            if countChanged && model.editingLineID != nil {
                deferredCacheRebuildAfterEditing = true
                deferredNeedsFullCacheRebuildAfterEditing = true
                return
            }
            if shouldSuspendHeavyUpdatesWhileEditing(for: changeKind) || shouldDeferCacheUpdate(for: changeKind) {
                deferredCacheRebuildAfterEditing = true
                queueDeferredCacheUpdate(for: changeKind)
                return
            }
            markDevCachePipelineStarted(for: changeKind)
            applyLineCacheUpdate(for: changeKind)
        }
        .onChange(of: findQuery) { _ in
            searchMatchCursor = -1
            replaceStatus = ""
            if model.editingLineID != nil {
                deferredCacheRebuildAfterEditing = true
                deferredSearchRebuildAfterEditing = true
                return
            }
            scheduleSearchCacheRebuild()
        }
        .onChange(of: model.showValidationIssues) { _ in
            rebuildLineDependentCaches()
        }
        .onChange(of: model.showOnlyIssues) { _ in
            rebuildLineDependentCaches()
        }
        .onChange(of: model.validateMissingSpeaker) { _ in
            rebuildLineDependentCaches()
        }
        .onChange(of: model.validateMissingStartTC) { _ in
            rebuildLineDependentCaches()
        }
        .onChange(of: model.validateMissingEndTC) { _ in
            rebuildLineDependentCaches()
        }
        .onChange(of: model.validateInvalidTC) { _ in
            rebuildLineDependentCaches()
        }
        .onChange(of: model.isLightModeEnabled) { _ in
            rebuildLineDependentCaches()
        }
        .onChange(of: showOnlyChronologyIssues) { _ in
            rebuildDisplayedIndicesAndIssueCountCache()
        }
        .onChange(of: showOnlyMissingSpeakerIssues) { _ in
            rebuildDisplayedIndicesAndIssueCountCache()
        }
        .onChange(of: selectedCharacterFilterKeys) { _ in
            rebuildDisplayedIndicesAndIssueCountCache()
        }
        .onChange(of: showCharacterFilterPopover) { isPresented in
            if !isPresented {
                characterFilterQuery = ""
            }
        }
        .onChange(of: model.speakerDatabase) { _ in
            sanitizeCharacterFilterSelection()
        }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.willResignActiveNotification)) { _ in
            model.forceAutosaveNow()
        }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.willTerminateNotification)) { _ in
            model.handleAppWillTerminate()
        }
        .onReceive(NotificationCenter.default.publisher(for: .openFindReplacePanel)) { _ in
            openFindReplacePanel()
        }
        .onReceive(NotificationCenter.default.publisher(for: .openTCChronologyPanel)) { _ in
            openTCChronologyPanel()
        }
        .onReceive(NotificationCenter.default.publisher(for: .openSpeakerStatsPanel)) { _ in
            rightPaneTab = .characters
        }
        .onReceive(NotificationCenter.default.publisher(for: .openSpeakerColorsPanel)) { _ in
            openSpeakerColorsPanel()
        }
        .onReceive(NotificationCenter.default.publisher(for: .openBugReportSheet)) { _ in
            isPresentingBugReportSheet = true
        }
        .alert(
            "Nalezeno autosave",
            isPresented: Binding(
                get: { model.pendingAutosaveRecovery != nil },
                set: { visible in
                    if !visible {
                        model.discardPendingAutosave()
                    }
                }
            ),
            actions: {
                Button("Obnovit") {
                    model.restorePendingAutosave()
                }
                Button("Ignorovat", role: .destructive) {
                    model.discardPendingAutosave()
                }
            },
            message: {
                Text(recoveryAlertMessage())
            }
        )
    }

    private func buildBugReportUIState() -> BugReportUIState {
        BugReportUIState(
            rightPaneTab: rightPaneTab.rawValue,
            findQuery: findQuery,
            replaceQuery: replaceQuery,
            showOnlyChronologyIssues: showOnlyChronologyIssues,
            showOnlyMissingSpeakerIssues: showOnlyMissingSpeakerIssues,
            selectedCharacterFilters: selectedCharacterFilterKeys.sorted()
        )
    }

    private func bugReportEmailRecipients() -> [String] {
        bugReportRecipientEmail
            .split(whereSeparator: { [",", ";", "\n"].contains($0) })
            .map { String($0).trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }

    private func bugReportEmailSubject(for draft: BugReportDraft) -> String {
        let title = draft.title.trimmingCharacters(in: .whitespacesAndNewlines)
        let resolvedTitle = title.isEmpty ? model.suggestedBugReportTitle() : title
        return "DubbingEditor Bug: \(resolvedTitle)"
    }

    private func bugReportEmailBody(for reportURL: URL) -> String {
        [
            "Ahoj,",
            "",
            "v priloze je ZIP s bug reportem z DubbingEditoru.",
            "",
            "Lokální cesta k reportu:",
            reportURL.path,
            "",
            "Součástí reportu je screenshot, stav editoru a případně snapshot projektu."
        ].joined(separator: "\n")
    }

    private var topBar: some View {
        HStack(spacing: 10) {
            Text(model.documentTitle)
                .font(.title2.weight(.semibold))
                .lineLimit(1)

            Text("Repliky: \(model.lines.count)")
                .font(.headline)
                .padding(.leading, 6)

            if model.showValidationIssues {
                Text(problemSummaryLabel())
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            if model.isLightModeEnabled {
                Text("Light Mode")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.orange)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(
                        Capsule()
                            .fill(Color.orange.opacity(0.12))
                    )
            }

            Spacer(minLength: 20)

            Button {
                performUndoAction()
            } label: {
                shortcutButtonLabel(title: "Undo", shortcut: shortcutUndo)
            }
            .buttonStyle(.bordered)
            .disabled(!model.canUndo)
            .help(shortcutHint("Undo", shortcutUndo))

            Button {
                performRedoAction()
            } label: {
                shortcutButtonLabel(title: "Redo", shortcut: shortcutRedo)
            }
            .buttonStyle(.bordered)
            .disabled(!model.canRedo)
            .help(shortcutHint("Redo", shortcutRedo))

            Button("Nastaveni") {
                openSettingsWindow()
            }
            .buttonStyle(.bordered)

            Button {
                let newLineID = model.insertNewLineAfterSelection()
                scrollTargetLineID = newLineID
            } label: {
                shortcutButtonLabel(title: "Nova replika", shortcut: shortcutAddLine)
            }
            .buttonStyle(.bordered)
            .disabled(model.isImportingWord)
            .help(shortcutHint("Nova replika", shortcutAddLine))

            Button("Smazat repliky") {
                _ = model.deleteSelectedLines()
            }
            .buttonStyle(.bordered)
            .disabled(model.selectedLineIDs.isEmpty || model.isImportingWord)
            .help("Smaze vybrane repliky (Delete/Backspace)")

            if model.isImportingWord {
                HStack(spacing: 6) {
                    ProgressView()
                        .controlSize(.small)
                    Text("Nacitam Word...")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            if let lastAutosaveDate = model.lastAutosaveDate {
                Text("Autosave: \(Self.autosaveTimeFormatter.string(from: lastAutosaveDate))")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(.leading, 8)
            }

            if let projectURL = model.currentProjectURL {
                Text("Project: \(projectURL.lastPathComponent)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .frame(maxWidth: 220, alignment: .leading)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }

    private var leftPane: some View {
        PlaybackPanelView(model: model)
    }

    @ViewBuilder
    private var timecodeModeControls: some View {
        let missingStartCount = model.missingTimecodeCount(for: .start)
        let missingEndCount = model.missingTimecodeCount(for: .end)

        Button {
            model.isTimecodeModeEnabled.toggle()
        } label: {
            Label(model.isTimecodeModeEnabled ? "TC Mode ON" : "TC Mode OFF", systemImage: "clock.badge")
        }
        .buttonStyle(.bordered)
        .tint(model.isTimecodeModeEnabled ? .orange : .gray.opacity(0.75))
        .help(timecodeModeHelpText())

        if model.isTimecodeModeEnabled {
            Menu {
                Toggle(
                    "Auto Next",
                    isOn: Binding(
                        get: { model.isTimecodeAutoAdvanceEnabled },
                        set: { model.isTimecodeAutoAdvanceEnabled = $0 }
                    )
                )
                Toggle(
                    "Auto S/E",
                    isOn: Binding(
                        get: { model.isTimecodeAutoSwitchTargetEnabled },
                        set: { model.isTimecodeAutoSwitchTargetEnabled = $0 }
                    )
                )

                Divider()

                Button("Zapsat Start TC") {
                    model.captureStartTimecodeForSelectedLine(advanceToNext: model.isTimecodeAutoAdvanceEnabled)
                }
                .disabled(model.lines.isEmpty)
                Button("Zapsat End TC") {
                    model.captureEndTimecodeForSelectedLine(advanceToNext: model.isTimecodeAutoAdvanceEnabled)
                }
                .disabled(model.lines.isEmpty)
            } label: {
                Label("TC volby", systemImage: "slider.horizontal.3")
            }
            .buttonStyle(.bordered)

            Text("S: \(missingStartCount)  E: \(missingEndCount)")
                .font(.caption)
                .foregroundStyle(.secondary)

            Text("TC pole: vybrana replika")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private var findReplaceSheetContent: some View {
        FindReplaceSheet(
            findQuery: $findQuery,
            replaceQuery: $replaceQuery,
            matchCount: Binding(
                get: { projectionResult.searchMatchIndices.count },
                set: { _ in }
            ),
            replaceStatus: $replaceStatus,
            onPrevious: {
                jumpToSearchMatch(step: -1, releaseTextFieldFocus: false)
            },
            onNext: {
                jumpToSearchMatch(step: 1, releaseTextFieldFocus: false)
            },
            onReplaceCurrent: {
                replaceCurrentMatch()
            },
            onReplaceAll: {
                replaceAllMatches()
            },
            onClose: {
                closeFindReplacePanel()
            }
        )
    }

    private var tcChronologyPanelContent: some View {
        TCChronologyIssuesPanel(
            issues: Binding(
                get: { projectionResult.chronoStartIssues },
                set: { _ in }
            ),
            activeIndex: $chronoIssueCursor,
            previousShortcutDisplay: shortcutDisplayString(shortcutChronoPrev),
            nextShortcutDisplay: shortcutDisplayString(shortcutChronoNext),
            onPrevious: {
                jumpToChronologyIssue(step: -1)
            },
            onNext: {
                jumpToChronologyIssue(step: 1)
            },
            onSelect: { index in
                goToChronologyIssue(at: index)
            },
            onClose: {
                closeTCChronologyPanel()
            }
        )
    }

    private var speakerStatsPanelContent: some View {
        SpeakerStatsPanel(
            model: model,
            showCloseButton: true,
            onClose: {
                closeSpeakerStatsPanel()
            }
        )
    }

    private var speakerColorsPanelContent: some View {
        SpeakerColorsPanelView(
            model: model,
            showCloseButton: true,
            onClose: {
                closeSpeakerColorsPanel()
            }
        )
    }

    private var rightPane: some View {
        let activeSearchLineID = activeSearchTargetLineID()
        let displayedLineIDs: [DialogueLine.ID] = validDisplayedLineIndices().compactMap { index in
            guard model.lines.indices.contains(index) else { return nil }
            return model.lines[index].id
        }
        let speakerSuggestions = model.speakerDatabase
            .map { $0.speaker.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        let missingSpeakerCount = model.missingSpeakerCount

        return VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                Picker("Pohled", selection: $rightPaneTab) {
                    Text("Text").tag(RightPaneTab.text)
                    Text("Postavy").tag(RightPaneTab.characters)
                }
                .pickerStyle(.segmented)
                .frame(width: 220)

                Spacer(minLength: 8)

                if rightPaneTab == .text {
                    characterFilterButton
                }
            }

            if rightPaneTab == .characters {
                SpeakerStatsPanel(
                    model: model,
                    showCloseButton: false,
                    onClose: {}
                )
            } else {
                VStack(alignment: .leading, spacing: 10) {
                    HStack(spacing: 10) {
                        timecodeModeControls

                        Spacer(minLength: 8)

                Button {
                    openTCChronologyPanel()
                } label: {
                    Text("TC chyby: \(projectionResult.chronoStartIssues.count)")
                }
                .buttonStyle(.bordered)
                .tint(projectionResult.chronoStartIssues.isEmpty ? .gray : .red)
                .help("Otevrit seznam chrono chyb Start TC.")

                Button {
                    showOnlyChronologyIssues.toggle()
                } label: {
                    Text(showOnlyChronologyIssues ? "Jen chrono: ON" : "Jen chrono: OFF")
                }
                .buttonStyle(.bordered)
                .disabled(projectionResult.chronoStartIssues.isEmpty && !showOnlyChronologyIssues)
                .help("Kdyz je ON, v seznamu replik se zobrazi jen chrono chyby Start TC.")

                Button {
                    showOnlyMissingSpeakerIssues.toggle()
                } label: {
                    Text(showOnlyMissingSpeakerIssues ? "Jen bez charakteru: ON" : "Jen bez charakteru: OFF")
                }
                .buttonStyle(.bordered)
                .disabled(missingSpeakerCount == 0 && !showOnlyMissingSpeakerIssues)
                .help("Kdyz je ON, v seznamu replik se zobrazi jen repliky bez charakteru.")

                Button {
                    model.setLoopEnabled(!model.isLoopEnabled)
                } label: {
                    shortcutButtonLabel(
                        title: model.isLoopEnabled ? "Loop: ON" : "Loop: OFF",
                        shortcut: shortcutToggleLoop
                    )
                }
                .buttonStyle(.borderedProminent)
                .tint(model.isLoopEnabled ? .green : .gray)
                .help(shortcutHint(model.isLoopEnabled ? "Vypnout loop" : "Zapnout loop", shortcutToggleLoop))
            }

                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(spacing: 8) {
                            ForEach(displayedLineIDs, id: \.self) { lineID in
                                if
                                    let index = model.lineIndex(for: lineID),
                                    model.lines.indices.contains(index)
                                {
                                    let line = model.lines[index]
                                    DialogueRowView(
                                        lineID: line.id,
                                        line: $model.lines[index],
                                        fps: model.fps,
                                        hideTimecodeFrames: model.hideTimecodeFrames,
                                        isEndTimecodeFieldHidden: model.isEndTimecodeFieldHidden,
                                        isTimecodeModeEnabled: model.isTimecodeModeEnabled,
                                        isSelected: model.selectedLineIDs.contains(line.id),
                                        isEditable: model.editingLineID == line.id,
                                        isPlaybackActive: model.isPlaybackActive,
                                        replicaTextFocusRequestLineID: replicaTextFocusRequestLineID,
                                        replicaTextFocusRequestToken: replicaTextFocusRequestToken,
                                        startTimecodeFocusRequestLineID: startTimecodeFocusRequestLineID,
                                        startTimecodeFocusRequestToken: startTimecodeFocusRequestToken,
                                        isActiveSearchSelection: line.id == activeSearchLineID,
                                        hasStartChronologyIssue: projectionResult.chronoIssueLineIDs.contains(line.id),
                                        totalLineCount: model.lines.count,
                                        replicaTextFontSize: model.replicaTextFontSize,
                                        speakerColorOverridesByKey: model.speakerColorOverridesByKey,
                                        speakerSuggestions: speakerSuggestions,
                                        speakerSuggestionSelection: speakerSuggestionSelection,
                                        isDevModeEnabled: model.isDevModeEnabled,
                                        issues: issuesForRow(lineID: line.id),
                                        onSelect: { extendSelection in
                                            let selectionDebugTrace = model.beginSelectionClickDebugTrace(
                                                clickedLineID: line.id,
                                                source: extendSelection ? "shift_click" : "single_click"
                                            )
                                            markDevSelectionInteractionStarted(lineID: line.id, source: extendSelection ? "shift_click" : "single_click")
                                            model.selectLine(
                                                line,
                                                extendSelection: extendSelection,
                                                debounceSeek: true
                                            )
                                            model.finishSelectionClickDebugTrace(selectionDebugTrace)
                                        },
                                        onDoubleClick: {
                                            if !model.isTimecodeModeEnabled {
                                                let selectionDebugTrace = model.beginSelectionClickDebugTrace(
                                                    clickedLineID: line.id,
                                                    source: "double_click"
                                                )
                                                markDevSelectionInteractionStarted(lineID: line.id, source: "double_click")
                                                model.activateLineByDoubleClick(line)
                                                requestReplicaTextFocus(for: line.id)
                                                scheduleReplicaTextFocusRetries(for: line.id)
                                                model.finishSelectionClickDebugTrace(selectionDebugTrace)
                                            }
                                        },
                                        onStartTimecodeFieldTap: {
                                            _ = model.prefillEmptyTimecodeWithPreviousHourMinute(
                                                lineID: line.id,
                                                target: .start,
                                                allowOutsideTimecodeMode: model.isEditModeTimecodePrefillEnabled
                                            )
                                        },
                                        onEndTimecodeFieldTap: {
                                            _ = model.prefillEmptyTimecodeWithPreviousHourMinute(
                                                lineID: line.id,
                                                target: .end,
                                                allowOutsideTimecodeMode: model.isEditModeTimecodePrefillEnabled
                                            )
                                        },
                                        onSetStart: {
                                            model.setStartFromCurrentTime(lineID: line.id)
                                        },
                                        onSetEnd: {
                                            model.setEndFromCurrentTime(lineID: line.id)
                                        },
                                        onFocusAcquired: { field in
                                            markDevFocusAcquired(lineID: line.id, field: field)
                                            appendFocusDebugReport(
                                                "FOCUS_ACQUIRED line=\(line.index) id=\(line.id.uuidString.prefix(8)) field=\(field) editing=\(model.editingLineID == line.id) selected=\(model.selectedLineID == line.id)"
                                            )
                                            if field == "start_tc", startTimecodeFocusRequestLineID == line.id {
                                                appendFocusDebugReport(
                                                    "CMD_ENTER_REQUEST_CONSUMED line=\(line.index) id=\(line.id.uuidString.prefix(8)) token=\(startTimecodeFocusRequestToken.uuidString.prefix(8))"
                                                )
                                                startTimecodeFocusRequestLineID = nil
                                                startTimecodeFocusRetryTask?.cancel()
                                                startTimecodeFocusRetryTask = nil
                                            }
                                            if field == "text", replicaTextFocusRequestLineID == line.id {
                                                replicaTextFocusRequestLineID = nil
                                                replicaTextFocusRetryTask?.cancel()
                                                replicaTextFocusRetryTask = nil
                                                appendFocusDebugReport(
                                                    "TEXT_FOCUS_REQUEST_CONSUMED line=\(line.index) id=\(line.id.uuidString.prefix(8)) token=\(replicaTextFocusRequestToken.uuidString.prefix(8))"
                                                )
                                            }
                                        },
                                        onModelCommit: { field in
                                            markDevCommitRequested(lineID: line.id, field: field)
                                        },
                                        dragItemProvider: model.editingLineID == nil ? {
                                            draggedLineID = line.id
                                            return NSItemProvider(object: line.id.uuidString as NSString)
                                        } : nil
                                    )
                                    .id(line.id)
                                    .onAppear {
                                        handleLineVisibility(lineID: line.id, isVisible: true)
                                    }
                                    .onDisappear {
                                        handleLineVisibility(lineID: line.id, isVisible: false)
                                    }
                                    .overlay(alignment: .top) {
                                        if dropTargetLineID == line.id {
                                            Rectangle()
                                                .fill(Color.accentColor.opacity(0.95))
                                                .frame(height: 3)
                                                .padding(.horizontal, 2)
                                                .transition(.opacity)
                                        }
                                    }
                                    .onDrop(
                                        of: [UTType.text],
                                        delegate: DialogueLineDropDelegate(
                                            targetLineID: line.id,
                                            draggedLineID: $draggedLineID,
                                            dropTargetLineID: $dropTargetLineID,
                                            isDropAtEndActive: $isDropAtEndActive,
                                            model: model
                                        )
                                    )
                                }
                            }
                            RoundedRectangle(cornerRadius: 8)
                                .fill(isDropAtEndActive ? Color.accentColor.opacity(0.16) : Color.clear)
                                .overlay(alignment: .center) {
                                    if isDropAtEndActive {
                                        Text("Presunout na konec")
                                            .font(.caption.weight(.semibold))
                                            .foregroundStyle(Color.accentColor)
                                    }
                                }
                                .overlay(alignment: .top) {
                                    Rectangle()
                                        .fill(isDropAtEndActive ? Color.accentColor.opacity(0.95) : Color.secondary.opacity(0.18))
                                        .frame(height: isDropAtEndActive ? 3 : 1)
                                        .padding(.horizontal, 2)
                                }
                                .frame(height: 28)
                                .onDrop(
                                    of: [UTType.text],
                                    delegate: DialogueLineDropDelegate(
                                        targetLineID: nil,
                                        draggedLineID: $draggedLineID,
                                        dropTargetLineID: $dropTargetLineID,
                                        isDropAtEndActive: $isDropAtEndActive,
                                        model: model
                                    )
                                )
                        }
                        .padding(.vertical, 2)
                    }
                    .onChange(of: scrollTargetLineID) { targetID in
                        guard let targetID else { return }
                        if model.isLightModeEnabled {
                            proxy.scrollTo(targetID, anchor: .center)
                        } else {
                            withAnimation(.easeInOut(duration: 0.18)) {
                                proxy.scrollTo(targetID, anchor: .center)
                            }
                        }
                        DispatchQueue.main.async {
                            scrollTargetLineID = nil
                        }
                    }
                }
                .overlayPreferenceValue(SpeakerSuggestionAnchorPreferenceKey.self) { entries in
                    SpeakerSuggestionOverlayHost(
                        entries: entries,
                        visibleLineIDs: visibleLineIDs,
                        autocompleteState: speakerAutocompleteState,
                        speakerColorOverridesByKey: model.speakerColorOverridesByKey
                    ) { snapshot in
                        updateSpeakerAutocompleteState(snapshot)
                    } onSelectIndex: { index in
                        _ = commitSpeakerAutocompleteSelection(index: index)
                    }
                }
            }
        }
        }
        .padding(14)
    }

    private var characterFilterButton: some View {
        Button {
            showCharacterFilterPopover.toggle()
        } label: {
            HStack(spacing: 6) {
                Image(systemName: selectedCharacterFilterKeys.isEmpty ? "line.3.horizontal.decrease.circle" : "line.3.horizontal.decrease.circle.fill")
                if !selectedCharacterFilterKeys.isEmpty {
                    Text("\(selectedCharacterFilterKeys.count)")
                        .font(.caption.weight(.semibold))
                }
            }
        }
        .buttonStyle(.bordered)
        .help("Filtrovani postav")
        .popover(isPresented: $showCharacterFilterPopover, arrowEdge: .top) {
            characterFilterPopoverContent
        }
    }

    private var characterFilterPopoverContent: some View {
        let filteredStats = filteredSpeakerStatsForCharacterFilter()
        return VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Filtr postav")
                    .font(.headline)
                Spacer()
                Text("\(filteredStats.count)/\(model.speakerDatabase.count)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            TextField("Hledat postavu...", text: $characterFilterQuery)
                .textFieldStyle(.roundedBorder)

            Divider()

            if model.speakerDatabase.isEmpty {
                Text("V projektu zatim nejsou zadne postavy.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            } else {
                HStack(spacing: 8) {
                    Button("Vybrat vse") {
                        selectAllCharacterFilters()
                    }
                    .disabled(model.speakerDatabase.isEmpty)

                    Button("Zrusit vse") {
                        selectedCharacterFilterKeys.removeAll()
                    }
                    .disabled(selectedCharacterFilterKeys.isEmpty)
                }
                .buttonStyle(.bordered)

                ScrollView {
                    VStack(alignment: .leading, spacing: 6) {
                        if filteredStats.isEmpty {
                            Text("Zadna postava neodpovida hledani.")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                                .padding(.top, 6)
                        }
                        ForEach(filteredStats, id: \.speaker) { stat in
                            let key = EditorProjectionCoordinator.normalizedSpeakerKey(stat.speaker)
                            Toggle(isOn: Binding(
                                get: { selectedCharacterFilterKeys.contains(key) },
                                set: { isOn in
                                    if isOn {
                                        selectedCharacterFilterKeys.insert(key)
                                    } else {
                                        selectedCharacterFilterKeys.remove(key)
                                    }
                                }
                            )) {
                                HStack {
                                    Text(stat.speaker)
                                        .lineLimit(1)
                                    Spacer(minLength: 8)
                                    Text("\(stat.entries)")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                            }
                            .toggleStyle(.checkbox)
                        }
                    }
                }
                .frame(maxHeight: 280)
            }

            Divider()

            Text(selectedCharacterFilterKeys.isEmpty ? "Zobrazuji vsechny postavy." : "Aktivni filtr: \(selectedCharacterFilterKeys.count)")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(12)
        .frame(width: 320)
    }

    @ViewBuilder
    private func shortcutButtonLabel(title: String, shortcut _: String) -> some View {
        Text(title)
    }

    private func timecodeModeHelpText() -> String {
        let startShortcut = shortcutDisplayString(shortcutCaptureStartTC)
        let endShortcut = shortcutDisplayString(shortcutCaptureEndTC)
        return "TC mode: \(startShortcut) = Start + dalsi replika, \(endShortcut) = End + dalsi replika"
    }

    private func rebuildLineDependentCaches() {
        metadataCacheUpdateTask?.cancel()
        metadataCacheUpdateTask = nil
        pendingDirtyLineIDs.removeAll()
        pendingDirtyNeedsChronologyRebuild = false
        searchRebuildTask?.cancel()
        lineCacheRebuildTask?.cancel()
        let result = projectionCoordinator.rebuildAll(from: makeProjectionInput())
        applyProjectionResult(result)
        markDevCachesCompleted()
    }

    private func scheduleLineDependentRebuild() {
        metadataCacheUpdateTask?.cancel()
        metadataCacheUpdateTask = nil
        pendingDirtyLineIDs.removeAll()
        pendingDirtyNeedsChronologyRebuild = false
        lineCacheRebuildTask?.cancel()
        lineCacheRebuildTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: model.isLightModeEnabled ? 260_000_000 : 140_000_000)
            guard !Task.isCancelled else { return }
            rebuildLineDependentCaches()
        }
    }

    private func queueDeferredCacheUpdate(for changeKind: EditorViewModel.LineChangeKind) {
        switch changeKind {
        case .none:
            return
        case .singleLineText(let lineID):
            enqueuePendingDirtyLineUpdate(lineID: lineID, rebuildChronology: false, scheduleFlush: false)
        case .singleLineMetadata(let lineID):
            enqueuePendingDirtyLineUpdate(lineID: lineID, rebuildChronology: true, scheduleFlush: false)
        case .structure, .multiLine:
            deferredNeedsFullCacheRebuildAfterEditing = true
        }
    }

    private func applyLineCacheUpdate(for changeKind: EditorViewModel.LineChangeKind) {
        switch changeKind {
        case .none:
            return
        case .singleLineText(let lineID):
            enqueuePendingDirtyLineUpdate(lineID: lineID, rebuildChronology: false)
        case .singleLineMetadata(let lineID):
            enqueuePendingDirtyLineUpdate(lineID: lineID, rebuildChronology: true)
        case .structure, .multiLine:
            scheduleLineDependentRebuild()
        }
    }

    private func enqueuePendingDirtyLineUpdate(
        lineID: DialogueLine.ID,
        rebuildChronology: Bool,
        scheduleFlush: Bool = true
    ) {
        pendingDirtyLineIDs.insert(lineID)
        if rebuildChronology {
            pendingDirtyNeedsChronologyRebuild = true
        }
        if scheduleFlush {
            schedulePendingDirtyLineFlush()
        }
    }

    private func schedulePendingDirtyLineFlush() {
        metadataCacheUpdateTask?.cancel()

        let baseDelayNanoseconds: UInt64
        if model.isLightModeEnabled {
            baseDelayNanoseconds = pendingDirtyNeedsChronologyRebuild ? 200_000_000 : 140_000_000
        } else {
            baseDelayNanoseconds = pendingDirtyNeedsChronologyRebuild ? 120_000_000 : 80_000_000
        }
        metadataCacheUpdateTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: baseDelayNanoseconds)
            guard !Task.isCancelled else { return }
            flushPendingDirtyLineUpdates()
        }
    }

    private func flushPendingDirtyLineUpdates() {
        metadataCacheUpdateTask?.cancel()
        metadataCacheUpdateTask = nil

        guard !pendingDirtyLineIDs.isEmpty else { return }
        let dirtyLineIDs = pendingDirtyLineIDs
        pendingDirtyLineIDs.removeAll()
        let rebuildChronology = pendingDirtyNeedsChronologyRebuild
        pendingDirtyNeedsChronologyRebuild = false

        var updatedAnyLine = false
        for lineID in dirtyLineIDs {
            if refreshSingleLineProjection(lineID) {
                updatedAnyLine = true
            }
        }

        guard updatedAnyLine else {
            scheduleLineDependentRebuild()
            return
        }

        if rebuildChronology {
            applyProjectionResult(
                projectionCoordinator.rebuildAll(from: makeProjectionInput()),
                preserveSearchCursor: true
            )
            markDevCachesCompleted()
            return
        }

        if model.showValidationIssues || model.showOnlyIssues || showOnlyChronologyIssues || showOnlyMissingSpeakerIssues {
            rebuildDisplayedIndicesAndIssueCountCache()
        }

        if !findQuery.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            scheduleSearchCacheRebuild()
        }

        markDevCachesCompleted()
    }

    private func shouldDeferCacheUpdate(for changeKind: EditorViewModel.LineChangeKind) -> Bool {
        guard let editingLineID = model.editingLineID else { return false }

        switch changeKind {
        case .singleLineText(let lineID):
            return lineID == editingLineID
        case .singleLineMetadata(let lineID):
            return lineID == editingLineID
        default:
            return false
        }
    }

    private func shouldSuspendHeavyUpdatesWhileEditing(for changeKind: EditorViewModel.LineChangeKind) -> Bool {
        guard model.editingLineID != nil else { return false }
        switch changeKind {
        case .singleLineText, .singleLineMetadata:
            return true
        default:
            return false
        }
    }

    private func updateCachesForSingleLine(_ lineID: DialogueLine.ID, rebuildChronology: Bool) {
        guard refreshSingleLineProjection(lineID) else {
            scheduleLineDependentRebuild()
            return
        }

        if rebuildChronology {
            applyProjectionResult(
                projectionCoordinator.rebuildAll(from: makeProjectionInput()),
                preserveSearchCursor: true
            )
            markDevCachesCompleted()
            return
        }

        if model.showValidationIssues || model.showOnlyIssues || showOnlyChronologyIssues || showOnlyMissingSpeakerIssues {
            rebuildDisplayedIndicesAndIssueCountCache()
        }

        if !findQuery.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            scheduleSearchCacheRebuild()
        }

        markDevCachesCompleted()
    }

    @discardableResult
    private func refreshSingleLineProjection(_ lineID: DialogueLine.ID) -> Bool {
        var nextResult = projectionResult
        let updated = projectionCoordinator.refreshSingleLine(
            lineID,
            in: &nextResult,
            from: makeProjectionInput()
        )
        guard updated else { return false }
        projectionResult = nextResult
        return true
    }

    private func rebuildDisplayedIndicesAndIssueCountCache() {
        var nextResult = projectionResult
        projectionCoordinator.rebuildDisplayedIndicesAndIssueCount(
            in: &nextResult,
            from: makeProjectionInput()
        )
        projectionResult = nextResult
    }

    private func scheduleSearchCacheRebuild() {
        searchRebuildTask?.cancel()
        searchRebuildTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: model.isLightModeEnabled ? 220_000_000 : 120_000_000)
            guard !Task.isCancelled else { return }
            rebuildSearchCache()
        }
    }

    private func problemSummaryLabel() -> String {
        if model.isLightModeEnabled && !model.showOnlyIssues {
            return "Problemy: light"
        }
        if projectionResult.issueCountIsViewportScoped {
            return "Problemy (viewport): \(projectionResult.issueLineCount)"
        }
        return "Problemy: \(projectionResult.issueLineCount)"
    }

    private func issuesForRow(lineID: DialogueLine.ID) -> [String] {
        guard model.showValidationIssues else { return [] }

        if model.isLightModeEnabled {
            let isFocusedRow = model.selectedLineID == lineID || model.editingLineID == lineID
            if !isFocusedRow {
                return []
            }
        }

        return projectionResult.issuesByLineID[lineID] ?? []
    }

    private func rebuildSearchCache() {
        var nextResult = projectionResult
        projectionCoordinator.rebuildSearch(in: &nextResult, from: makeProjectionInput())
        applyProjectionResult(nextResult, preserveChronologyCursor: true)
    }

    private func makeProjectionInput() -> EditorProjectionInput {
        EditorProjectionInput(
            lines: model.lines,
            fps: model.fps,
            findQuery: findQuery,
            showValidationIssues: model.showValidationIssues,
            showOnlyIssues: model.showOnlyIssues,
            validateMissingSpeaker: model.validateMissingSpeaker,
            validateMissingStartTC: model.validateMissingStartTC,
            validateMissingEndTC: model.validateMissingEndTC,
            validateInvalidTC: model.validateInvalidTC,
            showOnlyChronologyIssues: showOnlyChronologyIssues,
            showOnlyMissingSpeakerIssues: showOnlyMissingSpeakerIssues,
            selectedCharacterFilterKeys: selectedCharacterFilterKeys,
            visibleLineIDs: visibleLineIDs,
            useViewportScopedIssues: shouldUseViewportScopedIssueComputation(),
            selectedLineID: model.selectedLineID,
            editingLineID: model.editingLineID,
            highlightedLineID: model.highlightedLineID,
            activeSearchLineID: activeSearchTargetLineID(),
            isLightModeEnabled: model.isLightModeEnabled
        )
    }

    private func applyProjectionResult(
        _ result: EditorProjectionResult,
        preserveChronologyCursor: Bool = false,
        preserveSearchCursor: Bool = false
    ) {
        projectionResult = result

        let chronologyIssues = result.chronoStartIssues
        if chronologyIssues.isEmpty {
            chronoIssueCursor = -1
            if showOnlyChronologyIssues {
                showOnlyChronologyIssues = false
            }
        } else if chronoIssueCursor < 0 {
            chronoIssueCursor = 0
        } else if chronoIssueCursor >= chronologyIssues.count {
            chronoIssueCursor = chronologyIssues.count - 1
        }

        let searchMatchIndices = result.searchMatchIndices
        if searchMatchIndices.isEmpty {
            searchMatchCursor = -1
        } else if searchMatchCursor >= searchMatchIndices.count {
            searchMatchCursor = searchMatchIndices.count - 1
        }
    }

    private func openFindReplacePanel() {
        if let panel = findReplacePanel {
            panel.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }

        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 576, height: 152),
            styleMask: [.titled, .closable, .miniaturizable],
            backing: .buffered,
            defer: false
        )
        panel.title = "Najit a nahradit"
        panel.isReleasedWhenClosed = false
        panel.hidesOnDeactivate = false
        panel.isFloatingPanel = true
        panel.level = .floating
        panel.collectionBehavior = [.fullScreenAuxiliary]
        panel.contentViewController = NSHostingController(rootView: findReplaceSheetContent)
        panel.center()
        panel.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)

        findReplacePanel = panel
        installFindReplaceZOrderObserver(for: panel)
    }

    private func closeFindReplacePanel() {
        findReplacePanel?.close()
        findReplacePanel = nil
        removeFindReplaceZOrderObserver()
    }

    private func installFindReplaceZOrderObserver(for panel: NSPanel) {
        removeFindReplaceZOrderObserver()

        findReplaceZOrderObserver = NotificationCenter.default.addObserver(
            forName: NSWindow.didBecomeKeyNotification,
            object: nil,
            queue: .main
        ) { notification in
            guard let keyWindow = notification.object as? NSWindow else { return }
            guard keyWindow != panel else { return }
            guard panel.isVisible else { return }
            panel.orderFront(nil)
        }
    }

    private func removeFindReplaceZOrderObserver() {
        if let observer = findReplaceZOrderObserver {
            NotificationCenter.default.removeObserver(observer)
            findReplaceZOrderObserver = nil
        }
    }

    private func openTCChronologyPanel() {
        if let panel = tcChronologyPanel {
            panel.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }

        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 620, height: 420),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        panel.title = "TC Chrono chyby"
        panel.isReleasedWhenClosed = false
        panel.hidesOnDeactivate = false
        panel.level = .normal
        panel.collectionBehavior = [.fullScreenAuxiliary]
        panel.contentViewController = NSHostingController(rootView: tcChronologyPanelContent)
        panel.center()
        panel.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)

        tcChronologyPanel = panel
    }

    private func closeTCChronologyPanel() {
        tcChronologyPanel?.close()
        tcChronologyPanel = nil
    }

    private func openSpeakerStatsPanel() {
        if let panel = speakerStatsPanel {
            panel.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }

        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 620, height: 460),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        panel.title = "Postavy"
        panel.isReleasedWhenClosed = false
        panel.hidesOnDeactivate = false
        panel.level = .normal
        panel.collectionBehavior = [.fullScreenAuxiliary]
        panel.contentViewController = NSHostingController(rootView: speakerStatsPanelContent)
        panel.center()
        panel.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)

        speakerStatsPanel = panel
    }

    private func closeSpeakerStatsPanel() {
        speakerStatsPanel?.close()
        speakerStatsPanel = nil
    }

    private func openSpeakerColorsPanel() {
        if let panel = speakerColorsPanel {
            panel.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }

        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 820, height: 540),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        panel.title = "Barvy postav"
        panel.isReleasedWhenClosed = false
        panel.hidesOnDeactivate = false
        panel.level = .normal
        panel.collectionBehavior = [.fullScreenAuxiliary]
        panel.contentViewController = NSHostingController(rootView: speakerColorsPanelContent)
        panel.center()
        panel.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)

        speakerColorsPanel = panel
    }

    private func closeSpeakerColorsPanel() {
        speakerColorsPanel?.close()
        speakerColorsPanel = nil
    }

    private func openSettingsWindow() {
        SettingsWindowPresenter.show(model: model)
    }

    private func jumpToChronologyIssue(step: Int) {
        let issues = projectionResult.chronoStartIssues
        guard !issues.isEmpty else { return }

        if chronoIssueCursor < 0 || chronoIssueCursor >= issues.count {
            chronoIssueCursor = step >= 0 ? 0 : (issues.count - 1)
        } else {
            chronoIssueCursor = (chronoIssueCursor + step + issues.count) % issues.count
        }

        goToChronologyIssue(at: chronoIssueCursor)
    }

    private func goToChronologyIssue(at index: Int) {
        guard projectionResult.chronoStartIssues.indices.contains(index) else { return }
        chronoIssueCursor = index
        let issue = projectionResult.chronoStartIssues[index]
        guard let lineIndex = model.lines.firstIndex(where: { $0.id == issue.lineID }) else { return }
        let line = model.lines[lineIndex]
        model.selectLine(line)
        scrollTargetLineID = line.id
    }

    private func activeSearchTargetLineID() -> DialogueLine.ID? {
        guard !projectionResult.normalizedFindQuery.isEmpty else { return nil }
        let matches = validSearchMatchIndices()
        guard !matches.isEmpty else { return nil }

        if
            let selectedID = model.selectedLineID,
            let selectedIndex = model.lines.firstIndex(where: { $0.id == selectedID }),
            matches.contains(selectedIndex) {
            return selectedID
        }

        if searchMatchCursor >= 0, searchMatchCursor < matches.count {
            return model.lines[matches[searchMatchCursor]].id
        }

        return model.lines[matches[0]].id
    }

    private func jumpToSearchMatch(step: Int, releaseTextFieldFocus: Bool = false) {
        let matches = validSearchMatchIndices()
        guard !matches.isEmpty else { return }

        if searchMatchCursor < 0 || searchMatchCursor >= matches.count {
            searchMatchCursor = step >= 0 ? 0 : (matches.count - 1)
        } else {
            searchMatchCursor = (searchMatchCursor + step + matches.count) % matches.count
        }

        let lineIndex = matches[searchMatchCursor]
        let line = model.lines[lineIndex]
        model.selectLine(line)
        scrollTargetLineID = line.id
        if releaseTextFieldFocus {
            clearFocus()
        }
    }

    private func replaceCurrentMatch() {
        guard !projectionResult.normalizedFindQuery.isEmpty else { return }

        let matches = validSearchMatchIndices()
        guard !matches.isEmpty else { return }

        let targetIndex: Int
        if
            let selectedID = model.selectedLineID,
            let selectedIndex = model.lines.firstIndex(where: { $0.id == selectedID }),
            matches.contains(selectedIndex) {
            targetIndex = selectedIndex
            searchMatchCursor = matches.firstIndex(of: selectedIndex) ?? searchMatchCursor
        } else if searchMatchCursor >= 0, searchMatchCursor < matches.count {
            targetIndex = matches[searchMatchCursor]
        } else {
            searchMatchCursor = 0
            targetIndex = matches[0]
        }

        let targetID = model.lines[targetIndex].id
        let count = model.replaceInLine(lineID: targetID, query: findQuery, replacement: replaceQuery)
        if count > 0 {
            replaceStatus = "Nahrazeno: \(count)"
            model.selectLine(model.lines[targetIndex])
        } else {
            replaceStatus = "Bez zmen."
        }
    }

    private func replaceAllMatches() {
        guard !projectionResult.normalizedFindQuery.isEmpty else { return }

        let matches = validSearchMatchIndices()
        let ids = Set(matches.map { model.lines[$0].id })
        let count = model.replaceInAllLines(query: findQuery, replacement: replaceQuery, limitedTo: ids)
        if count > 0 {
            replaceStatus = "Nahrazeno celkem: \(count)"
            searchMatchCursor = -1
        } else {
            replaceStatus = "Bez zmen."
        }
    }

    private func installKeyMonitor() {
        guard keyMonitor == nil else { return }
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            // While alert is visible, let the system route keys only to the alert.
            if model.alertMessage != nil {
                return event
            }

            if event.keyCode == 51 || event.keyCode == 117 {
                model.noteBackspaceKeyDownDebug(
                    textInputFocused: isTextInputFocused(),
                    editingLineID: model.editingLineID
                )
            }

            let pressedModifiers = event.modifierFlags.intersection([.command, .option, .control, .shift])
            if handleSpeakerAutocompleteKeyEvent(event, pressedModifiers: pressedModifiers) {
                return nil
            }

            if !isTextInputFocused() {
                if matchesShortcut(event, shortcut: shortcutChronoPrev) {
                    jumpToChronologyIssue(step: -1)
                    return nil
                }
                if matchesShortcut(event, shortcut: shortcutChronoNext) {
                    jumpToChronologyIssue(step: 1)
                    return nil
                }
            }

            if model.isTimecodeModeEnabled {
                let pressed = event.modifierFlags.intersection([.command, .option, .control, .shift])
                if pressed.isEmpty, (event.keyCode == 36 || event.keyCode == 76) {
                    model.moveSelection(step: 1)
                    scrollToSelectedLine()
                    return nil
                }
            }

            if model.isTimecodeModeEnabled && model.editingLineID == nil && !isTextInputFocused() {
                if matchesShortcut(event, shortcut: shortcutCaptureStartTC) {
                    model.captureStartTimecodeForSelectedLine(advanceToNext: model.isTimecodeAutoAdvanceEnabled)
                    return nil
                }
                if matchesShortcut(event, shortcut: shortcutCaptureEndTC) {
                    model.captureEndTimecodeForSelectedLine(advanceToNext: model.isTimecodeAutoAdvanceEnabled)
                    return nil
                }
            }

            if matchesShortcut(event, shortcut: shortcutOpenReplicaStartTC) {
                openSelectedReplicaAndFocusStartTimecode()
                return nil
            }

            if model.editingLineID != nil, pressedModifiers == [.shift], (event.keyCode == 36 || event.keyCode == 76) {
                model.finishEditing()
                clearFocus()
                model.moveSelection(step: 1)
                scrollToSelectedLine()
                return nil
            }

            if matchesShortcut(event, shortcut: shortcutEnterEdit) {
                if model.isTimecodeModeEnabled {
                    return nil
                }
                if model.editingLineID != nil {
                    model.finishEditing()
                    clearFocus()
                    return nil
                }
                if !isTextInputFocused() {
                    if let selectedLineID = model.selectedLineID {
                        requestReplicaTextFocus(for: selectedLineID)
                        model.startEditingSelectedLine()
                        scheduleReplicaTextFocusRetries(for: selectedLineID)
                        return nil
                    }
                }
            }

            if matchesShortcut(event, shortcut: shortcutAddLine) {
                let newLineID = model.insertNewLineAfterSelection()
                scrollTargetLineID = newLineID
                return nil
            }

            if matchesShortcut(event, shortcut: shortcutRewindReplay) {
                model.rewindOrReplayActiveLine()
                return nil
            }

            if matchesShortcut(event, shortcut: shortcutSeekBackward) {
                model.seekBackwardStep()
                return nil
            }

            if matchesShortcut(event, shortcut: shortcutSeekForward) {
                model.seekForwardStep()
                return nil
            }

            if matchesShortcut(event, shortcut: shortcutUndo) {
                performUndoAction()
                return nil
            }

            if matchesShortcut(event, shortcut: shortcutRedo) {
                performRedoAction()
                return nil
            }

            if matchesShortcut(event, shortcut: shortcutToggleLoop) {
                model.setLoopEnabled(!model.isLoopEnabled)
                return nil
            }

            if matchesShortcut(event, shortcut: shortcutPlayPause) {
                if isTextInputFocused() {
                    return event
                }
                model.togglePlayPause()
                return nil
            }

            if !isTextInputFocused() {
                if matchesShortcut(event, shortcut: shortcutCopyReplicas) {
                    _ = model.copySelectedLinesToClipboard()
                    return nil
                }
                if matchesShortcut(event, shortcut: shortcutPasteReplicas) {
                    let pastedCount = model.pasteReplicasFromClipboard()
                    if pastedCount > 0 {
                        scrollToSelectedLine()
                    }
                    return nil
                }
            }

            if !isTextInputFocused() && model.editingLineID == nil {
                let pressed = event.modifierFlags.intersection([.command, .option, .control, .shift])
                if pressed.isEmpty && (event.keyCode == 51 || event.keyCode == 117) {
                    if event.isARepeat {
                        return nil
                    }
                    let debugTrace = model.beginBackspaceDebugTrace(watchedReplicaIndex: 8)
                    let targetIDs = model.snapshotDeletionTargetIDs()
                    let deletedCount = model.deleteLines(withIDs: targetIDs)
                    if let debugTrace {
                        model.finishBackspaceDebugTrace(
                            debugTrace,
                            deletedCountReturned: deletedCount
                        )
                    }
                    return nil
                }
                if pressed == [.shift] {
                    if event.keyCode == 125 {
                        model.moveSelection(step: 1, extendSelection: true)
                        scrollToSelectedLine()
                        return nil
                    }
                    if event.keyCode == 126 {
                        model.moveSelection(step: -1, extendSelection: true)
                        scrollToSelectedLine()
                        return nil
                    }
                }

                if matchesShortcut(event, shortcut: shortcutMoveDown) {
                    model.moveSelection(step: 1)
                    scrollToSelectedLine()
                    return nil
                }
                if matchesShortcut(event, shortcut: shortcutMoveUp) {
                    model.moveSelection(step: -1)
                    scrollToSelectedLine()
                    return nil
                }
            }

            return event
        }
    }

    private func removeKeyMonitor() {
        if let monitor = keyMonitor {
            NSEvent.removeMonitor(monitor)
            keyMonitor = nil
        }
    }

    private func resetKeyMonitor() {
        removeKeyMonitor()
        installKeyMonitor()
    }

    private func installMouseMonitor() {
        guard mouseMonitor == nil else { return }
        mouseMonitor = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown]) { event in
            handleMouseDownForFocus(event)
            return event
        }
    }

    private func removeMouseMonitor() {
        if let monitor = mouseMonitor {
            NSEvent.removeMonitor(monitor)
            mouseMonitor = nil
        }
    }

    private func openSelectedReplicaAndFocusStartTimecode() {
        guard let selectedLineID = model.selectedLineID else { return }

        appendFocusDebugReport(
            "CMD_ENTER_BEGIN selected=\(focusDebugLineSummary(selectedLineID)) editingBefore=\(focusDebugLineSummary(model.editingLineID)) tcMode=\(model.isTimecodeModeEnabled)"
        )

        replicaTextFocusRequestLineID = nil
        replicaTextFocusRetryTask?.cancel()
        replicaTextFocusRetryTask = nil

        // Set request early so row edit-focus logic can prefer Start TC over text field.
        startTimecodeFocusRequestLineID = selectedLineID
        startTimecodeFocusRequestToken = UUID()

        if !model.isTimecodeModeEnabled {
            model.startEditingSelectedLine()
        } else if model.editingLineID != nil {
            model.finishEditing()
            clearFocus()
        }
        scrollTargetLineID = selectedLineID
        scheduleStartTimecodeFocusRetries(for: selectedLineID)

        appendFocusDebugReport(
            "CMD_ENTER_END selected=\(focusDebugLineSummary(model.selectedLineID)) editingAfter=\(focusDebugLineSummary(model.editingLineID)) requestLine=\(focusDebugLineSummary(startTimecodeFocusRequestLineID)) token=\(startTimecodeFocusRequestToken.uuidString.prefix(8))"
        )
    }

    private func requestReplicaTextFocus(for lineID: DialogueLine.ID) {
        replicaTextFocusRetryTask?.cancel()
        replicaTextFocusRetryTask = nil
        startTimecodeFocusRetryTask?.cancel()
        startTimecodeFocusRetryTask = nil
        startTimecodeFocusRequestLineID = nil
        replicaTextFocusRequestLineID = lineID
        replicaTextFocusRequestToken = UUID()
        appendFocusDebugReport(
            "TEXT_FOCUS_REQUEST line=\(focusDebugLineSummary(lineID)) token=\(replicaTextFocusRequestToken.uuidString.prefix(8))"
        )
    }

    private func scheduleReplicaTextFocusRetries(for lineID: DialogueLine.ID) {
        replicaTextFocusRetryTask?.cancel()
        replicaTextFocusRetryTask = Task { @MainActor in
            let delays: [UInt64] = [80_000_000, 160_000_000, 320_000_000]
            for (index, delay) in delays.enumerated() {
                try? await Task.sleep(nanoseconds: delay)
                guard !Task.isCancelled else { return }
                guard replicaTextFocusRequestLineID == lineID else { return }
                guard model.selectedLineID == lineID else { return }
                guard model.editingLineID == lineID else { continue }
                replicaTextFocusRequestToken = UUID()
                appendFocusDebugReport(
                    "TEXT_FOCUS_RETRY[\(index + 1)] line=\(focusDebugLineSummary(lineID)) token=\(replicaTextFocusRequestToken.uuidString.prefix(8))"
                )
            }
        }
    }

    private func scheduleStartTimecodeFocusRetries(for lineID: DialogueLine.ID) {
        startTimecodeFocusRetryTask?.cancel()
        startTimecodeFocusRetryTask = Task { @MainActor in
            let delays: [UInt64] = [90_000_000, 180_000_000, 320_000_000]
            for (index, delay) in delays.enumerated() {
                try? await Task.sleep(nanoseconds: delay)
                guard !Task.isCancelled else { return }
                guard startTimecodeFocusRequestLineID == lineID else { return }
                guard model.selectedLineID == lineID else { return }
                guard model.editingLineID == lineID else { continue }
                startTimecodeFocusRequestToken = UUID()
                appendFocusDebugReport(
                    "CMD_ENTER_RETRY[\(index + 1)] line=\(focusDebugLineSummary(lineID)) token=\(startTimecodeFocusRequestToken.uuidString.prefix(8))"
                )
            }
        }
    }

    private func handleMouseDownForFocus(_ event: NSEvent) {
        guard model.alertMessage == nil else { return }
        guard isTextInputFocused() else { return }
        guard !speakerAutocompleteState.isPresented else { return }
        // Do not interfere with native double/triple click word/line selection in text inputs.
        if event.clickCount > 1 {
            return
        }

        let window = event.window ?? NSApp.keyWindow
        if let textResponder = window?.firstResponder as? NSTextView {
            let responderPoint = textResponder.convert(event.locationInWindow, from: nil)
            if textResponder.bounds.contains(responderPoint) {
                return
            }
            if let scrollView = textResponder.enclosingScrollView {
                let scrollPoint = scrollView.convert(event.locationInWindow, from: nil)
                if scrollView.bounds.contains(scrollPoint) {
                    return
                }
            }
        } else if let responderView = window?.firstResponder as? NSView {
            let responderPoint = responderView.convert(event.locationInWindow, from: nil)
            if responderView.bounds.contains(responderPoint) {
                return
            }
        }

        guard let contentView = window?.contentView else { return }

        let point = contentView.convert(event.locationInWindow, from: nil)
        let hitView = contentView.hitTest(point)
        if isTextInputHierarchy(hitView) {
            return
        }

        clearFocus()
    }

    private func updateSpeakerAutocompleteState(_ snapshot: SpeakerAutocompleteSnapshot?) {
        let previousState = speakerAutocompleteState
        speakerAutocompleteState.update(snapshot: snapshot)
        let relayWillBeCleared =
            speakerSuggestionSelection != nil &&
            speakerAutocompleteState != previousState &&
            !speakerAutocompleteState.isPresented
        if relayWillBeCleared {
            logSpeakerAutocompleteEvent(
                "AUTOCOMPLETE_RELAY_CLEARED",
                fields: [
                    ("tx", SpeakerAutocompleteDebugLog.shortID(speakerSuggestionSelection?.transactionID)),
                    ("reason", speakerAutocompleteRelayClearReason(snapshot: snapshot, previousState: previousState)),
                    ("wasPresented", String(previousState.isPresented)),
                    ("isPresented", String(speakerAutocompleteState.isPresented))
                ]
            )
            speakerSuggestionSelection = nil
        }
    }

    private func handleSpeakerAutocompleteKeyEvent(
        _ event: NSEvent,
        pressedModifiers: NSEvent.ModifierFlags
    ) -> Bool {
        guard speakerAutocompleteState.isPresented else { return false }
        guard pressedModifiers.isEmpty else { return false }

        switch event.keyCode {
        case 125:
            speakerAutocompleteState.moveSelection(step: 1)
            return true
        case 126:
            speakerAutocompleteState.moveSelection(step: -1)
            return true
        case 36, 76:
            let transactionID = UUID()
            logSpeakerAutocompleteEvent(
                "AUTOCOMPLETE_KEY_ENTER_BEGIN",
                fields: [
                    ("tx", SpeakerAutocompleteDebugLog.shortID(transactionID)),
                    ("lineID", SpeakerAutocompleteDebugLog.shortID(speakerAutocompleteState.lineID)),
                    ("query", speakerAutocompleteState.query),
                    ("selectedIndex", speakerAutocompleteSelectedIndexDescription(speakerAutocompleteState.selectedIndex)),
                    ("activeSuggestion", speakerAutocompleteState.activeSuggestion),
                    ("isPresented", String(speakerAutocompleteState.isPresented))
                ]
            )
            return commitSpeakerAutocompleteSelection(index: nil, transactionID: transactionID)
        case 53:
            speakerAutocompleteState.dismiss()
            return true
        default:
            return false
        }
    }

    @discardableResult
    private func commitSpeakerAutocompleteSelection(
        index: Int? = nil,
        transactionID: UUID? = nil
    ) -> Bool {
        let resolvedTransactionID = transactionID ?? UUID()
        let suggestion = speakerAutocompleteState.suggestionForCommit(preferredIndex: index)
        logSpeakerAutocompleteEvent(
            "AUTOCOMPLETE_COMMIT_REQUESTED",
            fields: [
                ("tx", SpeakerAutocompleteDebugLog.shortID(resolvedTransactionID)),
                ("explicitIndex", speakerAutocompleteSelectedIndexDescription(index)),
                ("selectedIndex", speakerAutocompleteSelectedIndexDescription(speakerAutocompleteState.selectedIndex)),
                ("suggestion", suggestion),
                ("lineID", SpeakerAutocompleteDebugLog.shortID(speakerAutocompleteState.lineID)),
                ("query", speakerAutocompleteState.query)
            ]
        )

        guard speakerAutocompleteState.isPresented else { return false }
        guard let lineID = speakerAutocompleteState.lineID else { return false }
        guard let suggestion else { return false }

        logSpeakerAutocompleteEvent(
            "AUTOCOMPLETE_MODEL_COMMIT_BEGIN",
            fields: [
                ("tx", SpeakerAutocompleteDebugLog.shortID(resolvedTransactionID)),
                ("lineID", SpeakerAutocompleteDebugLog.shortID(lineID)),
                ("suggestion", suggestion)
            ]
        )
        guard model.applySpeakerAutocompleteSuggestion(lineID: lineID, suggestion: suggestion) else {
            logSpeakerAutocompleteEvent(
                "AUTOCOMPLETE_MODEL_COMMIT_END",
                fields: [
                    ("tx", SpeakerAutocompleteDebugLog.shortID(resolvedTransactionID)),
                    ("lineID", SpeakerAutocompleteDebugLog.shortID(lineID)),
                    ("applied", "false")
                ]
            )
            return false
        }
        let committedSpeaker: String? = {
            guard
                let committedIndex = model.lineIndex(for: lineID),
                model.lines.indices.contains(committedIndex)
            else {
                return nil
            }
            return model.lines[committedIndex].speaker
        }()
        logSpeakerAutocompleteEvent(
            "AUTOCOMPLETE_MODEL_COMMIT_END",
            fields: [
                ("tx", SpeakerAutocompleteDebugLog.shortID(resolvedTransactionID)),
                ("lineID", SpeakerAutocompleteDebugLog.shortID(lineID)),
                ("applied", "true"),
                ("lineSpeakerAfter", committedSpeaker)
            ]
        )

        let selection = SpeakerSuggestionSelection(
            lineID: lineID,
            suggestion: suggestion,
            transactionID: resolvedTransactionID
        )
        speakerSuggestionSelection = selection
        logSpeakerAutocompleteEvent(
            "AUTOCOMPLETE_RELAY_SET",
            fields: [
                ("tx", SpeakerAutocompleteDebugLog.shortID(selection.transactionID)),
                ("relayToken", SpeakerAutocompleteDebugLog.shortID(selection.deliveryToken)),
                ("lineID", SpeakerAutocompleteDebugLog.shortID(selection.lineID)),
                ("suggestion", selection.suggestion)
            ]
        )
        speakerAutocompleteState.dismiss()
        logSpeakerAutocompleteEvent(
            "AUTOCOMPLETE_STATE_DISMISSED",
            fields: [
                ("tx", SpeakerAutocompleteDebugLog.shortID(selection.transactionID)),
                ("lineID", SpeakerAutocompleteDebugLog.shortID(selection.lineID)),
                ("selectedIndex", speakerAutocompleteSelectedIndexDescription(speakerAutocompleteState.selectedIndex)),
                ("isPresented", String(speakerAutocompleteState.isPresented))
            ]
        )
        return true
    }

    private func logSpeakerAutocompleteEvent(
        _ event: String,
        fields: [(String, String?)]
    ) {
        SpeakerAutocompleteDebugLog.append(
            enabled: model.isDevModeEnabled,
            event: event,
            fields: fields
        )
    }

    private func speakerAutocompleteSelectedIndexDescription(_ index: Int?) -> String? {
        guard let index else { return nil }
        return String(index)
    }

    private func speakerAutocompleteRelayClearReason(
        snapshot: SpeakerAutocompleteSnapshot?,
        previousState: SpeakerAutocompleteState
    ) -> String {
        if snapshot == nil {
            return "no_active_snapshot"
        }
        if previousState.isPresented && !speakerAutocompleteState.isPresented {
            return "state_not_present_after_update"
        }
        return "state_changed"
    }

    private func isTextInputFocused() -> Bool {
        guard let responder = NSApp.keyWindow?.firstResponder else {
            return false
        }
        return responder is NSTextView || responder is NSTextField
    }

    private func appendFocusDebugReport(_ line: String) {
        guard model.isDevModeEnabled else { return }
        let timestamp = Self.focusDebugDateFormatter.string(from: Date())
        let payload = "\(timestamp) \(line)\n"
        guard let data = payload.data(using: .utf8) else { return }

        if FileManager.default.fileExists(atPath: Self.focusDebugLogURL.path) {
            do {
                let handle = try FileHandle(forWritingTo: Self.focusDebugLogURL)
                defer { try? handle.close() }
                try handle.seekToEnd()
                handle.write(data)
            } catch {
                print("Focus debug log append failed: \(error.localizedDescription)")
            }
            return
        }

        do {
            try payload.write(to: Self.focusDebugLogURL, atomically: true, encoding: .utf8)
        } catch {
            print("Focus debug log write failed: \(error.localizedDescription)")
        }
    }

    private func focusDebugLineSummary(_ lineID: DialogueLine.ID?) -> String {
        guard let lineID else { return "<nil>" }
        guard let index = model.lines.firstIndex(where: { $0.id == lineID }) else {
            return "<missing \(lineID.uuidString.prefix(8))>"
        }
        let line = model.lines[index]
        let speaker = line.speaker.trimmingCharacters(in: .whitespacesAndNewlines)
        return "#\(line.index)[\(lineID.uuidString.prefix(8))] spk='\(speaker)'"
    }

    private func isTextInputHierarchy(_ view: NSView?) -> Bool {
        var current = view
        while let v = current {
            if v is NSTextField || v is NSTextView {
                return true
            }
            if let scrollView = v as? NSScrollView, scrollView.documentView is NSTextView {
                return true
            }
            if v.enclosingScrollView?.documentView is NSTextView {
                return true
            }
            current = v.superview
        }
        return false
    }

    private func clearFocus() {
        NSApp.keyWindow?.makeFirstResponder(nil)
    }

    private func performUndoAction() {
        if performTextInputUndoRedo(selector: #selector(UndoManager.undo)) {
            return
        }
        model.undo()
    }

    private func performRedoAction() {
        if performTextInputUndoRedo(selector: #selector(UndoManager.redo)) {
            return
        }
        model.redo()
    }

    @discardableResult
    private func performTextInputUndoRedo(selector: Selector) -> Bool {
        guard isTextInputFocused() else { return false }
        guard let window = NSApp.keyWindow else { return false }
        return window.firstResponder?.tryToPerform(selector, with: nil) ?? false
    }

    private func scrollToSelectedLine() {
        if let selectedID = model.selectedLineID {
            scrollTargetLineID = selectedID
        }
    }

    private func matchesShortcut(_ event: NSEvent, shortcut rawShortcut: String) -> Bool {
        guard let spec = parseShortcut(rawShortcut) else {
            return false
        }

        let pressed = event.modifierFlags.intersection([.command, .option, .control, .shift])
        guard pressed == spec.modifiers else {
            return false
        }

        switch spec.key {
        case .keyCode(let code):
            return event.keyCode == code
        case .enter:
            return event.keyCode == 36 || event.keyCode == 76
        case .character(let value):
            return event.charactersIgnoringModifiers?.lowercased() == value
        }
    }

    private func parseShortcut(_ rawShortcut: String) -> ShortcutSpec? {
        let normalized = rawShortcut
            .lowercased()
            .replacingOccurrences(of: " ", with: "")
        guard !normalized.isEmpty else { return nil }

        let tokens = normalized.split(separator: "+").map(String.init)
        guard let keyToken = tokens.last, !keyToken.isEmpty else {
            return nil
        }

        var modifiers: NSEvent.ModifierFlags = []
        for token in tokens.dropLast() {
            switch token {
            case "cmd", "command", "meta", "⌘":
                modifiers.insert(.command)
            case "option", "alt", "⌥":
                modifiers.insert(.option)
            case "ctrl", "control", "⌃":
                modifiers.insert(.control)
            case "shift", "⇧":
                modifiers.insert(.shift)
            default:
                return nil
            }
        }

        let key: ShortcutKey
        switch keyToken {
        case "space":
            key = .keyCode(49)
        case "enter", "return":
            key = .enter
        case "up", "uparrow":
            key = .keyCode(126)
        case "down", "downarrow":
            key = .keyCode(125)
        case "left", "leftarrow":
            key = .keyCode(123)
        case "right", "rightarrow":
            key = .keyCode(124)
        case "tab":
            key = .keyCode(48)
        case "esc", "escape":
            key = .keyCode(53)
        default:
            guard keyToken.count == 1 else { return nil }
            key = .character(keyToken)
        }

        return ShortcutSpec(modifiers: modifiers, key: key)
    }

    private func recoveryAlertMessage() -> String {
        guard let snapshot = model.pendingAutosaveRecovery else {
            return ""
        }
        let saved = Self.autosaveDateTimeFormatter.string(from: snapshot.savedAt)
        return "Byl nalezen automaticky ulozeny stav.\n\(model.pendingAutosaveSummary())\nUlozeno: \(saved)"
    }

    private func validDisplayedLineIndices() -> [Int] {
        let sanitized = projectionResult.displayedLineIndices.filter { model.lines.indices.contains($0) }
        if !sanitized.isEmpty {
            return sanitized
        }
        if shouldFallbackToAllLinesWhenDisplayCacheIsEmpty() {
            return Array(model.lines.indices)
        }
        return sanitized
    }

    private func validSearchMatchIndices() -> [Int] {
        projectionResult.searchMatchIndices.filter { model.lines.indices.contains($0) }
    }

    private func sanitizeIndexCaches() {
        let validLineIDs = Set(model.lines.map(\.id))
        let validVisible = visibleLineIDs.intersection(validLineIDs)
        if validVisible.count != visibleLineIDs.count {
            visibleLineIDs = validVisible
        }

        let validDisplayed = validDisplayedLineIndices()
        if validDisplayed.count != projectionResult.displayedLineIndices.count {
            projectionResult.displayedLineIndices = validDisplayed
        }

        let validMatches = validSearchMatchIndices()
        if validMatches.count != projectionResult.searchMatchIndices.count {
            projectionResult.searchMatchIndices = validMatches
        }

        if validMatches.isEmpty {
            searchMatchCursor = -1
        } else if searchMatchCursor >= validMatches.count {
            searchMatchCursor = validMatches.count - 1
        }
    }

    private func shouldComputeIssuesForCurrentMode() -> Bool {
        model.showOnlyIssues || (model.showValidationIssues && !model.isLightModeEnabled)
    }

    private func shouldUseViewportScopedIssueComputation() -> Bool {
        shouldComputeIssuesForCurrentMode() && !model.showOnlyIssues
    }

    private func shouldFallbackToAllLinesWhenDisplayCacheIsEmpty() -> Bool {
        guard !model.lines.isEmpty else { return false }
        let showOnlyValidationIssues = model.showValidationIssues && model.showOnlyIssues
        if showOnlyValidationIssues || showOnlyChronologyIssues || showOnlyMissingSpeakerIssues || !selectedCharacterFilterKeys.isEmpty {
            return false
        }
        return true
    }

    private func filteredSpeakerStatsForCharacterFilter() -> [EditorViewModel.SpeakerStatistic] {
        let query = EditorProjectionCoordinator.normalizeSearch(characterFilterQuery)
        guard !query.isEmpty else { return model.speakerDatabase }
        return model.speakerDatabase.filter { stat in
            EditorProjectionCoordinator.normalizeSearch(stat.speaker).contains(query)
        }
    }

    private func selectAllCharacterFilters() {
        selectedCharacterFilterKeys = Set(
            model.speakerDatabase.map { EditorProjectionCoordinator.normalizedSpeakerKey($0.speaker) }
        )
    }

    private func sanitizeCharacterFilterSelection() {
        let validKeys = Set(
            model.speakerDatabase.map { EditorProjectionCoordinator.normalizedSpeakerKey($0.speaker) }
        )
        let sanitized = selectedCharacterFilterKeys.intersection(validKeys)
        if sanitized != selectedCharacterFilterKeys {
            selectedCharacterFilterKeys = sanitized
        }
    }

    private func handleLineVisibility(lineID: DialogueLine.ID, isVisible: Bool) {
        if isVisible {
            let inserted = visibleLineIDs.insert(lineID).inserted
            guard inserted else { return }
            guard shouldUseViewportScopedIssueComputation() else { return }
            updateCachesForSingleLine(lineID, rebuildChronology: false)
        } else {
            let removed = visibleLineIDs.remove(lineID) != nil
            guard removed else { return }
            guard shouldUseViewportScopedIssueComputation() else { return }
            if model.showValidationIssues || model.showOnlyIssues {
                rebuildDisplayedIndicesAndIssueCountCache()
            }
        }
    }

    private func markDevSelectionInteractionStarted(lineID: DialogueLine.ID, source: String) {
        guard model.isDevModeEnabled else { return }
        let shouldMeasureFocus = source == "double_click" || model.isTimecodeModeEnabled
        guard shouldMeasureFocus else {
            devPendingClickToFocus = nil
            return
        }
        devPendingClickToFocus = (lineID: lineID, source: source, startedAt: CFAbsoluteTimeGetCurrent())
    }

    private func markDevFocusAcquired(lineID: DialogueLine.ID, field: String) {
        guard model.isDevModeEnabled else { return }
        guard let pending = devPendingClickToFocus else { return }
        guard pending.lineID == lineID else { return }
        let elapsed = (CFAbsoluteTimeGetCurrent() - pending.startedAt) * 1_000
        let label = "\(pending.source)->\(field)"
        model.recordDevClickToFocus(milliseconds: elapsed, label: label)
        Self.devLogger.debug("click_to_focus \(label, privacy: .public) \(elapsed, format: .fixed(precision: 2), privacy: .public)ms")
        devPendingClickToFocus = nil
    }

    private func markDevCommitRequested(lineID: DialogueLine.ID, field: String) {
        guard model.isDevModeEnabled else { return }
        let now = CFAbsoluteTimeGetCurrent()
        devPendingCommitToLinesChanged = (lineID: lineID, field: field, startedAt: now)
    }

    private func markDevLinesChangedObserved(_ changeKind: EditorViewModel.LineChangeKind) {
        guard model.isDevModeEnabled else {
            devPendingCommitToLinesChanged = nil
            return
        }
        guard let pending = devPendingCommitToLinesChanged else { return }
        guard let changedLineID = lineID(from: changeKind), changedLineID == pending.lineID else { return }

        let elapsed = (CFAbsoluteTimeGetCurrent() - pending.startedAt) * 1_000
        let label = "\(pending.field)->\(label(for: changeKind))"
        model.recordDevCommitToLinesChanged(milliseconds: elapsed, label: label)
        Self.devLogger.debug("commit_to_lines_changed \(label, privacy: .public) \(elapsed, format: .fixed(precision: 2), privacy: .public)ms")
        devPendingCommitToLinesChanged = nil
    }

    private func markDevCachePipelineStarted(for changeKind: EditorViewModel.LineChangeKind) {
        guard model.isDevModeEnabled else {
            devPendingLinesChangedToCacheDone = nil
            return
        }
        switch changeKind {
        case .none:
            return
        default:
            break
        }
        devPendingLinesChangedToCacheDone = (
            kindLabel: label(for: changeKind),
            startedAt: CFAbsoluteTimeGetCurrent()
        )
    }

    private func markDevCachesCompleted() {
        guard model.isDevModeEnabled else {
            devPendingLinesChangedToCacheDone = nil
            return
        }
        guard let pending = devPendingLinesChangedToCacheDone else { return }
        let elapsed = (CFAbsoluteTimeGetCurrent() - pending.startedAt) * 1_000
        model.recordDevLinesChangedToCacheDone(milliseconds: elapsed, label: pending.kindLabel)
        Self.devLogger.debug("lines_changed_to_cache_done \(pending.kindLabel, privacy: .public) \(elapsed, format: .fixed(precision: 2), privacy: .public)ms")
        devPendingLinesChangedToCacheDone = nil
    }

    private func lineID(from changeKind: EditorViewModel.LineChangeKind) -> DialogueLine.ID? {
        switch changeKind {
        case .singleLineText(let lineID), .singleLineMetadata(let lineID):
            return lineID
        default:
            return nil
        }
    }

    private func label(for changeKind: EditorViewModel.LineChangeKind) -> String {
        switch changeKind {
        case .none:
            return "none"
        case .structure:
            return "structure"
        case .multiLine:
            return "multi_line"
        case .singleLineText:
            return "single_text"
        case .singleLineMetadata:
            return "single_metadata"
        }
    }

}

private struct DialogueLineDropDelegate: DropDelegate {
    let targetLineID: DialogueLine.ID?
    @Binding var draggedLineID: DialogueLine.ID?
    @Binding var dropTargetLineID: DialogueLine.ID?
    @Binding var isDropAtEndActive: Bool
    let model: EditorViewModel

    func validateDrop(info _: DropInfo) -> Bool {
        draggedLineID != nil && model.editingLineID == nil
    }

    func dropEntered(info _: DropInfo) {
        if targetLineID == nil {
            isDropAtEndActive = true
            dropTargetLineID = nil
        } else {
            dropTargetLineID = targetLineID
            isDropAtEndActive = false
        }
    }

    func dropExited(info _: DropInfo) {
        if targetLineID == nil {
            isDropAtEndActive = false
        }
        if dropTargetLineID == targetLineID {
            dropTargetLineID = nil
        }
    }

    func performDrop(info _: DropInfo) -> Bool {
        defer {
            draggedLineID = nil
            dropTargetLineID = nil
            isDropAtEndActive = false
        }

        guard model.editingLineID == nil else { return false }
        guard let draggedLineID else { return false }

        let moved = model.moveLine(draggedLineID: draggedLineID, before: targetLineID)
        if moved, let movedIndex = model.lines.firstIndex(where: { $0.id == draggedLineID }) {
            model.selectLine(model.lines[movedIndex])
        }
        return moved
    }

    func dropUpdated(info _: DropInfo) -> DropProposal? {
        DropProposal(operation: .move)
    }
}

private struct ShortcutSpec {
    let modifiers: NSEvent.ModifierFlags
    let key: ShortcutKey
}

private enum ShortcutKey {
    case keyCode(UInt16)
    case enter
    case character(String)
}

private struct FindReplaceSheet: View {
    @Binding var findQuery: String
    @Binding var replaceQuery: String
    @Binding var matchCount: Int
    @Binding var replaceStatus: String
    let onPrevious: () -> Void
    let onNext: () -> Void
    let onReplaceCurrent: () -> Void
    let onReplaceAll: () -> Void
    let onClose: () -> Void
    @FocusState private var focusedField: Field?

    private enum Field {
        case find
        case replace
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                Text("Najit a nahradit")
                    .font(.title3.weight(.semibold))

                Spacer()

                Button("Zavrit") {
                    onClose()
                }
                .buttonStyle(.bordered)
            }

            HStack(spacing: 8) {
                TextField("Najit...", text: $findQuery)
                    .textFieldStyle(.roundedBorder)
                    .focused($focusedField, equals: .find)
                    .onSubmit {
                        onNext()
                    }

                Button("Predchozi") {
                    onPrevious()
                }
                .buttonStyle(.bordered)
                .disabled(!canNavigate)

                Button("Dalsi") {
                    onNext()
                }
                .buttonStyle(.bordered)
                .disabled(!canNavigate)

                Text("Nalezeno: \(matchCount)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .frame(minWidth: 86, alignment: .trailing)
            }

            HStack(spacing: 8) {
                TextField("Nahradit za...", text: $replaceQuery)
                    .textFieldStyle(.roundedBorder)
                    .focused($focusedField, equals: .replace)
                    .onSubmit {
                        onReplaceCurrent()
                    }

                Button("Nahradit vybranou") {
                    onReplaceCurrent()
                }
                .buttonStyle(.bordered)
                .disabled(!canReplace)

                Button("Nahradit vse") {
                    onReplaceAll()
                }
                .buttonStyle(.bordered)
                .disabled(!canReplace)
            }

            if !replaceStatus.isEmpty {
                Text(replaceStatus)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .frame(width: 560)
        .onAppear {
            DispatchQueue.main.async {
                focusedField = .find
            }
        }
    }

    private var canNavigate: Bool {
        matchCount > 0
    }

    private var canReplace: Bool {
        canNavigate && !findQuery.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
}

private struct TCChronologyIssuesPanel: View {
    @Binding var issues: [EditorViewModel.ChronologicalStartIssue]
    @Binding var activeIndex: Int
    let previousShortcutDisplay: String
    let nextShortcutDisplay: String
    let onPrevious: () -> Void
    let onNext: () -> Void
    let onSelect: (Int) -> Void
    let onClose: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                Text("TC Chrono chyby")
                    .font(.title3.weight(.semibold))

                Spacer()

                Button("Zavrit") {
                    onClose()
                }
                .buttonStyle(.bordered)
            }

            HStack(spacing: 8) {
                Button("Predchozi") {
                    onPrevious()
                }
                .buttonStyle(.bordered)
                .disabled(issues.isEmpty)
                .help("Predchozi chyba (\(previousShortcutDisplay))")

                Button("Dalsi") {
                    onNext()
                }
                .buttonStyle(.bordered)
                .disabled(issues.isEmpty)
                .help("Dalsi chyba (\(nextShortcutDisplay))")

                Text("Nalezeno: \(issues.count)")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                if issues.indices.contains(activeIndex) {
                    Text("Aktivni: \(activeIndex + 1)/\(issues.count)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            if issues.isEmpty {
                Text("Nenalezena zadna chrono chyba Start TC.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
            } else {
                List {
                    ForEach(Array(issues.enumerated()), id: \.element.id) { index, issue in
                        Button {
                            onSelect(index)
                        } label: {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(
                                    "#\(issue.lineIndex) \(issue.startTimecode) je mensi nez #\(issue.previousLineIndex) \(issue.previousStartTimecode)"
                                )
                                .font(.system(.body, design: .monospaced))
                                .foregroundStyle(.primary)

                                Text("next.start < prev.start")
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                            }
                            .padding(.vertical, 2)
                            .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        .buttonStyle(.plain)
                        .listRowBackground(
                            index == activeIndex ? Color.accentColor.opacity(0.15) : Color.clear
                        )
                    }
                }
                .listStyle(.inset)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .frame(minWidth: 580, minHeight: 360)
    }
}

private struct SpeakerStatsPanel: View {
    @ObservedObject var model: EditorViewModel
    let showCloseButton: Bool
    let onClose: () -> Void

    private static let replicaFormatter: NumberFormatter = {
        let formatter = NumberFormatter()
        formatter.locale = Locale(identifier: "cs_CZ")
        formatter.numberStyle = .decimal
        formatter.minimumFractionDigits = 1
        formatter.maximumFractionDigits = 1
        return formatter
    }()

    private var stats: [EditorViewModel.SpeakerStatistic] {
        model.speakerStatistics()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                Text("Postavy")
                    .font(.title3.weight(.semibold))

                Spacer()

                Text("Celkem: \(stats.count)")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Button("Barvy...") {
                    NotificationCenter.default.post(name: .openSpeakerColorsPanel, object: nil)
                }
                .buttonStyle(.bordered)
                .disabled(stats.isEmpty)

                Button("Export CSV...") {
                    model.promptExportSpeakerStatisticsCSV()
                }
                .buttonStyle(.bordered)
                .disabled(stats.isEmpty)

                if showCloseButton {
                    Button("Zavrit") {
                        onClose()
                    }
                    .buttonStyle(.bordered)
                }
            }

            if stats.isEmpty {
                Text("V projektu zatim nejsou zadne postavy.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
            } else {
                Table(stats) {
                    TableColumn("Postava") { row in
                        Text(row.speaker)
                    }
                    TableColumn("Vstupy") { row in
                        Text("\(row.entries)")
                            .frame(maxWidth: .infinity, alignment: .trailing)
                    }
                    TableColumn("Repliky") { row in
                        Text(replicaUnitsText(row.replicaUnits))
                            .frame(maxWidth: .infinity, alignment: .trailing)
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)

                Text("Repliky = soucet slov / 8")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .frame(minWidth: 560, minHeight: 360)
    }

    private func replicaUnitsText(_ value: Double) -> String {
        let number = NSNumber(value: value)
        return Self.replicaFormatter.string(from: number) ?? String(format: "%.1f", value)
    }
}
