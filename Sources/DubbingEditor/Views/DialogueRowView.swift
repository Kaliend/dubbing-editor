import AppKit
import SwiftUI

struct DialogueRowView: View {
    let lineID: DialogueLine.ID
    @Binding var line: DialogueLine
    let fps: Double
    let hideTimecodeFrames: Bool
    let isEndTimecodeFieldHidden: Bool
    let isTimecodeModeEnabled: Bool
    let isSelected: Bool
    let isEditable: Bool
    let isPlaybackActive: Bool
    let replicaTextFocusRequestLineID: DialogueLine.ID?
    let replicaTextFocusRequestToken: UUID
    let startTimecodeFocusRequestLineID: DialogueLine.ID?
    let startTimecodeFocusRequestToken: UUID
    let isActiveSearchSelection: Bool
    let hasStartChronologyIssue: Bool
    let totalLineCount: Int
    let replicaTextFontSize: Double
    let speakerColorOverridesByKey: [String: String]
    let speakerSuggestions: [String]
    let speakerSuggestionSelection: SpeakerSuggestionSelection?
    let isDevModeEnabled: Bool
    let issues: [String]
    let onSelect: (Bool) -> Void
    let onDoubleClick: () -> Void
    let onStartTimecodeFieldTap: () -> Void
    let onEndTimecodeFieldTap: () -> Void
    let onSetStart: () -> Void
    let onSetEnd: () -> Void
    let onFocusAcquired: (String) -> Void
    let onModelCommit: (String) -> Void
    let dragItemProvider: (() -> NSItemProvider)?
    @FocusState private var focusedField: FocusField?
    @State private var draftController = DialogueRowDraftController()
    @State private var previousFocusedField: FocusField?
    @State private var lastHandledReplicaTextFocusToken: UUID?
    @State private var lastHandledStartTimecodeFocusToken: UUID?
    @State private var lastHandledSpeakerSuggestionDeliveryToken: UUID?
    @State private var pendingSpeakerAutocompleteTransactionID: UUID?
    @State private var pendingSpeakerAutocompleteSuggestion: String?
    private let dragHandleWidth: CGFloat = 24
    private let speakerFieldWidth: CGFloat = 132

    private enum FocusField {
        case replicaText
        case speaker
        case startTimecode
        case endTimecode
    }

    private var isBoundToExpectedLine: Bool {
        line.id == lineID
    }

    private var shouldPreferStartTimecodeFocusForShortcut: Bool {
        startTimecodeFocusRequestLineID == lineID
    }

    private var shouldPreferReplicaTextFocusForRequest: Bool {
        replicaTextFocusRequestLineID == lineID
    }

    private var usesInteractiveRowPath: Bool {
        isEditable || isTimecodeFieldEditable
    }

    var body: some View {
        if usesInteractiveRowPath {
            interactiveRowShell
        } else {
            readOnlyRowShell
        }
    }

    @ViewBuilder
    private var interactiveRowShell: some View {
        rowScaffold {
            interactiveRowContent
        }
        .onChange(of: isEditable) { editable in
            if editable {
                draftController.load(from: line, fps: fps, hideFrames: hideTimecodeFrames)
                focusReplicaTextFromRequestIfNeeded()
                if shouldPreferStartTimecodeFocusForShortcut && !shouldPreferReplicaTextFocusForRequest {
                    focusStartTimecodeFromShortcutIfNeeded()
                }
            } else {
                flushAllDraftsToBinding()
                if focusedField == .replicaText || focusedField == .speaker {
                    focusedField = nil
                }
                focusStartTimecodeIfNeeded()
            }
            draftController.updateForHideFramesChange(
                line: line,
                fps: fps,
                hideFrames: hideTimecodeFrames,
                isStartFocused: focusedField == .startTimecode,
                isEndFocused: focusedField == .endTimecode
            )
            focusStartTimecodeFromShortcutIfNeeded()
        }
        .onChange(of: line.text) { _ in
            draftController.syncTextFromModel(
                line,
                isFocused: focusedField == .replicaText
            )
        }
        .onChange(of: line.speaker) { _ in
            draftController.syncSpeakerFromModel(
                line,
                isFocused: focusedField == .speaker,
                forceWhileFocused: true
            )
        }
        .onChange(of: isSelected) { _ in
            focusStartTimecodeIfNeeded()
        }
        .onChange(of: isTimecodeModeEnabled) { _ in
            focusStartTimecodeIfNeeded()
            focusStartTimecodeFromShortcutIfNeeded()
        }
        .onChange(of: replicaTextFocusRequestToken) { _ in
            focusReplicaTextFromRequestIfNeeded()
        }
        .onChange(of: startTimecodeFocusRequestToken) { _ in
            guard !shouldPreferReplicaTextFocusForRequest else { return }
            focusStartTimecodeFromShortcutIfNeeded()
        }
        .onChange(of: speakerSuggestionSelection?.deliveryToken) { _ in
            applySpeakerSuggestionSelectionIfNeeded()
        }
        .onChange(of: draftController.speakerDraft) { value in
            if
                let pendingSuggestion = pendingSpeakerAutocompleteSuggestion,
                value != pendingSuggestion
            {
                pendingSpeakerAutocompleteTransactionID = nil
                pendingSpeakerAutocompleteSuggestion = nil
            }
        }
        .onChange(of: line.startTimecode) { _ in
            draftController.syncStartTimecodeFromModel(
                line,
                fps: fps,
                hideFrames: hideTimecodeFrames,
                isFocused: focusedField == .startTimecode
            )
        }
        .onChange(of: line.endTimecode) { _ in
            draftController.syncEndTimecodeFromModel(
                line,
                fps: fps,
                hideFrames: hideTimecodeFrames,
                isFocused: focusedField == .endTimecode
            )
        }
        .onChange(of: hideTimecodeFrames) { _ in
            draftController.updateForHideFramesChange(
                line: line,
                fps: fps,
                hideFrames: hideTimecodeFrames,
                isStartFocused: focusedField == .startTimecode,
                isEndFocused: focusedField == .endTimecode
            )
        }
        .onChange(of: isEndTimecodeFieldHidden) { hidden in
            guard hidden else { return }
            if focusedField == .endTimecode {
                commitEndTimecodeDraft()
                focusedField = nil
            }
        }
        .onChange(of: focusedField) { field in
            let previous = previousFocusedField
            if previous == .startTimecode, field != .startTimecode {
                commitStartTimecodeDraft()
            }
            if previous == .endTimecode, field != .endTimecode {
                commitEndTimecodeDraft()
            }

            if field == nil {
                flushAllDraftsToBinding()
            }

            if field != .speaker {
                pendingSpeakerAutocompleteTransactionID = nil
                pendingSpeakerAutocompleteSuggestion = nil
            }

            switch field {
            case .speaker:
                draftController.prepareSpeakerEditing(from: line)
                onFocusAcquired("speaker")
            case .replicaText:
                draftController.syncTextFromModel(line, isFocused: false, forceWhileFocused: true)
                onFocusAcquired("text")
            case .startTimecode:
                onStartTimecodeFieldTap()
                draftController.prepareStartTimecodeEditing(
                    from: line,
                    fps: fps,
                    hideFrames: hideTimecodeFrames
                )
                onFocusAcquired("start_tc")
            case .endTimecode:
                onEndTimecodeFieldTap()
                draftController.prepareEndTimecodeEditing(
                    from: line,
                    fps: fps,
                    hideFrames: hideTimecodeFrames
                )
                onFocusAcquired("end_tc")
            case nil:
                break
            }
            previousFocusedField = field
        }
        .onAppear {
            draftController.load(from: line, fps: fps, hideFrames: hideTimecodeFrames)
            if isEditable {
                focusReplicaTextFromRequestIfNeeded()
                if !shouldPreferReplicaTextFocusForRequest {
                    focusStartTimecodeFromShortcutIfNeeded()
                }
            } else {
                focusStartTimecodeIfNeeded()
            }
            if !shouldPreferReplicaTextFocusForRequest {
                focusStartTimecodeFromShortcutIfNeeded()
            }
        }
        .onDisappear {
            guard shouldFlushDraftsOnDisappear else { return }
            flushAllDraftsToBinding()
        }
    }

    @ViewBuilder
    private var readOnlyRowShell: some View {
        rowScaffold {
            readOnlyRowContent
                .contentShape(Rectangle())
                .overlay {
                    ReadOnlyRowInteractionCaptureView(
                        onSingleClick: { extendSelection in
                            onSelect(extendSelection)
                        },
                        onDoubleClick: {
                            onDoubleClick()
                        }
                    )
                }
        }
        .onChange(of: line.text) { _ in
            draftController.syncTextFromModel(
                line,
                isFocused: focusedField == .replicaText
            )
        }
        .onChange(of: line.speaker) { _ in
            draftController.syncSpeakerFromModel(
                line,
                isFocused: focusedField == .speaker
            )
        }
        .onChange(of: line.startTimecode) { _ in
            draftController.syncStartTimecodeFromModel(
                line,
                fps: fps,
                hideFrames: hideTimecodeFrames,
                isFocused: false
            )
        }
        .onChange(of: line.endTimecode) { _ in
            draftController.syncEndTimecodeFromModel(
                line,
                fps: fps,
                hideFrames: hideTimecodeFrames,
                isFocused: false
            )
        }
        .onChange(of: hideTimecodeFrames) { _ in
            draftController.updateForHideFramesChange(
                line: line,
                fps: fps,
                hideFrames: hideTimecodeFrames,
                isStartFocused: false,
                isEndFocused: false
            )
        }
    }

    private func rowScaffold<Content: View>(
        @ViewBuilder content: () -> Content
    ) -> some View {
        HStack(alignment: .top, spacing: 8) {
            dragHandleView
            content()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(10)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(backgroundColor)
                .overlay(
                    RoundedRectangle(cornerRadius: 10)
                        .stroke(borderColor, lineWidth: (isSelected || isActiveSearchSelection || isEditable) ? 2 : 1)
                )
        )
        .overlay(alignment: .leading) {
            if isEditable, let currentSpeakerAppearance {
                RoundedRectangle(cornerRadius: 2)
                    .fill(currentSpeakerAppearance.rowAccentColor)
                    .frame(width: 3)
                    .padding(.leading, dragHandleWidth + 6)
                    .padding(.vertical, 12)
            }
        }
    }

    @ViewBuilder
    private var interactiveRowContent: some View {
        VStack(alignment: .leading, spacing: 8) {
            rowHeader(
                speakerView: AnyView(speakerFieldView),
                startView: AnyView(startFieldView),
                endView: isEndTimecodeFieldHidden ? nil : AnyView(endFieldView)
            )

            if isEditable {
                TextEditor(text: editableTextDraftBinding)
                    .font(.system(size: replicaTextFontSize))
                    .scrollContentBackground(.hidden)
                    .padding(6)
                    .background(
                        RoundedRectangle(cornerRadius: 6)
                            .fill(Color(nsColor: .textBackgroundColor))
                    )
                    .frame(minHeight: 66)
                    .focused($focusedField, equals: .replicaText)
            } else {
                Text(line.text)
                    .font(.system(size: replicaTextFontSize))
                    .frame(maxWidth: .infinity, minHeight: 66, alignment: .topLeading)
                    .padding(6)
                    .background(
                        RoundedRectangle(cornerRadius: 6)
                            .fill(Color(nsColor: .textBackgroundColor))
                    )
            }

            if !issues.isEmpty {
                issuesView
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder
    private var readOnlyRowContent: some View {
        VStack(alignment: .leading, spacing: 8) {
            rowHeader(
                speakerView: AnyView(
                    speakerReadOnlyField(
                        value: line.speaker,
                        placeholder: "Speaker"
                    )
                ),
                startView: AnyView(
                    readOnlyField(
                        value: resolvedDisplayedStartTimecode,
                        placeholder: "Start",
                        width: 115,
                        monospaced: true
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 6)
                            .stroke(hasStartChronologyIssue ? Color.red.opacity(0.85) : Color.clear, lineWidth: 1.25)
                    )
                ),
                endView: isEndTimecodeFieldHidden ? nil : AnyView(
                    readOnlyField(
                        value: resolvedDisplayedEndTimecode,
                        placeholder: "End",
                        width: 115,
                        monospaced: true
                    )
                )
            )

            Text(line.text)
                .font(.system(size: replicaTextFontSize))
                .frame(maxWidth: .infinity, minHeight: 66, alignment: .topLeading)
                .padding(6)
                .background(
                    RoundedRectangle(cornerRadius: 6)
                        .fill(Color(nsColor: .textBackgroundColor))
                )

            Text("Replika \(line.index) / \(totalLineCount)")
                .font(.caption2)
                .foregroundStyle(.secondary)

            if !issues.isEmpty {
                issuesView
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var backgroundColor: Color {
        if isEditable {
            return Color.orange.opacity(0.22)
        }
        if isSelected || isActiveSearchSelection {
            return Color.blue.opacity(0.20)
        }
        if hasStartChronologyIssue {
            return Color.red.opacity(0.06)
        }
        return .clear
    }

    private var borderColor: Color {
        if isEditable {
            return Color.orange.opacity(0.9)
        }
        if isSelected || isActiveSearchSelection {
            return Color.blue.opacity(0.75)
        }
        if hasStartChronologyIssue {
            return Color.red.opacity(0.65)
        }
        return .clear
    }

    private var currentSpeakerAppearance: SpeakerAppearance? {
        let speakerValue = isEditable ? draftController.speakerDraft : line.speaker
        return SpeakerAppearanceService.resolvedAppearance(
            for: speakerValue,
            overridesByKey: speakerColorOverridesByKey
        )
    }

    private var editableTextDraftBinding: Binding<String> {
        Binding(
            get: { draftController.editableTextDraft },
            set: { draftController.editableTextDraft = $0 }
        )
    }

    private var speakerDraftBinding: Binding<String> {
        Binding(
            get: { draftController.speakerDraft },
            set: { draftController.speakerDraft = $0 }
        )
    }

    private var startTimecodeDraftBinding: Binding<String> {
        Binding(
            get: { draftController.startTimecodeDraft },
            set: { draftController.startTimecodeDraft = $0 }
        )
    }

    private var endTimecodeDraftBinding: Binding<String> {
        Binding(
            get: { draftController.endTimecodeDraft },
            set: { draftController.endTimecodeDraft = $0 }
        )
    }

    private var resolvedDisplayedStartTimecode: String {
        draftController.resolvedDisplayedStartTimecode(
            for: line,
            fps: fps,
            hideFrames: hideTimecodeFrames
        )
    }

    private var resolvedDisplayedEndTimecode: String {
        draftController.resolvedDisplayedEndTimecode(
            for: line,
            fps: fps,
            hideFrames: hideTimecodeFrames
        )
    }

    private func rowHeader(
        speakerView: AnyView,
        startView: AnyView,
        endView: AnyView?
    ) -> some View {
        HStack(alignment: .center, spacing: 8) {
            Text(String(format: "%04d", line.index))
                .font(.system(.caption, design: .monospaced).weight(.bold))
                .foregroundStyle(.secondary)
                .frame(width: 46, alignment: .leading)

            speakerView
            startView

            if let endView {
                endView
            }

            Button("S") {
                onSetStart()
            }
            .buttonStyle(.bordered)
            .disabled(!(isEditable || isTimecodeEditableWhileSelected))

            Button("E") {
                onSetEnd()
            }
            .buttonStyle(.bordered)
            .disabled(!(isEditable || isTimecodeEditableWhileSelected))
        }
    }

    private var issuesView: some View {
        VStack(alignment: .leading, spacing: 4) {
            ForEach(issues, id: \.self) { issue in
                Text("• \(issue)")
                    .font(.caption2)
                    .foregroundStyle(.red)
                    .lineLimit(2)
            }
        }
    }

    private var isTimecodeEditableWhileSelected: Bool {
        isTimecodeModeEnabled && isSelected
    }

    private var isTimecodeFieldEditable: Bool {
        isEditable || isTimecodeEditableWhileSelected
    }

    private var shouldCaptureRowTapGestures: Bool {
        !usesInteractiveRowPath
    }

    private var shouldFlushDraftsOnDisappear: Bool {
        draftController.shouldFlushOnDisappear(
            comparedTo: line,
            fps: fps,
            hideFrames: hideTimecodeFrames,
            isEditable: isEditable,
            hasFocusedField: focusedField != nil
        )
    }

    private var shouldAutoFocusStartTimecode: Bool {
        isTimecodeModeEnabled && isSelected && !isEditable && isTimecodeFieldEditable
    }

    @ViewBuilder
    private var startFieldView: some View {
        if isTimecodeFieldEditable {
            TextField("Start", text: startTimecodeDraftBinding)
                .textFieldStyle(.roundedBorder)
                .font(.system(.caption, design: .monospaced))
                .frame(width: 115)
                .focused($focusedField, equals: .startTimecode)
                .onSubmit {
                    commitStartTimecodeDraft()
                }
                .overlay(
                    RoundedRectangle(cornerRadius: 6)
                        .stroke(hasStartChronologyIssue ? Color.red.opacity(0.85) : Color.clear, lineWidth: 1.25)
                )
        } else {
            readOnlyField(
                value: resolvedDisplayedStartTimecode,
                placeholder: "Start",
                width: 115,
                monospaced: true
            )
            .overlay(
                RoundedRectangle(cornerRadius: 6)
                    .stroke(hasStartChronologyIssue ? Color.red.opacity(0.85) : Color.clear, lineWidth: 1.25)
            )
        }
    }

    @ViewBuilder
    private var endFieldView: some View {
        if isTimecodeFieldEditable {
            TextField("End", text: endTimecodeDraftBinding)
                .textFieldStyle(.roundedBorder)
                .font(.system(.caption, design: .monospaced))
                .frame(width: 115)
                .focused($focusedField, equals: .endTimecode)
                .onSubmit {
                    commitEndTimecodeDraft()
                }
        } else {
            readOnlyField(
                value: resolvedDisplayedEndTimecode,
                placeholder: "End",
                width: 115,
                monospaced: true
            )
        }
    }

    @ViewBuilder
    private var speakerFieldView: some View {
        if isEditable {
            speakerFieldChrome(speakerValue: draftController.speakerDraft, placeholder: "Speaker") {
                TextField("Speaker", text: speakerDraftBinding)
                    .textFieldStyle(.plain)
                    .focused($focusedField, equals: .speaker)
                    .onSubmit {
                        logSpeakerAutocompleteEvent(
                            "ROW_SPEAKER_TEXTFIELD_ONSUBMIT",
                            fields: [
                                ("tx", SpeakerAutocompleteDebugLog.shortID(pendingSpeakerAutocompleteTransactionID)),
                                ("lineID", SpeakerAutocompleteDebugLog.shortID(lineID)),
                                ("speakerDraft", draftController.speakerDraft),
                                ("lineSpeaker", line.speaker),
                                ("focusedField", focusedFieldDebugDescription(focusedField))
                            ]
                        )
                        commitSpeakerDraft(debugTransactionID: pendingSpeakerAutocompleteTransactionID)
                    }
            }
            .anchorPreference(key: SpeakerSuggestionAnchorPreferenceKey.self, value: .bounds) { anchor in
                guard shouldShowSpeakerSuggestions else { return [] }
                return [
                    SpeakerSuggestionAnchorPreferenceEntry(
                        lineID: lineID,
                        query: speakerSuggestionQuery,
                        suggestions: matchingSpeakerSuggestions,
                        anchor: anchor
                    )
                ]
            }
        } else {
            speakerReadOnlyField(
                value: line.speaker,
                placeholder: "Speaker"
            )
        }
    }

    private func speakerReadOnlyField(
        value: String,
        placeholder: String
    ) -> some View {
        speakerFieldChrome(speakerValue: value, placeholder: placeholder) {
            let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
            Text(trimmed.isEmpty ? placeholder : value)
                .lineLimit(1)
                .foregroundStyle(trimmed.isEmpty ? .secondary : .primary)
        }
    }

    private func speakerFieldChrome<Content: View>(
        speakerValue: String,
        placeholder _: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        let appearance = SpeakerAppearanceService.resolvedAppearance(
            for: speakerValue,
            overridesByKey: speakerColorOverridesByKey
        )
        let baseFill = isEditable ? Color(nsColor: .textBackgroundColor) : Color(nsColor: .controlBackgroundColor)

        return HStack(spacing: 8) {
            if let appearance {
                Circle()
                    .fill(appearance.swatchColor)
                    .frame(width: 10, height: 10)
            }

            content()
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.horizontal, 10)
        .frame(width: speakerFieldWidth, height: 28, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 6)
                .fill(appearance?.fieldFillColor ?? baseFill)
                .overlay(
                    RoundedRectangle(cornerRadius: 6)
                        .stroke(
                            appearance?.fieldBorderColor ?? Color.secondary.opacity(isEditable ? 0.28 : 0.18),
                            lineWidth: appearance == nil ? 1 : 1.2
                        )
                )
        )
    }

    private func readOnlyField(
        value: String,
        placeholder: String,
        width: CGFloat,
        monospaced: Bool
    ) -> some View {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return ZStack(alignment: .leading) {
            RoundedRectangle(cornerRadius: 6)
                .fill(Color(nsColor: .controlBackgroundColor))
            Text(trimmed.isEmpty ? placeholder : value)
                .font(monospaced ? .system(.caption, design: .monospaced) : .body)
                .foregroundStyle(trimmed.isEmpty ? .secondary : .primary)
                .lineLimit(1)
                .padding(.horizontal, 10)
        }
        .frame(width: width, height: 28)
    }

    @ViewBuilder
    private var dragHandleView: some View {
        let isHandleHighlighted = isSelected && shouldCaptureRowTapGestures
        let base = ZStack {
            RoundedRectangle(cornerRadius: 5)
                .fill(isHandleHighlighted ? Color.accentColor.opacity(0.18) : Color.clear)
                .frame(width: dragHandleWidth, height: 20)
            Image(systemName: "line.3.horizontal")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(Color.secondary.opacity(0.85))
        }
        .frame(width: dragHandleWidth, height: 22)
        .contentShape(Rectangle())
        .help("Pretahni repliku")

        if let dragItemProvider {
            base
                .onDrag {
                    dragItemProvider()
                } preview: {
                    DragGhostPreview(
                        index: line.index,
                        speaker: line.speaker,
                        startTimecode: resolvedDisplayedStartTimecode,
                        text: line.text
                    )
                }
        } else {
            base
                .opacity(0.45)
        }
    }

    private func focusStartTimecodeIfNeeded() {
        guard shouldAutoFocusStartTimecode else { return }
        DispatchQueue.main.async {
            focusedField = .startTimecode
        }
    }

    private func focusReplicaTextFromRequestIfNeeded() {
        guard replicaTextFocusRequestLineID == lineID else { return }
        guard lastHandledReplicaTextFocusToken != replicaTextFocusRequestToken else { return }
        guard isEditable else { return }
        lastHandledReplicaTextFocusToken = replicaTextFocusRequestToken
        DispatchQueue.main.async {
            focusedField = .replicaText
        }
    }

    private func focusStartTimecodeFromShortcutIfNeeded() {
        guard startTimecodeFocusRequestLineID == lineID else { return }
        guard lastHandledStartTimecodeFocusToken != startTimecodeFocusRequestToken else { return }
        guard isTimecodeFieldEditable else { return }
        lastHandledStartTimecodeFocusToken = startTimecodeFocusRequestToken
        focusedField = .startTimecode
    }

    private func commitSpeakerDraft(debugTransactionID: UUID? = nil) {
        guard isBoundToExpectedLine else { return }
        let resolvedTransactionID = debugTransactionID ?? pendingSpeakerAutocompleteTransactionID
        logSpeakerAutocompleteEvent(
            "ROW_SPEAKER_MODEL_COMMIT_BEGIN",
            fields: [
                ("tx", SpeakerAutocompleteDebugLog.shortID(resolvedTransactionID)),
                ("lineID", SpeakerAutocompleteDebugLog.shortID(lineID)),
                ("speakerDraft", draftController.speakerDraft),
                ("lineSpeakerBefore", line.speaker)
            ]
        )

        var onModelCommitCalled = false
        let didChange = draftController.commitSpeakerIfNeeded(into: &line) { field in
            onModelCommitCalled = true
            onModelCommit(field)
        }
        logSpeakerAutocompleteEvent(
            "ROW_SPEAKER_MODEL_COMMIT_END",
            fields: [
                ("tx", SpeakerAutocompleteDebugLog.shortID(resolvedTransactionID)),
                ("lineID", SpeakerAutocompleteDebugLog.shortID(lineID)),
                ("lineSpeakerAfter", line.speaker),
                ("changed", String(didChange)),
                ("onModelCommitCalled", String(onModelCommitCalled))
            ]
        )
    }

    private func applySpeakerSuggestionSelectionIfNeeded() {
        guard let selection = speakerSuggestionSelection else { return }
        logSpeakerAutocompleteEvent(
            "ROW_RELAY_RECEIVED",
            fields: [
                ("tx", SpeakerAutocompleteDebugLog.shortID(selection.transactionID)),
                ("rowLineID", SpeakerAutocompleteDebugLog.shortID(lineID)),
                ("selectionLineID", SpeakerAutocompleteDebugLog.shortID(selection.lineID)),
                ("suggestion", selection.suggestion),
                ("isEditable", String(isEditable)),
                ("focusedField", focusedFieldDebugDescription(focusedField)),
                ("speakerDraftBefore", draftController.speakerDraft),
                ("lineSpeakerBefore", line.speaker),
                ("alreadyHandled", String(lastHandledSpeakerSuggestionDeliveryToken == selection.deliveryToken))
            ]
        )
        guard selection.lineID == lineID else { return }
        guard lastHandledSpeakerSuggestionDeliveryToken != selection.deliveryToken else { return }
        guard isEditable else { return }

        lastHandledSpeakerSuggestionDeliveryToken = selection.deliveryToken
        pendingSpeakerAutocompleteTransactionID = selection.transactionID
        pendingSpeakerAutocompleteSuggestion = selection.suggestion
        draftController.syncSpeakerFromModel(
            line,
            isFocused: focusedField == .speaker,
            forceWhileFocused: true
        )
        logSpeakerAutocompleteEvent(
            "ROW_SPEAKER_DRAFT_UPDATED",
            fields: [
                ("tx", SpeakerAutocompleteDebugLog.shortID(selection.transactionID)),
                ("lineID", SpeakerAutocompleteDebugLog.shortID(lineID)),
                ("speakerDraftAfter", draftController.speakerDraft)
            ]
        )
        if focusedField != .speaker {
            focusedField = .speaker
        }
    }

    private var shouldShowSpeakerSuggestions: Bool {
        isEditable && focusedField == .speaker && !matchingSpeakerSuggestions.isEmpty
    }

    private var speakerSuggestionQuery: String {
        draftController.speakerDraft.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var matchingSpeakerSuggestions: [String] {
        guard !speakerSuggestionQuery.isEmpty else { return speakerSuggestions }

        let lowerQuery = speakerSuggestionQuery.lowercased()
        let prefixMatches = speakerSuggestions.filter {
            $0.lowercased().hasPrefix(lowerQuery)
        }
        let containsMatches = speakerSuggestions.filter {
            !$0.lowercased().hasPrefix(lowerQuery) && $0.lowercased().contains(lowerQuery)
        }
        return prefixMatches + containsMatches
    }

    private func logSpeakerAutocompleteEvent(
        _ event: String,
        fields: [(String, String?)]
    ) {
        SpeakerAutocompleteDebugLog.append(
            enabled: isDevModeEnabled,
            event: event,
            fields: fields
        )
    }

    private func focusedFieldDebugDescription(_ field: FocusField?) -> String {
        switch field {
        case .replicaText:
            return "replicaText"
        case .speaker:
            return "speaker"
        case .startTimecode:
            return "startTimecode"
        case .endTimecode:
            return "endTimecode"
        case nil:
            return "nil"
        }
    }

    private func commitStartTimecodeDraft() {
        guard isBoundToExpectedLine else { return }
        draftController.commitStartTimecodeIfNeeded(
            into: &line,
            fps: fps,
            hideFrames: hideTimecodeFrames,
            onCommit: onModelCommit
        )
    }

    private func commitEndTimecodeDraft() {
        guard isBoundToExpectedLine else { return }
        draftController.commitEndTimecodeIfNeeded(
            into: &line,
            fps: fps,
            hideFrames: hideTimecodeFrames,
            onCommit: onModelCommit
        )
    }

    private func flushAllDraftsToBinding() {
        guard isBoundToExpectedLine else { return }
        draftController.flushAll(
            into: &line,
            fps: fps,
            hideFrames: hideTimecodeFrames,
            onCommit: onModelCommit
        )
    }
}

private struct ReadOnlyRowInteractionCaptureView: NSViewRepresentable {
    let onSingleClick: (Bool) -> Void
    let onDoubleClick: () -> Void

    func makeNSView(context: Context) -> ClickCaptureView {
        let view = ClickCaptureView()
        view.onSingleClick = onSingleClick
        view.onDoubleClick = onDoubleClick
        return view
    }

    func updateNSView(_ nsView: ClickCaptureView, context: Context) {
        nsView.onSingleClick = onSingleClick
        nsView.onDoubleClick = onDoubleClick
    }

    final class ClickCaptureView: NSView {
        var onSingleClick: ((Bool) -> Void)?
        var onDoubleClick: (() -> Void)?

        override var isFlipped: Bool { true }

        override func hitTest(_ point: NSPoint) -> NSView? {
            bounds.contains(point) ? self : nil
        }

        override func mouseDown(with event: NSEvent) {
            window?.makeFirstResponder(nil)

            if event.clickCount >= 2 {
                onDoubleClick?()
                return
            }

            onSingleClick?(event.modifierFlags.contains(.shift))
        }

        override func scrollWheel(with event: NSEvent) {
            nextResponder?.scrollWheel(with: event)
        }
    }
}

private struct DragGhostPreview: View {
    let index: Int
    let speaker: String
    let startTimecode: String
    let text: String

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                Text(String(format: "%04d", index))
                    .font(.system(.caption, design: .monospaced).weight(.bold))
                    .foregroundStyle(.secondary)
                if !startTimecode.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    Text(startTimecode)
                        .font(.system(.caption, design: .monospaced))
                        .foregroundStyle(.secondary)
                }
                if !speaker.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    Text(speaker)
                        .font(.caption.weight(.semibold))
                        .lineLimit(1)
                }
            }

            Text(text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "Prazdna replika" : text)
                .font(.subheadline)
                .lineLimit(2)
                .foregroundStyle(.primary)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .frame(width: 280, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(.regularMaterial)
                .overlay(
                    RoundedRectangle(cornerRadius: 10)
                        .stroke(Color.accentColor.opacity(0.5), lineWidth: 1)
                )
        )
    }
}
