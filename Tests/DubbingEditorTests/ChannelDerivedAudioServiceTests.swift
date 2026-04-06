import Foundation
#if canImport(XCTest)
import XCTest
@testable import DubbingEditor

final class ChannelDerivedAudioServiceTests: XCTestCase {
    func testVideoAudioChannelVariantMapsMuteStatesToExpectedStem() {
        XCTAssertEqual(
            VideoAudioChannelVariant(muteLeftChannel: false, muteRightChannel: false),
            .stereo
        )
        XCTAssertEqual(
            VideoAudioChannelVariant(muteLeftChannel: false, muteRightChannel: true),
            .leftOnly
        )
        XCTAssertEqual(
            VideoAudioChannelVariant(muteLeftChannel: true, muteRightChannel: false),
            .rightOnly
        )
        XCTAssertEqual(
            VideoAudioChannelVariant(muteLeftChannel: true, muteRightChannel: true),
            .muted
        )
    }

    func testCacheIdentityChangesWithVariantAndSourceFingerprint() {
        let url = URL(fileURLWithPath: "/tmp/example.mov")
        let modificationDate = Date(timeIntervalSince1970: 1_700_000_000)

        let stereoIdentity = ChannelDerivedAudioService.cacheIdentity(
            for: url,
            modificationDate: modificationDate,
            fileSize: 1024,
            variant: .stereo
        )
        let leftIdentity = ChannelDerivedAudioService.cacheIdentity(
            for: url,
            modificationDate: modificationDate,
            fileSize: 1024,
            variant: .leftOnly
        )
        let updatedIdentity = ChannelDerivedAudioService.cacheIdentity(
            for: url,
            modificationDate: modificationDate.addingTimeInterval(1),
            fileSize: 1024,
            variant: .leftOnly
        )

        XCTAssertNotEqual(stereoIdentity, leftIdentity)
        XCTAssertNotEqual(leftIdentity, updatedIdentity)
    }
}
#endif
