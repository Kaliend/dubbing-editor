import AVFoundation
import CryptoKit
import Foundation

enum VideoAudioChannelVariant: String, CaseIterable, Codable, Sendable {
    case stereo
    case leftOnly
    case rightOnly
    case muted

    init(muteLeftChannel: Bool, muteRightChannel: Bool) {
        switch (muteLeftChannel, muteRightChannel) {
        case (false, false):
            self = .stereo
        case (false, true):
            self = .leftOnly
        case (true, false):
            self = .rightOnly
        case (true, true):
            self = .muted
        }
    }

    var requiresDerivedStem: Bool {
        switch self {
        case .leftOnly, .rightOnly:
            return true
        case .stereo, .muted:
            return false
        }
    }

    fileprivate var preferredChannelIndex: Int? {
        switch self {
        case .leftOnly:
            return 0
        case .rightOnly:
            return 1
        case .stereo, .muted:
            return nil
        }
    }
}

enum ChannelDerivedAudioService {
    struct ResolvedVideoAudioSource: Sendable {
        enum CompositionInput: Sendable {
            case embeddedVideoTrack
            case derivedAudioFile(URL)
            case none
        }

        let variant: VideoAudioChannelVariant
        let compositionInput: CompositionInput
        let sourceHasAudioTrack: Bool
    }

    enum Error: LocalizedError {
        case missingVideoAudioTrack
        case unsupportedChannelIsolation(channelCount: Int)
        case cannotCreateAudioReader
        case cannotCreateCacheDirectory
        case cannotCreateOutputFile
        case audioReadFailed(String)
        case emptyDerivedAudio

        var errorDescription: String? {
            switch self {
            case .missingVideoAudioTrack:
                return String(localized: "error.channel.missing_audio_track", bundle: .appBundle)
            case .unsupportedChannelIsolation(let channelCount):
                return String(format: String(localized: "error.channel.unsupported_isolation", bundle: .appBundle), channelCount)
            case .cannotCreateAudioReader:
                return String(localized: "error.channel.cannot_create_reader", bundle: .appBundle)
            case .cannotCreateCacheDirectory:
                return String(localized: "error.channel.cannot_create_cache_dir", bundle: .appBundle)
            case .cannotCreateOutputFile:
                return String(localized: "error.channel.cannot_create_output_file", bundle: .appBundle)
            case .audioReadFailed(let reason):
                return String(format: String(localized: "error.channel.read_failed", bundle: .appBundle), reason)
            case .emptyDerivedAudio:
                return String(localized: "error.channel.empty_derived_audio", bundle: .appBundle)
            }
        }
    }

    static func resolveVideoAudioSource(
        for videoURL: URL,
        variant: VideoAudioChannelVariant
    ) async throws -> ResolvedVideoAudioSource {
        let asset = AVURLAsset(
            url: videoURL,
            options: [AVURLAssetPreferPreciseDurationAndTimingKey: false]
        )
        let audioTracks = try await asset.loadTracks(withMediaType: .audio)
        guard let sourceAudioTrack = audioTracks.first else {
            return ResolvedVideoAudioSource(
                variant: variant,
                compositionInput: .none,
                sourceHasAudioTrack: false
            )
        }

        switch variant {
        case .stereo:
            return ResolvedVideoAudioSource(
                variant: variant,
                compositionInput: .embeddedVideoTrack,
                sourceHasAudioTrack: true
            )
        case .muted:
            return ResolvedVideoAudioSource(
                variant: variant,
                compositionInput: .none,
                sourceHasAudioTrack: true
            )
        case .leftOnly, .rightOnly:
            let channelCount = try await sourceChannelCount(for: sourceAudioTrack)
            guard channelCount >= 2 else {
                throw Error.unsupportedChannelIsolation(channelCount: channelCount)
            }
            let derivedURL = try await prepareDerivedStem(
                from: asset,
                sourceTrack: sourceAudioTrack,
                videoURL: videoURL,
                variant: variant
            )
            return ResolvedVideoAudioSource(
                variant: variant,
                compositionInput: .derivedAudioFile(derivedURL),
                sourceHasAudioTrack: true
            )
        }
    }

    static func cacheIdentity(
        for videoURL: URL,
        modificationDate: Date?,
        fileSize: Int?,
        variant: VideoAudioChannelVariant
    ) -> String {
        let path = videoURL.standardizedFileURL.path
        let mtime = modificationDate?.timeIntervalSince1970 ?? 0
        let size = fileSize ?? 0
        let material = "\(path)|\(mtime)|\(size)|\(variant.rawValue)"
        let digest = SHA256.hash(data: Data(material.utf8))
        return digest.map { String(format: "%02x", $0) }.joined()
    }

    private static func prepareDerivedStem(
        from asset: AVAsset,
        sourceTrack: AVAssetTrack,
        videoURL: URL,
        variant: VideoAudioChannelVariant
    ) async throws -> URL {
        guard let channelIndex = variant.preferredChannelIndex else {
            throw Error.cannotCreateOutputFile
        }

        let cacheURL = try derivedStemURL(for: videoURL, variant: variant)
        if FileManager.default.fileExists(atPath: cacheURL.path) {
            return cacheURL
        }

        let directoryURL = cacheURL.deletingLastPathComponent()
        do {
            try FileManager.default.createDirectory(
                at: directoryURL,
                withIntermediateDirectories: true
            )
        } catch {
            throw Error.cannotCreateCacheDirectory
        }

        let tempURL = directoryURL.appendingPathComponent(UUID().uuidString).appendingPathExtension("caf")
        do {
            try await generateDerivedStem(
                from: asset,
                sourceTrack: sourceTrack,
                channelIndex: channelIndex,
                outputURL: tempURL
            )
            if FileManager.default.fileExists(atPath: cacheURL.path) {
                try FileManager.default.removeItem(at: cacheURL)
            }
            try FileManager.default.moveItem(at: tempURL, to: cacheURL)
            return cacheURL
        } catch {
            try? FileManager.default.removeItem(at: tempURL)
            throw error
        }
    }

    private static func derivedStemURL(
        for videoURL: URL,
        variant: VideoAudioChannelVariant
    ) throws -> URL {
        let values = try videoURL.resourceValues(forKeys: [.contentModificationDateKey, .fileSizeKey])
        let identity = cacheIdentity(
            for: videoURL,
            modificationDate: values.contentModificationDate,
            fileSize: values.fileSize,
            variant: variant
        )
        let root = try cacheRootURL()
        return root
            .appendingPathComponent(identity)
            .appendingPathExtension("caf")
    }

    private static func cacheRootURL() throws -> URL {
        guard
            let cachesDirectory = FileManager.default.urls(
                for: .cachesDirectory,
                in: .userDomainMask
            ).first
        else {
            throw Error.cannotCreateCacheDirectory
        }
        return cachesDirectory
            .appendingPathComponent("DubbingEditor", isDirectory: true)
            .appendingPathComponent("ChannelDerivedAudio", isDirectory: true)
    }

    private static func sourceChannelCount(for track: AVAssetTrack) async throws -> Int {
        let formatDescriptions = try await track.load(.formatDescriptions)
        for formatDescription in formatDescriptions {
            if let stream = CMAudioFormatDescriptionGetStreamBasicDescription(formatDescription) {
                return max(1, Int(stream.pointee.mChannelsPerFrame))
            }
        }
        return 2
    }

    private static func generateDerivedStem(
        from asset: AVAsset,
        sourceTrack: AVAssetTrack,
        channelIndex: Int,
        outputURL: URL
    ) async throws {
        let reader: AVAssetReader
        do {
            reader = try AVAssetReader(asset: asset)
        } catch {
            throw Error.cannotCreateAudioReader
        }
        let outputSettings: [String: Any] = [
            AVFormatIDKey: kAudioFormatLinearPCM,
            AVLinearPCMIsFloatKey: true,
            AVLinearPCMBitDepthKey: 32,
            AVLinearPCMIsNonInterleaved: false,
            AVLinearPCMIsBigEndianKey: false
        ]
        let output = AVAssetReaderTrackOutput(track: sourceTrack, outputSettings: outputSettings)
        output.alwaysCopiesSampleData = false
        guard reader.canAdd(output) else {
            throw Error.cannotCreateAudioReader
        }
        reader.add(output)

        let formatDescriptions: [CMFormatDescription]
        do {
            formatDescriptions = try await sourceTrack.load(.formatDescriptions)
        } catch {
            throw Error.cannotCreateOutputFile
        }
        guard
            let formatDescription = formatDescriptions.first,
            let stream = CMAudioFormatDescriptionGetStreamBasicDescription(formatDescription)
        else {
            throw Error.cannotCreateOutputFile
        }

        let sourceSampleRate = stream.pointee.mSampleRate > 0 ? stream.pointee.mSampleRate : 48_000
        guard
            let monoFormat = AVAudioFormat(
                commonFormat: .pcmFormatFloat32,
                sampleRate: sourceSampleRate,
                channels: 1,
                interleaved: false
            )
        else {
            throw Error.cannotCreateOutputFile
        }

        let outputFile: AVAudioFile
        do {
            outputFile = try AVAudioFile(
                forWriting: outputURL,
                settings: monoFormat.settings,
                commonFormat: .pcmFormatFloat32,
                interleaved: false
            )
        } catch {
            throw Error.cannotCreateOutputFile
        }

        guard reader.startReading() else {
            throw Error.audioReadFailed(reader.error?.localizedDescription ?? "AVAssetReader startReading failed")
        }

        var wroteFrames = false
        while reader.status == .reading {
            try Task.checkCancellation()
            guard let sampleBuffer = output.copyNextSampleBuffer() else { break }
            defer { CMSampleBufferInvalidate(sampleBuffer) }

            guard let monoBuffer = try monoBuffer(from: sampleBuffer, preferredChannelIndex: channelIndex, outputFormat: monoFormat) else {
                continue
            }

            do {
                try outputFile.write(from: monoBuffer)
            } catch {
                throw Error.audioReadFailed("Zapis audio dat selhal: \(error.localizedDescription)")
            }
            wroteFrames = true
        }

        if reader.status == .failed {
            throw Error.audioReadFailed(reader.error?.localizedDescription ?? "AVAssetReader failed")
        }

        guard wroteFrames else {
            throw Error.emptyDerivedAudio
        }
    }

    private static func monoBuffer(
        from sampleBuffer: CMSampleBuffer,
        preferredChannelIndex: Int,
        outputFormat: AVAudioFormat
    ) throws -> AVAudioPCMBuffer? {
        let frameCount = CMSampleBufferGetNumSamples(sampleBuffer)
        guard frameCount > 0 else { return nil }

        guard let formatDescription = CMSampleBufferGetFormatDescription(sampleBuffer),
              let stream = CMAudioFormatDescriptionGetStreamBasicDescription(formatDescription) else {
            return nil
        }

        let channelCount = max(1, Int(stream.pointee.mChannelsPerFrame))
        let channelIndex = min(preferredChannelIndex, max(0, channelCount - 1))
        guard
            let buffer = AVAudioPCMBuffer(
                pcmFormat: outputFormat,
                frameCapacity: AVAudioFrameCount(frameCount)
            ),
            let monoChannel = buffer.floatChannelData?[0]
        else {
            return nil
        }
        buffer.frameLength = AVAudioFrameCount(frameCount)

        var audioBufferList = AudioBufferList()
        var blockBuffer: CMBlockBuffer?
        let status = CMSampleBufferGetAudioBufferListWithRetainedBlockBuffer(
            sampleBuffer,
            bufferListSizeNeededOut: nil,
            bufferListOut: &audioBufferList,
            bufferListSize: MemoryLayout<AudioBufferList>.size,
            blockBufferAllocator: nil,
            blockBufferMemoryAllocator: nil,
            flags: UInt32(kCMSampleBufferFlag_AudioBufferList_Assure16ByteAlignment),
            blockBufferOut: &blockBuffer
        )
        guard status == noErr else {
            throw Error.audioReadFailed("CMSampleBufferGetAudioBufferList failed (\(status))")
        }

        let audioBuffers = UnsafeMutableAudioBufferListPointer(&audioBufferList)
        if audioBuffers.count >= channelCount {
            guard
                let sourceData = audioBuffers[channelIndex].mData?.assumingMemoryBound(to: Float.self)
            else {
                return nil
            }
            monoChannel.update(from: sourceData, count: frameCount)
            return buffer
        }

        guard
            let interleavedData = audioBuffers.first?.mData?.assumingMemoryBound(to: Float.self)
        else {
            return nil
        }

        for frameIndex in 0 ..< frameCount {
            monoChannel[frameIndex] = interleavedData[(frameIndex * channelCount) + channelIndex]
        }
        return buffer
    }
}
