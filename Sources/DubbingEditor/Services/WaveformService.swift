import AVFoundation
import Foundation

enum WaveformLoadSource {
    case cache
    case generated
}

struct WaveformBuildResult {
    let samples: [Float]
    let leftSamples: [Float]
    let rightSamples: [Float]
    let source: WaveformLoadSource
    let durationSeconds: Double?
}

enum WaveformService {
    private static let cacheMagic = "DBEWFM1"
    private static let cacheVersion: UInt32 = 2

    static func buildWaveform(
        from videoURL: URL,
        sampleCount: Int = 1200,
        preferCache: Bool = true
    ) async throws -> WaveformBuildResult {
        let durationSeconds = await loadDurationSeconds(from: videoURL)
        if preferCache, let cached = try? loadCachedWaveform(for: videoURL, desiredSampleCount: sampleCount) {
            return WaveformBuildResult(
                samples: cached.mono,
                leftSamples: cached.left,
                rightSamples: cached.right,
                source: .cache,
                durationSeconds: durationSeconds
            )
        }

        let generated = try await generateWaveform(from: videoURL, sampleCount: sampleCount)
        if !generated.mono.isEmpty {
            try? saveCachedWaveform(generated, for: videoURL)
        }
        return WaveformBuildResult(
            samples: generated.mono,
            leftSamples: generated.left,
            rightSamples: generated.right,
            source: .generated,
            durationSeconds: durationSeconds
        )
    }

    static func cacheURL(for videoURL: URL) -> URL {
        URL(fileURLWithPath: videoURL.path + ".dbe.waveform")
    }

    static func cacheExists(for videoURL: URL) -> Bool {
        FileManager.default.fileExists(atPath: cacheURL(for: videoURL).path)
    }

    static func cacheSizeBytes(for videoURL: URL) -> UInt64? {
        let target = cacheURL(for: videoURL)
        guard let attributes = try? FileManager.default.attributesOfItem(atPath: target.path) else {
            return nil
        }
        return (attributes[.size] as? NSNumber)?.uint64Value
    }

    @discardableResult
    static func deleteCache(for videoURL: URL) throws -> Bool {
        let target = cacheURL(for: videoURL)
        guard FileManager.default.fileExists(atPath: target.path) else {
            return false
        }
        try FileManager.default.removeItem(at: target)
        return true
    }

    private static func loadDurationSeconds(from videoURL: URL) async -> Double? {
        let asset = AVURLAsset(
            url: videoURL,
            options: [AVURLAssetPreferPreciseDurationAndTimingKey: false]
        )
        guard let duration = try? await asset.load(.duration) else {
            return nil
        }
        let seconds = duration.seconds
        guard duration.isNumeric, seconds.isFinite, seconds > 0 else {
            return nil
        }
        return seconds
    }

    private static func generateWaveform(from videoURL: URL, sampleCount: Int) async throws -> CachedWaveform {
        let asset = AVURLAsset(url: videoURL)
        let audioTracks = try await asset.loadTracks(withMediaType: .audio)
        guard let track = audioTracks.first else {
            throw EditorError.noAudioTrack
        }
        let channelCount = max(1, try await detectChannelCount(for: track))

        let floatSettings: [String: Any] = [
            AVFormatIDKey: kAudioFormatLinearPCM,
            AVLinearPCMBitDepthKey: 32,
            AVLinearPCMIsBigEndianKey: false,
            AVLinearPCMIsFloatKey: true,
            AVLinearPCMIsNonInterleaved: false
        ]
        let int16Settings: [String: Any] = [
            AVFormatIDKey: kAudioFormatLinearPCM,
            AVLinearPCMBitDepthKey: 16,
            AVLinearPCMIsBigEndianKey: false,
            AVLinearPCMIsFloatKey: false,
            AVLinearPCMIsNonInterleaved: false
        ]

        let amplitudes =
            (try? readAmplitudes(asset: asset, track: track, channelCount: channelCount, settings: floatSettings, sampleType: .float32))
            ?? (try? readAmplitudes(asset: asset, track: track, channelCount: channelCount, settings: int16Settings, sampleType: .int16))
            ?? CachedWaveform(mono: [], left: [], right: [])

        guard !amplitudes.mono.isEmpty else {
            return CachedWaveform(mono: [], left: [], right: [])
        }

        return CachedWaveform(
            mono: normalize(downsample(amplitudes: amplitudes.mono, targetCount: sampleCount)),
            left: normalize(downsample(amplitudes: amplitudes.left, targetCount: sampleCount)),
            right: normalize(downsample(amplitudes: amplitudes.right, targetCount: sampleCount))
        )
    }

    private static func loadCachedWaveform(for videoURL: URL, desiredSampleCount: Int) throws -> CachedWaveform? {
        guard desiredSampleCount > 0 else { return nil }

        let cacheURL = cacheURL(for: videoURL)
        guard FileManager.default.fileExists(atPath: cacheURL.path) else {
            return nil
        }

        guard let fingerprint = try fingerprint(for: videoURL) else {
            return nil
        }

        let data = try Data(contentsOf: cacheURL, options: [.mappedIfSafe])
        var cursor = 0

        guard let magic = readString(from: data, cursor: &cursor, length: cacheMagic.utf8.count), magic == cacheMagic else {
            return nil
        }

        guard let version = readUInt32LE(from: data, cursor: &cursor), version == cacheVersion else {
            return nil
        }

        guard
            let cachedFileSize = readUInt64LE(from: data, cursor: &cursor),
            let cachedModifiedAt = readInt64LE(from: data, cursor: &cursor)
        else {
            return nil
        }

        guard cachedFileSize == fingerprint.fileSize, cachedModifiedAt == fingerprint.modifiedAtMillis else {
            return nil
        }

        guard
            let monoLengthRaw = readUInt32LE(from: data, cursor: &cursor),
            let leftLengthRaw = readUInt32LE(from: data, cursor: &cursor),
            let rightLengthRaw = readUInt32LE(from: data, cursor: &cursor)
        else {
            return nil
        }

        let monoLength = Int(monoLengthRaw)
        let leftLength = Int(leftLengthRaw)
        let rightLength = Int(rightLengthRaw)
        guard monoLength > 0, monoLength <= 2_000_000 else { return nil }
        guard leftLength <= 2_000_000, rightLength <= 2_000_000 else { return nil }

        func readFloatArray(length: Int) -> [Float]? {
            if length == 0 { return [] }
            let expectedBytes = length * MemoryLayout<UInt32>.size
            guard cursor + expectedBytes <= data.count else { return nil }
            var values: [Float] = []
            values.reserveCapacity(length)
            for _ in 0..<length {
                guard let bitPattern = readUInt32LE(from: data, cursor: &cursor) else { return nil }
                values.append(Float(bitPattern: bitPattern))
            }
            return values
        }

        guard
            let monoRaw = readFloatArray(length: monoLength),
            let leftRaw = readFloatArray(length: leftLength),
            let rightRaw = readFloatArray(length: rightLength)
        else {
            return nil
        }

        guard let mono = normalizeToRequestedCount(monoRaw, desiredCount: desiredSampleCount) else {
            return nil
        }
        guard let left = normalizeToRequestedCount(leftRaw, desiredCount: desiredSampleCount) else {
            return nil
        }
        guard let right = normalizeToRequestedCount(rightRaw, desiredCount: desiredSampleCount) else {
            return nil
        }

        return CachedWaveform(mono: mono, left: left, right: right)
    }

    private static func saveCachedWaveform(_ waveform: CachedWaveform, for videoURL: URL) throws {
        guard !waveform.mono.isEmpty else { return }
        guard let fingerprint = try fingerprint(for: videoURL) else { return }

        var data = Data()
        guard let magicData = cacheMagic.data(using: .utf8) else { return }
        data.append(magicData)
        appendUInt32LE(cacheVersion, to: &data)
        appendUInt64LE(fingerprint.fileSize, to: &data)
        appendInt64LE(fingerprint.modifiedAtMillis, to: &data)
        appendUInt32LE(UInt32(waveform.mono.count), to: &data)
        appendUInt32LE(UInt32(waveform.left.count), to: &data)
        appendUInt32LE(UInt32(waveform.right.count), to: &data)

        for value in waveform.mono {
            appendUInt32LE(value.bitPattern, to: &data)
        }
        for value in waveform.left {
            appendUInt32LE(value.bitPattern, to: &data)
        }
        for value in waveform.right {
            appendUInt32LE(value.bitPattern, to: &data)
        }

        let cacheURL = cacheURL(for: videoURL)
        try data.write(to: cacheURL, options: .atomic)
    }

    private static func fingerprint(for videoURL: URL) throws -> VideoFingerprint? {
        let attributes = try FileManager.default.attributesOfItem(atPath: videoURL.path)
        guard
            let fileSizeNumber = attributes[.size] as? NSNumber,
            let modifiedAt = attributes[.modificationDate] as? Date
        else {
            return nil
        }

        return VideoFingerprint(
            fileSize: fileSizeNumber.uint64Value,
            modifiedAtMillis: Int64(modifiedAt.timeIntervalSince1970 * 1000)
        )
    }

    private static func readString(from data: Data, cursor: inout Int, length: Int) -> String? {
        guard cursor + length <= data.count else { return nil }
        let slice = data[cursor..<(cursor + length)]
        cursor += length
        return String(data: slice, encoding: .utf8)
    }

    private static func readUInt32LE(from data: Data, cursor: inout Int) -> UInt32? {
        guard cursor + 4 <= data.count else { return nil }
        let b0 = UInt32(data[cursor])
        let b1 = UInt32(data[cursor + 1]) << 8
        let b2 = UInt32(data[cursor + 2]) << 16
        let b3 = UInt32(data[cursor + 3]) << 24
        cursor += 4
        return b0 | b1 | b2 | b3
    }

    private static func readUInt64LE(from data: Data, cursor: inout Int) -> UInt64? {
        guard cursor + 8 <= data.count else { return nil }
        var value: UInt64 = 0
        for shift in 0..<8 {
            value |= UInt64(data[cursor + shift]) << (UInt64(shift) * 8)
        }
        cursor += 8
        return value
    }

    private static func readInt64LE(from data: Data, cursor: inout Int) -> Int64? {
        guard let unsigned = readUInt64LE(from: data, cursor: &cursor) else {
            return nil
        }
        return Int64(bitPattern: unsigned)
    }

    private static func appendUInt32LE(_ value: UInt32, to data: inout Data) {
        data.append(UInt8(truncatingIfNeeded: value))
        data.append(UInt8(truncatingIfNeeded: value >> 8))
        data.append(UInt8(truncatingIfNeeded: value >> 16))
        data.append(UInt8(truncatingIfNeeded: value >> 24))
    }

    private static func appendUInt64LE(_ value: UInt64, to data: inout Data) {
        for shift in 0..<8 {
            data.append(UInt8(truncatingIfNeeded: value >> (UInt64(shift) * 8)))
        }
    }

    private static func appendInt64LE(_ value: Int64, to data: inout Data) {
        appendUInt64LE(UInt64(bitPattern: value), to: &data)
    }

    private static func readAmplitudes(
        asset: AVURLAsset,
        track: AVAssetTrack,
        channelCount: Int,
        settings: [String: Any],
        sampleType: SampleType
    ) throws -> CachedWaveform {
        let reader = try AVAssetReader(asset: asset)
        let output = AVAssetReaderTrackOutput(track: track, outputSettings: settings)
        output.alwaysCopiesSampleData = false

        guard reader.canAdd(output) else {
            return CachedWaveform(mono: [], left: [], right: [])
        }
        reader.add(output)

        guard reader.startReading() else {
            return CachedWaveform(mono: [], left: [], right: [])
        }

        var monoAmplitudes: [Float] = []
        monoAmplitudes.reserveCapacity(10_000)
        var leftAmplitudes: [Float] = []
        leftAmplitudes.reserveCapacity(10_000)
        var rightAmplitudes: [Float] = []
        rightAmplitudes.reserveCapacity(10_000)

        while reader.status == .reading {
            guard let sampleBuffer = output.copyNextSampleBuffer() else {
                break
            }

            guard let blockBuffer = CMSampleBufferGetDataBuffer(sampleBuffer) else {
                CMSampleBufferInvalidate(sampleBuffer)
                continue
            }

            let length = CMBlockBufferGetDataLength(blockBuffer)
            if length <= 0 {
                CMSampleBufferInvalidate(sampleBuffer)
                continue
            }

            var lengthAtOffset = 0
            var totalLength = 0
            var dataPointer: UnsafeMutablePointer<Int8>?
            let pointerResult = CMBlockBufferGetDataPointer(
                blockBuffer,
                atOffset: 0,
                lengthAtOffsetOut: &lengthAtOffset,
                totalLengthOut: &totalLength,
                dataPointerOut: &dataPointer
            )

            if pointerResult == kCMBlockBufferNoErr, let dataPointer, totalLength > 0 {
                let rawBuffer = UnsafeRawBufferPointer(start: dataPointer, count: totalLength)
                switch sampleType {
                case .int16:
                    appendInt16Amplitudes(
                        from: rawBuffer,
                        channelCount: channelCount,
                        mono: &monoAmplitudes,
                        left: &leftAmplitudes,
                        right: &rightAmplitudes
                    )
                case .float32:
                    appendFloat32Amplitudes(
                        from: rawBuffer,
                        channelCount: channelCount,
                        mono: &monoAmplitudes,
                        left: &leftAmplitudes,
                        right: &rightAmplitudes
                    )
                }
            } else {
                var bufferData = Data(count: length)
                let copyResult = bufferData.withUnsafeMutableBytes { rawBuffer -> OSStatus in
                    guard let base = rawBuffer.baseAddress else { return -1 }
                    return CMBlockBufferCopyDataBytes(blockBuffer, atOffset: 0, dataLength: length, destination: base)
                }

                guard copyResult == kCMBlockBufferNoErr else {
                    CMSampleBufferInvalidate(sampleBuffer)
                    continue
                }

                switch sampleType {
                case .int16:
                    appendInt16Amplitudes(
                        from: bufferData,
                        channelCount: channelCount,
                        mono: &monoAmplitudes,
                        left: &leftAmplitudes,
                        right: &rightAmplitudes
                    )
                case .float32:
                    appendFloat32Amplitudes(
                        from: bufferData,
                        channelCount: channelCount,
                        mono: &monoAmplitudes,
                        left: &leftAmplitudes,
                        right: &rightAmplitudes
                    )
                }
            }

            CMSampleBufferInvalidate(sampleBuffer)
        }

        if reader.status == .failed {
            return CachedWaveform(mono: [], left: [], right: [])
        }

        return CachedWaveform(
            mono: monoAmplitudes,
            left: leftAmplitudes,
            right: rightAmplitudes
        )
    }

    private static func appendInt16Amplitudes(
        from data: Data,
        channelCount: Int,
        mono: inout [Float],
        left: inout [Float],
        right: inout [Float]
    ) {
        data.withUnsafeBytes { rawBuffer in
            appendInt16Amplitudes(
                from: rawBuffer,
                channelCount: channelCount,
                mono: &mono,
                left: &left,
                right: &right
            )
        }
    }

    private static func appendInt16Amplitudes(
        from rawBuffer: UnsafeRawBufferPointer,
        channelCount: Int,
        mono: inout [Float],
        left: inout [Float],
        right: inout [Float]
    ) {
        let valuesPerWindow = 256
        guard let pointer = rawBuffer.bindMemory(to: Int16.self).baseAddress else { return }
        let totalValues = rawBuffer.count / MemoryLayout<Int16>.size
        guard totalValues > 0 else { return }
        let clampedChannels = max(1, channelCount)
        let frameCount = totalValues / clampedChannels
        guard frameCount > 0 else { return }

        var offset = 0
        while offset < frameCount {
            let upper = min(offset + valuesPerWindow, frameCount)
            var monoMax: Float = 0
            var leftMax: Float = 0
            var rightMax: Float = 0

            for frameIndex in offset..<upper {
                let base = frameIndex * clampedChannels
                var frameMax: Float = 0
                for channelIndex in 0..<clampedChannels {
                    let normalized = abs(Float(pointer[base + channelIndex])) / Float(Int16.max)
                    frameMax = max(frameMax, normalized)
                    if channelIndex == 0 {
                        leftMax = max(leftMax, normalized)
                    } else if channelIndex == 1 {
                        rightMax = max(rightMax, normalized)
                    }
                }
                monoMax = max(monoMax, frameMax)
            }

            mono.append(monoMax)
            if clampedChannels >= 2 {
                left.append(leftMax)
                right.append(rightMax)
            }
            offset += valuesPerWindow
        }
    }

    private static func appendFloat32Amplitudes(
        from data: Data,
        channelCount: Int,
        mono: inout [Float],
        left: inout [Float],
        right: inout [Float]
    ) {
        data.withUnsafeBytes { rawBuffer in
            appendFloat32Amplitudes(
                from: rawBuffer,
                channelCount: channelCount,
                mono: &mono,
                left: &left,
                right: &right
            )
        }
    }

    private static func appendFloat32Amplitudes(
        from rawBuffer: UnsafeRawBufferPointer,
        channelCount: Int,
        mono: inout [Float],
        left: inout [Float],
        right: inout [Float]
    ) {
        let valuesPerWindow = 256
        guard let pointer = rawBuffer.bindMemory(to: Float32.self).baseAddress else { return }
        let totalValues = rawBuffer.count / MemoryLayout<Float32>.size
        guard totalValues > 0 else { return }
        let clampedChannels = max(1, channelCount)
        let frameCount = totalValues / clampedChannels
        guard frameCount > 0 else { return }

        var offset = 0
        while offset < frameCount {
            let upper = min(offset + valuesPerWindow, frameCount)
            var monoMax: Float = 0
            var leftMax: Float = 0
            var rightMax: Float = 0

            for frameIndex in offset..<upper {
                let base = frameIndex * clampedChannels
                var frameMax: Float = 0
                for channelIndex in 0..<clampedChannels {
                    let normalized = abs(pointer[base + channelIndex])
                    frameMax = max(frameMax, normalized)
                    if channelIndex == 0 {
                        leftMax = max(leftMax, normalized)
                    } else if channelIndex == 1 {
                        rightMax = max(rightMax, normalized)
                    }
                }
                monoMax = max(monoMax, frameMax)
            }

            mono.append(monoMax)
            if clampedChannels >= 2 {
                left.append(leftMax)
                right.append(rightMax)
            }
            offset += valuesPerWindow
        }
    }

    private static func detectChannelCount(for track: AVAssetTrack) async throws -> Int {
        let formatDescriptions = try await track.load(.formatDescriptions)
        for formatDescription in formatDescriptions {
            if let stream = CMAudioFormatDescriptionGetStreamBasicDescription(formatDescription) {
                return Int(stream.pointee.mChannelsPerFrame)
            }
        }
        return 1
    }

    private static func downsample(amplitudes: [Float], targetCount: Int) -> [Float] {
        guard targetCount > 0, amplitudes.count > targetCount else {
            return amplitudes
        }

        let bucketSize = Float(amplitudes.count) / Float(targetCount)
        var result: [Float] = []
        result.reserveCapacity(targetCount)

        for index in 0..<targetCount {
            let start = Int(Float(index) * bucketSize)
            let end = Int(Float(index + 1) * bucketSize)
            if start >= amplitudes.count {
                result.append(0)
                continue
            }

            let clampedEnd = max(start + 1, min(end, amplitudes.count))
            let slice = amplitudes[start..<clampedEnd]
            result.append(slice.max() ?? 0)
        }

        return result
    }

    private static func normalize(_ amplitudes: [Float]) -> [Float] {
        guard !amplitudes.isEmpty else { return [] }
        let maxValue = amplitudes.max() ?? 0
        guard maxValue > 0 else { return amplitudes }
        return amplitudes.map { min(1, $0 / maxValue) }
    }

    private static func normalizeToRequestedCount(_ amplitudes: [Float], desiredCount: Int) -> [Float]? {
        guard !amplitudes.isEmpty else { return [] }
        if amplitudes.count == desiredCount {
            return amplitudes
        }
        if amplitudes.count > desiredCount {
            return downsample(amplitudes: amplitudes, targetCount: desiredCount)
        }
        return nil
    }
}

private struct VideoFingerprint {
    let fileSize: UInt64
    let modifiedAtMillis: Int64
}

private enum SampleType {
    case int16
    case float32
}

private struct CachedWaveform {
    let mono: [Float]
    let left: [Float]
    let right: [Float]
}
