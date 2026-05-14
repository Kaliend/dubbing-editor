import Foundation
#if canImport(XCTest)
import XCTest
@testable import DubbingEditor

final class ProjectWorkTrackerTests: XCTestCase {
    func testTrackerCountsOnlyWhileWindowIsActiveAndActivityIsFresh() {
        var tracker = ProjectWorkTracker()
        let startedAt = Date(timeIntervalSince1970: 1_000)

        XCTAssertFalse(tracker.noteActivity(at: startedAt))
        XCTAssertEqual(tracker.currentTrackedSeconds(at: startedAt.addingTimeInterval(10)), 0, accuracy: 0.001)

        XCTAssertFalse(tracker.setWindowActive(true, at: startedAt))
        XCTAssertFalse(tracker.noteActivity(at: startedAt))

        XCTAssertEqual(tracker.currentTrackedSeconds(at: startedAt.addingTimeInterval(12)), 12, accuracy: 0.001)
        XCTAssertEqual(tracker.currentTrackedSeconds(at: startedAt.addingTimeInterval(35)), 30, accuracy: 0.001)

        XCTAssertTrue(tracker.sync(at: startedAt.addingTimeInterval(35)))
        XCTAssertEqual(tracker.currentTrackedSeconds(at: startedAt.addingTimeInterval(35)), 30, accuracy: 0.001)
    }

    func testTrackerPausesImmediatelyWhenWindowResignsActive() {
        var tracker = ProjectWorkTracker()
        let startedAt = Date(timeIntervalSince1970: 2_000)

        XCTAssertFalse(tracker.setWindowActive(true, at: startedAt))
        XCTAssertFalse(tracker.noteActivity(at: startedAt))
        XCTAssertTrue(tracker.setWindowActive(false, at: startedAt.addingTimeInterval(9)))

        XCTAssertEqual(tracker.currentTrackedSeconds(at: startedAt.addingTimeInterval(20)), 9, accuracy: 0.001)
    }

    func testRestorePersistedSecondsResetsTransientSessionState() {
        var tracker = ProjectWorkTracker()
        let startedAt = Date(timeIntervalSince1970: 3_000)

        XCTAssertFalse(tracker.setWindowActive(true, at: startedAt))
        XCTAssertFalse(tracker.noteActivity(at: startedAt))
        tracker.restorePersistedSeconds(125)

        XCTAssertEqual(tracker.currentTrackedSeconds(at: startedAt.addingTimeInterval(10)), 125, accuracy: 0.001)
        XCTAssertFalse(tracker.isActivelyTracking(at: startedAt.addingTimeInterval(10)))
    }
}
#endif
