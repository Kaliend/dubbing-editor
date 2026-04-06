import SwiftUI

struct SpeakerSuggestionSelection: Equatable {
    let lineID: DialogueLine.ID
    let suggestion: String
    let transactionID: UUID
    let deliveryToken: UUID

    init(
        lineID: DialogueLine.ID,
        suggestion: String,
        transactionID: UUID = UUID(),
        deliveryToken: UUID = UUID()
    ) {
        self.lineID = lineID
        self.suggestion = suggestion
        self.transactionID = transactionID
        self.deliveryToken = deliveryToken
    }
}

struct SpeakerAutocompleteSnapshot: Equatable {
    let lineID: DialogueLine.ID
    let query: String
    let suggestions: [String]
}

struct SpeakerAutocompleteState: Equatable {
    private struct DismissedSignature: Equatable {
        let lineID: DialogueLine.ID
        let query: String
    }

    private(set) var lineID: DialogueLine.ID?
    private(set) var query: String = ""
    private(set) var suggestions: [String] = []
    private(set) var selectedIndex: Int?
    private var dismissedSignature: DismissedSignature?

    var isPresented: Bool {
        guard !suggestions.isEmpty, currentSignature != nil else {
            return false
        }
        return dismissedSignature != currentSignature
    }

    var activeSuggestion: String? {
        guard isPresented, let selectedIndex, suggestions.indices.contains(selectedIndex) else {
            return nil
        }
        return suggestions[selectedIndex]
    }

    mutating func update(snapshot: SpeakerAutocompleteSnapshot?) {
        guard let snapshot, !snapshot.suggestions.isEmpty else {
            clear()
            return
        }

        let previousSignature = currentSignature
        let previousSuggestions = suggestions

        lineID = snapshot.lineID
        query = snapshot.query
        suggestions = snapshot.suggestions

        if dismissedSignature != currentSignature {
            dismissedSignature = nil
        }

        if previousSignature != currentSignature || previousSuggestions != snapshot.suggestions {
            selectedIndex = nil
        } else if let selectedIndex, selectedIndex >= snapshot.suggestions.count {
            self.selectedIndex = snapshot.suggestions.indices.last
        }
    }

    mutating func moveSelection(step: Int) {
        guard isPresented, !suggestions.isEmpty else { return }

        if step > 0 {
            if let selectedIndex {
                self.selectedIndex = min(selectedIndex + 1, suggestions.count - 1)
            } else {
                selectedIndex = 0
            }
            return
        }

        if step < 0 {
            if let selectedIndex {
                self.selectedIndex = max(selectedIndex - 1, 0)
            } else {
                selectedIndex = suggestions.count - 1
            }
        }
    }

    func suggestion(at index: Int?) -> String? {
        guard let index, suggestions.indices.contains(index) else { return nil }
        return suggestions[index]
    }

    func suggestionForCommit(preferredIndex: Int?) -> String? {
        guard isPresented, !suggestions.isEmpty else { return nil }

        if let suggestion = suggestion(at: preferredIndex) {
            return suggestion
        }
        if let suggestion = suggestion(at: selectedIndex) {
            return suggestion
        }
        return suggestions.first
    }

    mutating func dismiss() {
        guard let currentSignature else {
            clear()
            return
        }
        dismissedSignature = currentSignature
        selectedIndex = nil
    }

    mutating func clear() {
        lineID = nil
        query = ""
        suggestions = []
        selectedIndex = nil
        dismissedSignature = nil
    }

    private var currentSignature: DismissedSignature? {
        guard let lineID else { return nil }
        return DismissedSignature(lineID: lineID, query: query)
    }
}

struct SpeakerSuggestionAnchorPreferenceEntry {
    let lineID: DialogueLine.ID
    let query: String
    let suggestions: [String]
    let anchor: Anchor<CGRect>
}

enum SpeakerSuggestionOverlayLayout {
    static let panelWidth: CGFloat = 210
    static let verticalGap: CGFloat = 4
    static let cornerRadius: CGFloat = 7
    static let shadowRadius: CGFloat = 5
    static let shadowYOffset: CGFloat = 2
    static let rowHeight: CGFloat = 30
    static let maxVisibleRows: CGFloat = 8
    static let panelMaxHeight: CGFloat = rowHeight * maxVisibleRows

    static func usesScrollingList(for suggestionCount: Int) -> Bool {
        CGFloat(suggestionCount) > maxVisibleRows
    }
}

struct SpeakerSuggestionAnchorPreferenceKey: PreferenceKey {
    static var defaultValue: [SpeakerSuggestionAnchorPreferenceEntry] = []

    static func reduce(value: inout [SpeakerSuggestionAnchorPreferenceEntry], nextValue: () -> [SpeakerSuggestionAnchorPreferenceEntry]) {
        value.append(contentsOf: nextValue())
    }
}

struct SpeakerSuggestionOverlayHost: View {
    let entries: [SpeakerSuggestionAnchorPreferenceEntry]
    let visibleLineIDs: Set<DialogueLine.ID>
    let autocompleteState: SpeakerAutocompleteState
    let speakerColorOverridesByKey: [String: String]
    let onActiveSnapshotChange: (SpeakerAutocompleteSnapshot?) -> Void
    let onSelectIndex: (Int) -> Void

    private var availableEntry: SpeakerSuggestionAnchorPreferenceEntry? {
        if let activeLineID = autocompleteState.lineID {
            return entries.last(where: {
                $0.lineID == activeLineID &&
                visibleLineIDs.contains($0.lineID) &&
                !$0.suggestions.isEmpty
            })
        }
        return entries.last(where: { visibleLineIDs.contains($0.lineID) && !$0.suggestions.isEmpty })
    }

    private var availableSnapshot: SpeakerAutocompleteSnapshot? {
        guard let availableEntry else { return nil }
        return SpeakerAutocompleteSnapshot(
            lineID: availableEntry.lineID,
            query: availableEntry.query,
            suggestions: availableEntry.suggestions
        )
    }

    var body: some View {
        GeometryReader { proxy in
            if
                autocompleteState.isPresented,
                let entry = availableEntry,
                entry.lineID == autocompleteState.lineID
            {
                let frame = proxy[entry.anchor]
                suggestionList
                    .offset(
                        x: frame.minX,
                        y: frame.maxY + SpeakerSuggestionOverlayLayout.verticalGap
                    )
            }
        }
        .onAppear {
            onActiveSnapshotChange(availableSnapshot)
        }
        .onChange(of: availableSnapshot) { snapshot in
            onActiveSnapshotChange(snapshot)
        }
        .onDisappear {
            onActiveSnapshotChange(nil)
        }
        .zIndex(300)
    }

    private var suggestionList: some View {
        suggestionPanelContainer {
            if SpeakerSuggestionOverlayLayout.usesScrollingList(for: autocompleteState.suggestions.count) {
                scrollingSuggestionList
            } else {
                staticSuggestionList
            }
        }
    }

    private var staticSuggestionList: some View {
        suggestionRows(lazy: false)
    }

    private var scrollingSuggestionList: some View {
        ScrollViewReader { proxy in
            ScrollView(.vertical) {
                suggestionRows(lazy: true)
            }
            .frame(maxHeight: SpeakerSuggestionOverlayLayout.panelMaxHeight)
            .onAppear {
                scrollSelectionIfNeeded(with: proxy, animated: false)
            }
            .onChange(of: autocompleteState.selectedIndex) { _ in
                scrollSelectionIfNeeded(with: proxy, animated: true)
            }
        }
    }

    @ViewBuilder
    private func suggestionRows(lazy: Bool) -> some View {
        if lazy {
            LazyVStack(alignment: .leading, spacing: 0) {
                suggestionRowButtons
            }
        } else {
            VStack(alignment: .leading, spacing: 0) {
                suggestionRowButtons
            }
        }
    }

    private var suggestionRowButtons: some View {
        ForEach(Array(autocompleteState.suggestions.enumerated()), id: \.offset) { index, suggestion in
            let appearance = SpeakerAppearanceService.resolvedAppearance(
                for: suggestion,
                overridesByKey: speakerColorOverridesByKey
            )
            Button {
                onSelectIndex(index)
            } label: {
                HStack(spacing: 8) {
                    if let appearance {
                        Circle()
                            .fill(appearance.swatchColor)
                            .frame(width: 8, height: 8)
                    }

                    Text(suggestion)
                        .lineLimit(1)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 5)
                .frame(height: SpeakerSuggestionOverlayLayout.rowHeight)
            }
            .buttonStyle(.plain)
            .background(
                index == (autocompleteState.selectedIndex ?? 0)
                    ? Color.accentColor.opacity(0.18)
                    : Color(nsColor: .controlBackgroundColor)
            )
            .id(index)
        }
    }

    private func suggestionPanelContainer<Content: View>(
        @ViewBuilder content: () -> Content
    ) -> some View {
        content()
            .background(
                RoundedRectangle(cornerRadius: SpeakerSuggestionOverlayLayout.cornerRadius)
                    .fill(Color(nsColor: .windowBackgroundColor))
                    .overlay(
                        RoundedRectangle(cornerRadius: SpeakerSuggestionOverlayLayout.cornerRadius)
                            .stroke(Color.secondary.opacity(0.25), lineWidth: 1)
                    )
            )
            .frame(width: SpeakerSuggestionOverlayLayout.panelWidth)
            .shadow(
                color: .black.opacity(0.18),
                radius: SpeakerSuggestionOverlayLayout.shadowRadius,
                y: SpeakerSuggestionOverlayLayout.shadowYOffset
            )
    }

    private func scrollSelectionIfNeeded(
        with proxy: ScrollViewProxy,
        animated: Bool
    ) {
        guard let index = autocompleteState.selectedIndex ?? autocompleteState.suggestions.indices.first else {
            return
        }
        if animated {
            withAnimation(.easeInOut(duration: 0.12)) {
                proxy.scrollTo(index, anchor: .center)
            }
        } else {
            proxy.scrollTo(index, anchor: .center)
        }
    }
}
