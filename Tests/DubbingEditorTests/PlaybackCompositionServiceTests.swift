import AVFoundation
import Foundation
#if canImport(XCTest)
import XCTest
@testable import DubbingEditor

final class PlaybackCompositionServiceTests: XCTestCase {
    func testAudioMixPlanUsesNoMixWhenNothingIsMuted() {
        let plan = PlaybackCompositionService.makeAudioMixPlan(
            videoAudioTrackID: 101,
            externalAudioTrackID: 202,
            isVideoAudioMuted: false,
            isExternalAudioMuted: false,
            muteLeftChannel: false,
            muteRightChannel: false
        )

        XCTAssertEqual(
            plan,
            .init(
                muteVideoTrack: false,
                muteExternalTrack: false,
                applyStereoChannelMuteToVideoTrack: false,
                tapForcedOff: false
            )
        )
        XCTAssertFalse(plan.requiresAudioMix)
    }

    func testAudioMixPlanKeepsOnlyTrackMuteResponsibilities() {
        let plan = PlaybackCompositionService.makeAudioMixPlan(
            videoAudioTrackID: 101,
            externalAudioTrackID: 202,
            isVideoAudioMuted: false,
            isExternalAudioMuted: true,
            muteLeftChannel: true,
            muteRightChannel: false
        )

        XCTAssertEqual(
            plan,
            .init(
                muteVideoTrack: false,
                muteExternalTrack: true,
                applyStereoChannelMuteToVideoTrack: false,
                tapForcedOff: true
            )
        )
        XCTAssertTrue(plan.requiresAudioMix)
    }

    func testAudioMixPlanCanMuteVideoTrackWithoutTap() {
        let plan = PlaybackCompositionService.makeAudioMixPlan(
            videoAudioTrackID: 101,
            externalAudioTrackID: nil,
            isVideoAudioMuted: true,
            isExternalAudioMuted: false,
            muteLeftChannel: true,
            muteRightChannel: true
        )

        XCTAssertEqual(
            plan,
            .init(
                muteVideoTrack: true,
                muteExternalTrack: false,
                applyStereoChannelMuteToVideoTrack: false,
                tapForcedOff: true
            )
        )
        XCTAssertTrue(plan.requiresAudioMix)
    }
}
#endif
