import AVFoundation
import Foundation

enum PlaybackCompositionService {
    struct BuildResult {
        let composition: AVComposition
        let videoAsset: AVAsset
        let videoAudioTrackID: CMPersistentTrackID?
        let externalAudioTrackID: CMPersistentTrackID?
        let sourceHasVideoAudioTrack: Bool
    }

    struct AudioMixPlan: Equatable {
        let muteVideoTrack: Bool
        let muteExternalTrack: Bool
        let applyStereoChannelMuteToVideoTrack: Bool
        let tapForcedOff: Bool

        var requiresAudioMix: Bool {
            muteVideoTrack || muteExternalTrack || applyStereoChannelMuteToVideoTrack
        }
    }

    enum BuildError: LocalizedError {
        case missingVideoTrack
        case missingVideoAudioTrack
        case missingExternalAudioTrack

        var errorDescription: String? {
            switch self {
            case .missingVideoTrack:
                return String(localized: "error.composition.missing_video_track")
            case .missingVideoAudioTrack:
                return String(localized: "error.composition.missing_video_audio_track")
            case .missingExternalAudioTrack:
                return String(localized: "error.composition.missing_external_audio_track")
            }
        }
    }

    static func buildPlayerItem(
        videoURL: URL,
        videoAudioVariant: VideoAudioChannelVariant,
        externalAudioURL: URL?
    ) async throws -> BuildResult {
        let videoAsset = AVURLAsset(
            url: videoURL,
            options: [AVURLAssetPreferPreciseDurationAndTimingKey: false]
        )
        let videoDuration = try await videoAsset.load(.duration)
        let videoTracks = try await videoAsset.loadTracks(withMediaType: .video)
        guard let sourceVideoTrack = videoTracks.first else {
            throw BuildError.missingVideoTrack
        }

        let composition = AVMutableComposition()
        guard
            let compositionVideoTrack = composition.addMutableTrack(
                withMediaType: .video,
                preferredTrackID: kCMPersistentTrackID_Invalid
            )
        else {
            throw BuildError.missingVideoTrack
        }

        try compositionVideoTrack.insertTimeRange(
            CMTimeRange(start: .zero, duration: videoDuration),
            of: sourceVideoTrack,
            at: .zero
        )
        compositionVideoTrack.preferredTransform = try await sourceVideoTrack.load(.preferredTransform)

        let resolvedVideoAudioSource = try await ChannelDerivedAudioService.resolveVideoAudioSource(
            for: videoURL,
            variant: videoAudioVariant
        )
        let videoAudioTrackID = try await insertVideoAudioTrackIfAvailable(
            from: resolvedVideoAudioSource,
            originalVideoAsset: videoAsset,
            duration: videoDuration,
            into: composition
        )
        let externalAudioTrackID = try await insertExternalAudioTrackIfAvailable(
            from: externalAudioURL,
            videoDuration: videoDuration,
            into: composition
        )

        return BuildResult(
            composition: composition,
            videoAsset: videoAsset,
            videoAudioTrackID: videoAudioTrackID,
            externalAudioTrackID: externalAudioTrackID,
            sourceHasVideoAudioTrack: resolvedVideoAudioSource.sourceHasAudioTrack
        )
    }

    static func makeAudioMixPlan(
        videoAudioTrackID: CMPersistentTrackID?,
        externalAudioTrackID: CMPersistentTrackID?,
        isVideoAudioMuted: Bool,
        isExternalAudioMuted: Bool,
        muteLeftChannel: Bool,
        muteRightChannel: Bool
    ) -> AudioMixPlan {
        let hasVideoAudioTrack = videoAudioTrackID != nil
        let hasExternalAudioTrack = externalAudioTrackID != nil
        let channelIsolationRequested = muteLeftChannel || muteRightChannel

        return AudioMixPlan(
            muteVideoTrack: hasVideoAudioTrack && isVideoAudioMuted,
            muteExternalTrack: hasExternalAudioTrack && isExternalAudioMuted,
            applyStereoChannelMuteToVideoTrack: false,
            tapForcedOff: channelIsolationRequested
        )
    }

    static func buildAudioMix(
        for asset: AVAsset,
        videoAudioTrackID: CMPersistentTrackID?,
        externalAudioTrackID: CMPersistentTrackID?,
        isVideoAudioMuted: Bool,
        isExternalAudioMuted: Bool,
        muteLeftChannel: Bool,
        muteRightChannel: Bool
    ) async -> AVAudioMix? {
        let plan = makeAudioMixPlan(
            videoAudioTrackID: videoAudioTrackID,
            externalAudioTrackID: externalAudioTrackID,
            isVideoAudioMuted: isVideoAudioMuted,
            isExternalAudioMuted: isExternalAudioMuted,
            muteLeftChannel: muteLeftChannel,
            muteRightChannel: muteRightChannel
        )
        guard plan.requiresAudioMix else { return nil }

        do {
            let audioTracks = try await asset.loadTracks(withMediaType: .audio)
            var parameters: [AVMutableAudioMixInputParameters] = []
            parameters.reserveCapacity(2)

            if
                let videoAudioTrackID,
                let videoTrack = audioTracks.first(where: { $0.trackID == videoAudioTrackID })
            {
                let input = AVMutableAudioMixInputParameters(track: videoTrack)
                if plan.muteVideoTrack {
                    input.setVolume(0, at: .zero)
                }
                if plan.muteVideoTrack {
                    parameters.append(input)
                }
            }

            if
                let externalAudioTrackID,
                let externalTrack = audioTracks.first(where: { $0.trackID == externalAudioTrackID }),
                plan.muteExternalTrack
            {
                let input = AVMutableAudioMixInputParameters(track: externalTrack)
                input.setVolume(0, at: .zero)
                parameters.append(input)
            }

            guard !parameters.isEmpty else { return nil }

            let mix = AVMutableAudioMix()
            mix.inputParameters = parameters
            return mix
        } catch {
            return nil
        }
    }

    private static func insertVideoAudioTrackIfAvailable(
        from source: ChannelDerivedAudioService.ResolvedVideoAudioSource,
        originalVideoAsset: AVAsset,
        duration: CMTime,
        into composition: AVMutableComposition
    ) async throws -> CMPersistentTrackID? {
        let sourceAudioTrack: AVAssetTrack?
        switch source.compositionInput {
        case .embeddedVideoTrack:
            let audioTracks = try await originalVideoAsset.loadTracks(withMediaType: .audio)
            sourceAudioTrack = audioTracks.first
        case .derivedAudioFile(let derivedAudioURL):
            let derivedAsset = AVURLAsset(
                url: derivedAudioURL,
                options: [AVURLAssetPreferPreciseDurationAndTimingKey: false]
            )
            let audioTracks = try await derivedAsset.loadTracks(withMediaType: .audio)
            guard let derivedTrack = audioTracks.first else {
                throw BuildError.missingVideoAudioTrack
            }
            sourceAudioTrack = derivedTrack
        case .none:
            sourceAudioTrack = nil
        }

        guard let sourceAudioTrack else {
            return nil
        }

        guard
            let compositionAudioTrack = composition.addMutableTrack(
                withMediaType: .audio,
                preferredTrackID: kCMPersistentTrackID_Invalid
            )
        else {
            return nil
        }

        try compositionAudioTrack.insertTimeRange(
            CMTimeRange(start: .zero, duration: duration),
            of: sourceAudioTrack,
            at: .zero
        )
        return compositionAudioTrack.trackID
    }

    private static func insertExternalAudioTrackIfAvailable(
        from externalAudioURL: URL?,
        videoDuration: CMTime,
        into composition: AVMutableComposition
    ) async throws -> CMPersistentTrackID? {
        guard let externalAudioURL else { return nil }

        let externalAsset = AVURLAsset(
            url: externalAudioURL,
            options: [AVURLAssetPreferPreciseDurationAndTimingKey: false]
        )
        let audioTracks = try await externalAsset.loadTracks(withMediaType: .audio)
        guard let sourceAudioTrack = audioTracks.first else {
            throw BuildError.missingExternalAudioTrack
        }

        let externalDuration = try await externalAsset.load(.duration)
        let insertionDuration = minimumPositiveDuration(videoDuration, externalDuration)
        guard insertionDuration.seconds > 0 else {
            throw BuildError.missingExternalAudioTrack
        }

        guard
            let compositionAudioTrack = composition.addMutableTrack(
                withMediaType: .audio,
                preferredTrackID: kCMPersistentTrackID_Invalid
            )
        else {
            throw BuildError.missingExternalAudioTrack
        }

        try compositionAudioTrack.insertTimeRange(
            CMTimeRange(start: .zero, duration: insertionDuration),
            of: sourceAudioTrack,
            at: .zero
        )
        return compositionAudioTrack.trackID
    }

    private static func minimumPositiveDuration(_ lhs: CMTime, _ rhs: CMTime) -> CMTime {
        if !lhs.isNumeric || lhs.seconds <= 0 { return .zero }
        if !rhs.isNumeric || rhs.seconds <= 0 { return .zero }
        return CMTimeCompare(lhs, rhs) <= 0 ? lhs : rhs
    }
}
