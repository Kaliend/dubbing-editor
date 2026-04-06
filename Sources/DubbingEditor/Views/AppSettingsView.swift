import AppKit
import SwiftUI

struct AppSettingsWindowContainer: View {
    @ObservedObject var model: EditorViewModel
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

    var body: some View {
        AppSettingsView(model: model, colorSchemeModeRaw: $colorSchemeModeRaw)
            .preferredColorScheme(preferredColorScheme)
    }
}

struct AppSettingsView: View {
    @ObservedObject var model: EditorViewModel
    @Binding var colorSchemeModeRaw: String

    var body: some View {
        TabView {
            GeneralSettingsTab(model: model, colorSchemeModeRaw: $colorSchemeModeRaw)
                .tabItem {
                    Label("Obecne", systemImage: "gearshape")
                }

            PlaybackSettingsTab(model: model)
                .tabItem {
                    Label("Prehravani", systemImage: "play.circle")
                }

            ShortcutSettingsTab(model: model)
                .tabItem {
                    Label("Zkratky", systemImage: "command")
                }
        }
        .padding(16)
    }
}

private struct GeneralSettingsTab: View {
    @ObservedObject var model: EditorViewModel
    @Binding var colorSchemeModeRaw: String
    @AppStorage("bug_report_recipient_email") private var bugReportRecipientEmail = "info@kiulpekidis.me"
    @State private var replicaTextFontSizeDraft: Double = 13
    @State private var isAdjustingReplicaTextFontSize = false
    @State private var replicaTextFontSizeCommitTask: Task<Void, Never>?

    var body: some View {
        Form {
            Picker("Vzhled appky", selection: $colorSchemeModeRaw) {
                Text("System").tag("system")
                Text("Light").tag("light")
                Text("Dark").tag("dark")
            }
            .pickerStyle(.segmented)

            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text("Velikost textu replik")
                    Spacer()
                    Text("\(Int(replicaTextFontSizeDraft.rounded())) pt")
                        .foregroundStyle(.secondary)
                }
                Slider(
                    value: $replicaTextFontSizeDraft,
                    in: 13...30,
                    step: 1,
                    onEditingChanged: { isEditing in
                        isAdjustingReplicaTextFontSize = isEditing
                        if isEditing {
                            scheduleReplicaTextFontSizeCommit()
                        } else {
                            commitReplicaTextFontSizeNow()
                        }
                    }
                )
                .onChange(of: replicaTextFontSizeDraft) { _ in
                    guard isAdjustingReplicaTextFontSize else { return }
                    scheduleReplicaTextFontSizeCommit()
                }
            }
            Toggle(
                "Dev Mode",
                isOn: Binding(
                    get: { model.isDevModeEnabled },
                    set: { model.isDevModeEnabled = $0 }
                )
            )
            Toggle(
                "Light Mode (vykon)",
                isOn: Binding(
                    get: { model.isLightModeEnabled },
                    set: { model.isLightModeEnabled = $0 }
                )
            )
            Toggle(
                "Timecode mod",
                isOn: Binding(
                    get: { model.isTimecodeModeEnabled },
                    set: { model.isTimecodeModeEnabled = $0 }
                )
            )
            Toggle(
                "TC auto HH:MM i v editu",
                isOn: Binding(
                    get: { model.isEditModeTimecodePrefillEnabled },
                    set: { model.isEditModeTimecodePrefillEnabled = $0 }
                )
            )
            Toggle(
                "Skryt framy",
                isOn: Binding(
                    get: { model.hideTimecodeFrames },
                    set: { model.hideTimecodeFrames = $0 }
                )
            )
            Toggle(
                "Skryt End TC pole",
                isOn: Binding(
                    get: { model.isEndTimecodeFieldHidden },
                    set: { model.isEndTimecodeFieldHidden = $0 }
                )
            )

            Divider()

            TextField("E-mail pro bug reporty", text: $bugReportRecipientEmail)
                .textFieldStyle(.roundedBorder)
                .help("Pouzije se pro akci 'Vytvorit a odeslat mailem'. Muze obsahovat i vice adres oddelenych carkou.")

            Divider()

            Toggle(
                "Zobrazit validace",
                isOn: Binding(
                    get: { model.showValidationIssues },
                    set: { model.showValidationIssues = $0 }
                )
            )
            Toggle(
                "Jen problematicke",
                isOn: Binding(
                    get: { model.showOnlyIssues },
                    set: { model.showOnlyIssues = $0 }
                )
            )
            .disabled(!model.showValidationIssues)

            Divider()

            Toggle(
                "Validace: Chybejici charakter",
                isOn: Binding(
                    get: { model.validateMissingSpeaker },
                    set: { model.validateMissingSpeaker = $0 }
                )
            )
            .disabled(!model.showValidationIssues)

            Toggle(
                "Validace: Chybejici start TC",
                isOn: Binding(
                    get: { model.validateMissingStartTC },
                    set: { model.validateMissingStartTC = $0 }
                )
            )
            .disabled(!model.showValidationIssues)

            Toggle(
                "Validace: Chybejici end TC",
                isOn: Binding(
                    get: { model.validateMissingEndTC },
                    set: { model.validateMissingEndTC = $0 }
                )
            )
            .disabled(!model.showValidationIssues)

            Toggle(
                "Validace: Spatne zadany TC",
                isOn: Binding(
                    get: { model.validateInvalidTC },
                    set: { model.validateInvalidTC = $0 }
                )
            )
            .disabled(!model.showValidationIssues)
        }
        .formStyle(.grouped)
        .onAppear {
            replicaTextFontSizeDraft = model.replicaTextFontSize
        }
        .onChange(of: model.replicaTextFontSize) { value in
            guard !isAdjustingReplicaTextFontSize else { return }
            replicaTextFontSizeDraft = value
        }
        .onDisappear {
            replicaTextFontSizeCommitTask?.cancel()
            replicaTextFontSizeCommitTask = nil
        }
    }

    private func scheduleReplicaTextFontSizeCommit() {
        replicaTextFontSizeCommitTask?.cancel()
        let pending = replicaTextFontSizeDraft.rounded()
        replicaTextFontSizeCommitTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 90_000_000)
            guard !Task.isCancelled else { return }
            if model.replicaTextFontSize != pending {
                model.replicaTextFontSize = pending
            }
        }
    }

    private func commitReplicaTextFontSizeNow() {
        replicaTextFontSizeCommitTask?.cancel()
        replicaTextFontSizeCommitTask = nil
        let value = replicaTextFontSizeDraft.rounded()
        if model.replicaTextFontSize != value {
            model.replicaTextFontSize = value
        }
    }
}

private struct PlaybackSettingsTab: View {
    @ObservedObject var model: EditorViewModel
    @State private var playbackSeekStepInput: String = ""
    @State private var lineOffsetInput: String = "0"
    @State private var videoOffsetInput: String = "0"

    var body: some View {
        Form {
            HStack {
                Text("FPS projektu")
                Spacer()
                Picker(
                    "FPS projektu",
                    selection: Binding(
                        get: { model.fpsPresetSelection },
                        set: { model.setFPSPreset($0) }
                    )
                ) {
                    ForEach(EditorViewModel.FPSPreset.allCases) { preset in
                        Text(preset.displayName).tag(preset)
                    }
                }
                .pickerStyle(.menu)
                .frame(width: 110)
            }

            Text("Aktualni FPS: \(model.fpsDisplayLabel)")
                .font(.caption)
                .foregroundStyle(.secondary)

            HStack {
                Text("Krok posunu videa (+/-)")
                Spacer()
                TextField("sekundy", text: $playbackSeekStepInput)
                    .textFieldStyle(.roundedBorder)
                    .multilineTextAlignment(.trailing)
                    .frame(width: 110)
                    .onSubmit {
                        applyPlaybackSeekStepInput()
                    }
                Text("s")
                    .foregroundStyle(.secondary)
            }

            HStack {
                Text("Offset textu")
                Spacer()
                TextField("sec nebo TC", text: $lineOffsetInput)
                    .textFieldStyle(.roundedBorder)
                    .multilineTextAlignment(.trailing)
                    .frame(width: 140)
                    .help("Posune textove timecody o zadanou hodnotu. Kdyz je vybrano vice replik, aplikuje se jen na vybrane.")
                    .onSubmit {
                        applyLineOffset()
                    }
                Button("Aplikovat") {
                    applyLineOffset()
                }
                .buttonStyle(.bordered)
                .disabled(model.lines.isEmpty || model.isImportingWord)
                .help("Aplikuje offset na vsechny repliky, nebo jen na vybrane pri vice-vyberu.")
            }

            HStack {
                Text("Video offset")
                Spacer()
                TextField("sec nebo TC", text: $videoOffsetInput)
                    .textFieldStyle(.roundedBorder)
                    .multilineTextAlignment(.trailing)
                    .frame(width: 140)
                    .help("Posune video vuci timecodum. Hodnota + znamena, ze video pujde pozdeji.")
                    .onSubmit {
                        applyVideoOffset()
                    }
                Button("Aplikovat") {
                    applyVideoOffset()
                }
                .buttonStyle(.bordered)
                .disabled(model.videoURL == nil || model.isImportingWord)
                .help("Aplikuje offset jen na prehravani videa.")
            }

            HStack {
                Text("Replay predjezd")
                Spacer()
                Text(model.isReplayPrerollEnabled ? "\(formattedPlaybackSeekStepValue()) s" : "Vypnuto")
                    .foregroundStyle(.secondary)
            }

            Toggle(
                "Zapnout replay predjezd",
                isOn: Binding(
                    get: { model.isReplayPrerollEnabled },
                    set: { model.isReplayPrerollEnabled = $0 }
                )
            )

            HStack {
                Text("Audio kanaly")
                Spacer()
                Text(audioChannelSummary())
                    .foregroundStyle(.secondary)
            }

            HStack(spacing: 10) {
                Toggle(
                    "Mute L",
                    isOn: Binding(
                        get: { model.isLeftChannelMuted },
                        set: { model.setLeftChannelMuted($0) }
                    )
                )
                .toggleStyle(.switch)

                Toggle(
                    "Mute R",
                    isOn: Binding(
                        get: { model.isRightChannelMuted },
                        set: { model.setRightChannelMuted($0) }
                    )
                )
                .toggleStyle(.switch)
            }
            .disabled(!model.canControlStereoChannels || model.isPreparingChannelDerivedAudio)

            if model.isPreparingChannelDerivedAudio {
                Text("Pripravuji lokalni kanalovy stem pro L/R mute...")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Text("Replay predjezd (kdyz je zapnuty) pouziva stejnou hodnotu jako Krok posunu videa (+/-). Nastaveni je projektove a uklada se spolu s projektem.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .formStyle(.grouped)
        .onAppear {
            syncPlaybackSeekStepInput()
            videoOffsetInput = formatOffsetInput(model.videoOffsetSeconds)
        }
        .onChange(of: model.playbackSeekStepSeconds) { _ in
            syncPlaybackSeekStepInput()
        }
        .onChange(of: model.videoOffsetSeconds) { value in
            videoOffsetInput = formatOffsetInput(value)
        }
    }

    private func syncPlaybackSeekStepInput() {
        let value = model.playbackSeekStepSeconds
        playbackSeekStepInput = formattedPlaybackSeekStepValue(from: value)
    }

    private func formattedPlaybackSeekStepValue() -> String {
        formattedPlaybackSeekStepValue(from: model.playbackSeekStepSeconds)
    }

    private func formattedPlaybackSeekStepValue(from value: Double) -> String {
        if abs(value.rounded() - value) < 0.0001 {
            return String(Int(value.rounded()))
        }
        let formatted = String(format: "%.2f", value)
        let withoutTrailingZeros = formatted.replacingOccurrences(
            of: #"0+$"#,
            with: "",
            options: .regularExpression
        )
        return withoutTrailingZeros.replacingOccurrences(
            of: #"\.$"#,
            with: "",
            options: .regularExpression
        )
    }

    private func applyPlaybackSeekStepInput() {
        let normalized = playbackSeekStepInput
            .replacingOccurrences(of: ",", with: ".")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard let parsed = Double(normalized), parsed > 0 else {
            syncPlaybackSeekStepInput()
            return
        }
        model.setPlaybackSeekStepSeconds(parsed)
        syncPlaybackSeekStepInput()
    }

    private func applyLineOffset() {
        model.applyOffset(rawValue: lineOffsetInput)
    }

    private func applyVideoOffset() {
        model.applyVideoOffset(rawValue: videoOffsetInput)
    }

    private func formatOffsetInput(_ value: Double) -> String {
        let rounded = value.rounded()
        if abs(rounded - value) < 0.000001 {
            return String(Int(rounded))
        }
        let formatted = String(format: "%.3f", value)
        let withoutTrailingZeros = formatted.replacingOccurrences(
            of: #"0+$"#,
            with: "",
            options: .regularExpression
        )
        return withoutTrailingZeros.replacingOccurrences(
            of: #"\.$"#,
            with: "",
            options: .regularExpression
        )
    }

    private func audioChannelSummary() -> String {
        if model.videoURL == nil { return "neni video" }
        if model.detectedAudioChannelCount <= 0 { return "nezjisteno" }
        if model.detectedAudioChannelCount == 1 { return "mono" }
        return "\(model.detectedAudioChannelCount) kanaly"
    }
}

private enum SettingsShortcutField: String, CaseIterable, Hashable {
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

private func settingsShortcutString(from event: NSEvent) -> String? {
    let modifiers = event.modifierFlags.intersection([.command, .option, .control, .shift])
    var parts: [String] = []
    if modifiers.contains(.command) { parts.append("cmd") }
    if modifiers.contains(.option) { parts.append("option") }
    if modifiers.contains(.control) { parts.append("ctrl") }
    if modifiers.contains(.shift) { parts.append("shift") }

    let keyToken: String
    switch event.keyCode {
    case 49:
        keyToken = "space"
    case 36, 76:
        keyToken = "enter"
    case 126:
        keyToken = "up"
    case 125:
        keyToken = "down"
    case 123:
        keyToken = "left"
    case 124:
        keyToken = "right"
    case 48:
        keyToken = "tab"
    case 53:
        keyToken = "esc"
    default:
        guard
            let chars = event.charactersIgnoringModifiers?.lowercased(),
            chars.count == 1
        else {
            return nil
        }
        keyToken = chars
    }

    parts.append(keyToken)
    return parts.joined(separator: "+")
}

private struct ShortcutSettingsTab: View {
    @ObservedObject var model: EditorViewModel
    @AppStorage("shortcut_add_line") private var shortcutAddLine = "cmd+shift+n"
    @AppStorage("shortcut_enter_edit") private var shortcutEnterEdit = "enter"
    @AppStorage("shortcut_open_replica_start_tc") private var shortcutOpenReplicaStartTC = "cmd+enter"
    @AppStorage("shortcut_play_pause") private var shortcutPlayPause = "space"
    @AppStorage("shortcut_rewind_replay") private var shortcutRewindReplay = "option+space"
    @AppStorage("shortcut_seek_backward") private var shortcutSeekBackward = "option+left"
    @AppStorage("shortcut_seek_forward") private var shortcutSeekForward = "option+right"
    @AppStorage("shortcut_capture_start_tc") private var shortcutCaptureStartTC = "enter"
    @AppStorage("shortcut_capture_end_tc") private var shortcutCaptureEndTC = "shift+enter"
    @AppStorage("shortcut_move_up") private var shortcutMoveUp = "up"
    @AppStorage("shortcut_move_down") private var shortcutMoveDown = "down"
    @AppStorage("shortcut_toggle_loop") private var shortcutToggleLoop = "option+l"
    @AppStorage("shortcut_undo") private var shortcutUndo = "cmd+z"
    @AppStorage("shortcut_redo") private var shortcutRedo = "cmd+shift+z"
    @State private var capturedMonitor: Any?
    @State private var capturingField: SettingsShortcutField?

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Form {
                SettingsShortcutCaptureRow(
                    title: "Nova replika",
                    value: shortcutAddLine,
                    isCapturing: capturingField == .addLine
                ) { capturingField = .addLine }
                SettingsShortcutCaptureRow(
                    title: "Edit replika",
                    value: shortcutEnterEdit,
                    isCapturing: capturingField == .enterEdit
                ) { capturingField = .enterEdit }
                SettingsShortcutCaptureRow(
                    title: "Edit replika + Start TC",
                    value: shortcutOpenReplicaStartTC,
                    isCapturing: capturingField == .openReplicaStartTC
                ) { capturingField = .openReplicaStartTC }
                SettingsShortcutCaptureRow(
                    title: "Play/Pause",
                    value: shortcutPlayPause,
                    isCapturing: capturingField == .playPause
                ) { capturingField = .playPause }
                SettingsShortcutCaptureRow(
                    title: "Replay replika od startu",
                    value: shortcutRewindReplay,
                    isCapturing: capturingField == .rewindReplay
                ) { capturingField = .rewindReplay }
                SettingsShortcutCaptureRow(
                    title: "Posun videa zpet",
                    value: shortcutSeekBackward,
                    isCapturing: capturingField == .seekBackward
                ) { capturingField = .seekBackward }
                SettingsShortcutCaptureRow(
                    title: "Posun videa vpred",
                    value: shortcutSeekForward,
                    isCapturing: capturingField == .seekForward
                ) { capturingField = .seekForward }
                SettingsShortcutCaptureRow(
                    title: "Priradit Start TC",
                    value: shortcutCaptureStartTC,
                    isCapturing: capturingField == .captureStartTC
                ) { capturingField = .captureStartTC }
                SettingsShortcutCaptureRow(
                    title: "Priradit End TC",
                    value: shortcutCaptureEndTC,
                    isCapturing: capturingField == .captureEndTC
                ) { capturingField = .captureEndTC }
                SettingsShortcutCaptureRow(
                    title: "Move vyber nahoru",
                    value: shortcutMoveUp,
                    isCapturing: capturingField == .moveUp
                ) { capturingField = .moveUp }
                SettingsShortcutCaptureRow(
                    title: "Move vyber dolu",
                    value: shortcutMoveDown,
                    isCapturing: capturingField == .moveDown
                ) { capturingField = .moveDown }
                SettingsShortcutCaptureRow(
                    title: "Toggle loop",
                    value: shortcutToggleLoop,
                    isCapturing: capturingField == .toggleLoop
                ) { capturingField = .toggleLoop }
                SettingsShortcutCaptureRow(
                    title: "Undo",
                    value: shortcutUndo,
                    isCapturing: capturingField == .undo
                ) { capturingField = .undo }
                SettingsShortcutCaptureRow(
                    title: "Redo",
                    value: shortcutRedo,
                    isCapturing: capturingField == .redo
                ) { capturingField = .redo }
            }
            .formStyle(.grouped)

            Text("Dvojklik na zkratku a potom stiskni pozadovanou kombinaci. Esc zrusi cekani.")
                .font(.caption)
                .foregroundStyle(.secondary)

            HStack {
                Button("Default") {
                    shortcutAddLine = "cmd+shift+n"
                    shortcutEnterEdit = "enter"
                    shortcutOpenReplicaStartTC = "cmd+enter"
                    shortcutPlayPause = "space"
                    shortcutRewindReplay = "option+space"
                    shortcutSeekBackward = "option+left"
                    shortcutSeekForward = "option+right"
                    shortcutCaptureStartTC = "enter"
                    shortcutCaptureEndTC = "shift+enter"
                    shortcutMoveUp = "up"
                    shortcutMoveDown = "down"
                    shortcutToggleLoop = "option+l"
                    shortcutUndo = "cmd+z"
                    shortcutRedo = "cmd+shift+z"
                    model.setPlaybackSeekStepSeconds(1)
                }
                Spacer()
            }
        }
        .onAppear {
            installCaptureMonitor()
        }
        .onDisappear {
            removeCaptureMonitor()
        }
    }

    private func installCaptureMonitor() {
        guard capturedMonitor == nil else { return }
        capturedMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            guard let capturingField else { return event }
            if event.keyCode == 53 {
                self.capturingField = nil
                return nil
            }
            guard let value = settingsShortcutString(from: event) else {
                return nil
            }
            applyShortcut(value, for: capturingField)
            self.capturingField = nil
            return nil
        }
    }

    private func removeCaptureMonitor() {
        if let monitor = capturedMonitor {
            NSEvent.removeMonitor(monitor)
            capturedMonitor = nil
        }
    }

    private func applyShortcut(_ value: String, for field: SettingsShortcutField) {
        switch field {
        case .addLine:
            shortcutAddLine = value
        case .enterEdit:
            shortcutEnterEdit = value
        case .openReplicaStartTC:
            shortcutOpenReplicaStartTC = value
        case .playPause:
            shortcutPlayPause = value
        case .rewindReplay:
            shortcutRewindReplay = value
        case .seekBackward:
            shortcutSeekBackward = value
        case .seekForward:
            shortcutSeekForward = value
        case .captureStartTC:
            shortcutCaptureStartTC = value
        case .captureEndTC:
            shortcutCaptureEndTC = value
        case .moveUp:
            shortcutMoveUp = value
        case .moveDown:
            shortcutMoveDown = value
        case .toggleLoop:
            shortcutToggleLoop = value
        case .undo:
            shortcutUndo = value
        case .redo:
            shortcutRedo = value
        }
    }
}

private struct SettingsShortcutCaptureRow: View {
    let title: String
    let value: String
    let isCapturing: Bool
    let onStartCapture: () -> Void

    var body: some View {
        HStack {
            Text(title)
            Spacer()
            Text(isCapturing ? "Stiskni zkratku..." : value)
                .font(.system(.body, design: .monospaced))
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .frame(width: 190, alignment: .leading)
                .background(
                    RoundedRectangle(cornerRadius: 6)
                        .fill(isCapturing ? Color.accentColor.opacity(0.2) : Color(nsColor: .controlBackgroundColor))
                        .overlay(
                            RoundedRectangle(cornerRadius: 6)
                                .stroke(isCapturing ? Color.accentColor : Color.clear, lineWidth: 1)
                        )
                )
                .onTapGesture(count: 2, perform: onStartCapture)
        }
    }
}
