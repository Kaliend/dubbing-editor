import Foundation
#if canImport(XCTest)
import XCTest
@testable import DubbingEditor

final class PlaybackWaveformProjectionServiceTests: XCTestCase {
    func testProjectToTimelinePadsTrailingSilenceWhenExternalAudioIsShorter() {
        let input: [Float] = [0.2, 0.4, 0.6, 0.8]

        let projected = PlaybackWaveformProjectionService.projectToTimeline(
            samples: input,
            mediaDurationSeconds: 5,
            timelineDurationSeconds: 10
        )

        XCTAssertEqual(projected.count, 4)
        XCTAssertEqual(projected[0], 0.4, accuracy: 0.0001)
        XCTAssertEqual(projected[1], 0.8, accuracy: 0.0001)
        XCTAssertEqual(projected[2], 0, accuracy: 0.0001)
        XCTAssertEqual(projected[3], 0, accuracy: 0.0001)
    }

    func testProjectToTimelineTruncatesAndStretchesWhenExternalAudioIsLonger() {
        let input: [Float] = [0.1, 0.3, 0.5, 0.7]

        let projected = PlaybackWaveformProjectionService.projectToTimeline(
            samples: input,
            mediaDurationSeconds: 10,
            timelineDurationSeconds: 5
        )

        XCTAssertEqual(projected.count, 4)
        XCTAssertEqual(projected[0], 0.1, accuracy: 0.0001)
        XCTAssertEqual(projected[1], 0.1667, accuracy: 0.0001)
        XCTAssertEqual(projected[2], 0.2333, accuracy: 0.0001)
        XCTAssertEqual(projected[3], 0.3, accuracy: 0.0001)
    }

    func testProjectToTimelineReturnsOriginalSamplesWhenDurationsMatch() {
        let input: [Float] = [0.15, 0.45, 0.75]

        let projected = PlaybackWaveformProjectionService.projectToTimeline(
            samples: input,
            mediaDurationSeconds: 8,
            timelineDurationSeconds: 8
        )

        XCTAssertEqual(projected, input)
    }
}
#endif
