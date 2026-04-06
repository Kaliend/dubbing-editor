import Foundation
#if canImport(XCTest)
import XCTest
@testable import DubbingEditor

final class SpeakerSuggestionOverlayTests: XCTestCase {
    func testOverlayUsesStaticListAtOrBelowVisibleRowLimit() {
        XCTAssertFalse(SpeakerSuggestionOverlayLayout.usesScrollingList(for: 1))
        XCTAssertFalse(SpeakerSuggestionOverlayLayout.usesScrollingList(for: 8))
    }

    func testOverlayUsesScrollingListAboveVisibleRowLimit() {
        XCTAssertTrue(SpeakerSuggestionOverlayLayout.usesScrollingList(for: 9))
    }

    func testMoveDownFromNilSelectsFirstSuggestion() {
        var state = SpeakerAutocompleteState()
        state.update(snapshot: snapshot(query: "al", suggestions: ["Alice", "Alfred", "Alma"]))

        state.moveSelection(step: 1)

        XCTAssertTrue(state.isPresented)
        XCTAssertEqual(state.selectedIndex, 0)
        XCTAssertEqual(state.activeSuggestion, "Alice")
    }

    func testMoveUpFromNilSelectsLastSuggestion() {
        var state = SpeakerAutocompleteState()
        state.update(snapshot: snapshot(query: "al", suggestions: ["Alice", "Alfred", "Alma"]))

        state.moveSelection(step: -1)

        XCTAssertEqual(state.selectedIndex, 2)
        XCTAssertEqual(state.activeSuggestion, "Alma")
    }

    func testDismissKeepsPopupClosedUntilQueryChanges() {
        var state = SpeakerAutocompleteState()
        let initial = snapshot(query: "al", suggestions: ["Alice", "Alfred"])
        state.update(snapshot: initial)

        state.dismiss()
        state.update(snapshot: initial)

        XCTAssertFalse(state.isPresented)

        state.update(snapshot: snapshot(query: "ali", suggestions: ["Alice"]))

        XCTAssertTrue(state.isPresented)
        XCTAssertNil(state.selectedIndex)
    }

    func testQueryChangeResetsSelectedIndex() {
        var state = SpeakerAutocompleteState()
        state.update(snapshot: snapshot(query: "al", suggestions: ["Alice", "Alfred"]))
        state.moveSelection(step: 1)

        state.update(snapshot: snapshot(query: "alf", suggestions: ["Alfred"]))

        XCTAssertNil(state.selectedIndex)
        XCTAssertNil(state.activeSuggestion)
    }

    func testSuggestionForCommitFallsBackToFirstSuggestion() {
        var state = SpeakerAutocompleteState()
        state.update(snapshot: snapshot(query: "va", suggestions: ["Vanessa", "Valerie", "Vera"]))

        XCTAssertEqual(state.suggestionForCommit(preferredIndex: nil), "Vanessa")
    }

    func testSuggestionForCommitPrefersExplicitIndex() {
        var state = SpeakerAutocompleteState()
        state.update(snapshot: snapshot(query: "va", suggestions: ["Vanessa", "Valerie", "Vera"]))

        XCTAssertEqual(state.suggestionForCommit(preferredIndex: 2), "Vera")
    }

    private func snapshot(
        lineID: DialogueLine.ID = DialogueLine.ID(),
        query: String,
        suggestions: [String]
    ) -> SpeakerAutocompleteSnapshot {
        SpeakerAutocompleteSnapshot(
            lineID: lineID,
            query: query,
            suggestions: suggestions
        )
    }
}
#endif
