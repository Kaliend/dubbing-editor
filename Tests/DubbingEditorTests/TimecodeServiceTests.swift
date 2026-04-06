import Foundation
#if canImport(XCTest)
import XCTest
@testable import DubbingEditor

final class TimecodeServiceTests: XCTestCase {
    func testSecondsParsesFrameTimecode() {
        let seconds = TimecodeService.seconds(from: "01:02:03:12", fps: 24)
        XCTAssertNotNil(seconds)
        XCTAssertEqual(seconds ?? 0, 3723.5, accuracy: 0.0001)
    }

    func testSecondsParsesMillisecondTimecode() {
        let seconds = TimecodeService.seconds(from: "00:00:10.250", fps: 25)
        XCTAssertNotNil(seconds)
        XCTAssertEqual(seconds ?? 0, 10.25, accuracy: 0.0001)
    }

    func testSecondsParsesMillisecondTimecodeWithComma() {
        let seconds = TimecodeService.seconds(from: "00:00:10,250", fps: 25)
        XCTAssertNotNil(seconds)
        XCTAssertEqual(seconds ?? 0, 10.25, accuracy: 0.0001)
    }

    func testSecondsParsesClockTimecode() {
        let seconds = TimecodeService.seconds(from: "00:01:05", fps: 25)
        XCTAssertEqual(seconds, 65)
    }

    func testSecondsParsesMinuteSecondTimecode() {
        let seconds = TimecodeService.seconds(from: "01:05", fps: 25)
        XCTAssertEqual(seconds, 65)
    }

    func testTimecodeFromSecondsClampsToZero() {
        XCTAssertEqual(TimecodeService.timecode(from: -10, fps: 25), "00:00:00:00")
    }

    func testTimecodeFromSecondsIncludesFrames() {
        XCTAssertEqual(TimecodeService.timecode(from: 12.5, fps: 25), "00:00:12:12")
    }

    func testTimecodeWithoutFramesDropsFrameComponent() {
        XCTAssertEqual(TimecodeService.timecodeWithoutFrames(from: 12.9), "00:00:12")
        XCTAssertEqual(TimecodeService.timecodeWithoutFrames(from: 3723.5), "01:02:03")
    }

    func testDisplayTimecodeDropsFramesWithoutChangingVisibleFormat() {
        XCTAssertEqual(
            TimecodeService.displayTimecode("01:02:03:12", fps: 24, hideFrames: true),
            "01:02:03"
        )
        XCTAssertEqual(
            TimecodeService.displayTimecode("00:00:10,250", fps: 25, hideFrames: true),
            "00:00:10"
        )
        XCTAssertEqual(
            TimecodeService.displayTimecode("01:05", fps: 25, hideFrames: true),
            "00:01:05"
        )
        XCTAssertEqual(
            TimecodeService.displayTimecode("01:02:03:12", fps: 24, hideFrames: false),
            "01:02:03:12"
        )
    }

    func testOffsetParsesSignedSeconds() {
        XCTAssertEqual(TimecodeService.offsetSeconds(from: "-1.25", fps: 25), -1.25, accuracy: 0.0001)
        XCTAssertEqual(TimecodeService.offsetSeconds(from: "+1,5", fps: 25), 1.5, accuracy: 0.0001)
    }

    func testOffsetParsesSignedTimecode() {
        XCTAssertEqual(TimecodeService.offsetSeconds(from: "+00:00:02:12", fps: 25), 2.48, accuracy: 0.0001)
        XCTAssertEqual(TimecodeService.offsetSeconds(from: "-00:00:01:00", fps: 25), -1, accuracy: 0.0001)
    }

    func testOffsetRejectsInvalidValues() {
        XCTAssertNil(TimecodeService.offsetSeconds(from: "abc", fps: 25))
        XCTAssertNil(TimecodeService.offsetSeconds(from: "", fps: 25))
    }
}
#endif
