import AVFoundation
import AudioToolbox
import Foundation
import MediaToolbox

enum StereoChannelMuteService {
    private final class TapContext {
        let muteLeft: Bool
        let muteRight: Bool
        var formatDescription: AudioStreamBasicDescription?

        init(muteLeft: Bool, muteRight: Bool) {
            self.muteLeft = muteLeft
            self.muteRight = muteRight
        }
    }

    static func audioChannelCount(for asset: AVAsset) async -> Int {
        do {
            let tracks = try await asset.loadTracks(withMediaType: .audio)
            guard let firstTrack = tracks.first else { return 0 }
            let formatDescriptions = try await firstTrack.load(.formatDescriptions)
            for formatDescription in formatDescriptions {
                if let stream = CMAudioFormatDescriptionGetStreamBasicDescription(formatDescription) {
                    return Int(stream.pointee.mChannelsPerFrame)
                }
            }
            return 0
        } catch {
            return 0
        }
    }

    static func buildAudioMix(
        for asset: AVAsset,
        muteLeft: Bool,
        muteRight: Bool
    ) async -> AVAudioMix? {
        guard muteLeft || muteRight else { return nil }

        do {
            let tracks = try await asset.loadTracks(withMediaType: .audio)
            guard let firstTrack = tracks.first else { return nil }
            guard let tap = makeProcessingTap(muteLeft: muteLeft, muteRight: muteRight) else { return nil }

            let input = AVMutableAudioMixInputParameters(track: firstTrack)
            input.audioTapProcessor = tap
            let mix = AVMutableAudioMix()
            mix.inputParameters = [input]
            return mix
        } catch {
            return nil
        }
    }

    static func makeAudioTapProcessor(
        muteLeft: Bool,
        muteRight: Bool
    ) -> MTAudioProcessingTap? {
        guard muteLeft || muteRight else { return nil }
        return makeProcessingTap(muteLeft: muteLeft, muteRight: muteRight)
    }

    private static func makeProcessingTap(muteLeft: Bool, muteRight: Bool) -> MTAudioProcessingTap? {
        let context = TapContext(muteLeft: muteLeft, muteRight: muteRight)
        let contextPointer = Unmanaged.passRetained(context).toOpaque()
        var callbacks = MTAudioProcessingTapCallbacks(
            version: kMTAudioProcessingTapCallbacksVersion_0,
            clientInfo: contextPointer,
            init: tapInitCallback,
            finalize: tapFinalizeCallback,
            prepare: tapPrepareCallback,
            unprepare: tapUnprepareCallback,
            process: tapProcessCallback
        )

        var tap: MTAudioProcessingTap?
        let status = MTAudioProcessingTapCreate(
            kCFAllocatorDefault,
            &callbacks,
            kMTAudioProcessingTapCreationFlag_PostEffects,
            &tap
        )

        guard status == noErr, let tap else {
            Unmanaged<TapContext>.fromOpaque(contextPointer).release()
            return nil
        }

        return tap
    }

    private static let tapInitCallback: MTAudioProcessingTapInitCallback = { _, clientInfo, tapStorageOut in
        tapStorageOut.pointee = clientInfo
    }

    private static let tapFinalizeCallback: MTAudioProcessingTapFinalizeCallback = { tap in
        let rawStorage = MTAudioProcessingTapGetStorage(tap)
        Unmanaged<TapContext>.fromOpaque(rawStorage).release()
    }

    private static let tapPrepareCallback: MTAudioProcessingTapPrepareCallback = { tap, _, processingFormat in
        let rawStorage = MTAudioProcessingTapGetStorage(tap)
        let context = Unmanaged<TapContext>.fromOpaque(rawStorage).takeUnretainedValue()
        context.formatDescription = processingFormat.pointee
    }

    private static let tapUnprepareCallback: MTAudioProcessingTapUnprepareCallback = { tap in
        let rawStorage = MTAudioProcessingTapGetStorage(tap)
        let context = Unmanaged<TapContext>.fromOpaque(rawStorage).takeUnretainedValue()
        context.formatDescription = nil
    }

    private static let tapProcessCallback: MTAudioProcessingTapProcessCallback = {
        tap,
        frameCount,
        _,
        bufferListInOut,
        frameCountOut,
        flagsOut in

        let status = MTAudioProcessingTapGetSourceAudio(
            tap,
            frameCount,
            bufferListInOut,
            flagsOut,
            nil,
            frameCountOut
        )

        guard status == noErr else { return }
        let rawStorage = MTAudioProcessingTapGetStorage(tap)
        let context = Unmanaged<TapContext>.fromOpaque(rawStorage).takeUnretainedValue()
        process(
            context: context,
            frameCountOut: frameCountOut,
            bufferListInOut: bufferListInOut
        )
    }

    private static func process(
        context: TapContext,
        frameCountOut: UnsafeMutablePointer<CMItemCount>,
        bufferListInOut: UnsafeMutablePointer<AudioBufferList>
    ) {
        guard context.muteLeft || context.muteRight else { return }
        guard let format = context.formatDescription else { return }

        let channelCount = max(1, Int(format.mChannelsPerFrame))
        guard channelCount >= 2 else { return }

        let isNonInterleaved = (format.mFormatFlags & kAudioFormatFlagIsNonInterleaved) != 0
        let bitDepth = Int(format.mBitsPerChannel)
        let bytesPerSample = max(1, bitDepth / 8)
        let fallbackBytesPerFrame = bytesPerSample * channelCount
        let bytesPerFrame = max(1, Int(format.mBytesPerFrame == 0 ? UInt32(fallbackBytesPerFrame) : format.mBytesPerFrame))
        let requestedFrames = max(0, Int(frameCountOut.pointee))

        let buffers = UnsafeMutableAudioBufferListPointer(bufferListInOut)
        if buffers.isEmpty { return }

        // Treat channel-separated buffers the same as non-interleaved data.
        if isNonInterleaved || buffers.count >= channelCount {
            if context.muteLeft, buffers.indices.contains(0), let data = buffers[0].mData {
                memset(data, 0, Int(buffers[0].mDataByteSize))
            }
            if context.muteRight, buffers.indices.contains(1), let data = buffers[1].mData {
                memset(data, 0, Int(buffers[1].mDataByteSize))
            }
            return
        }

        guard let interleavedData = buffers[0].mData else { return }
        let byteSize = Int(buffers[0].mDataByteSize)
        let maxFrames = min(requestedFrames, byteSize / bytesPerFrame)
        guard maxFrames > 0 else { return }

        for frameIndex in 0 ..< maxFrames {
            let framePointer = interleavedData.advanced(by: frameIndex * bytesPerFrame)
            if context.muteLeft {
                memset(framePointer.advanced(by: 0 * bytesPerSample), 0, bytesPerSample)
            }
            if context.muteRight {
                memset(framePointer.advanced(by: 1 * bytesPerSample), 0, bytesPerSample)
            }
        }
    }
}
