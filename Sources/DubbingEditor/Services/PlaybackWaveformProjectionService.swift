import Foundation

enum PlaybackWaveformProjectionService {
    static func projectToTimeline(
        samples: [Float],
        mediaDurationSeconds: Double?,
        timelineDurationSeconds: Double?
    ) -> [Float] {
        guard !samples.isEmpty else { return [] }
        guard
            let mediaDurationSeconds,
            let timelineDurationSeconds,
            mediaDurationSeconds.isFinite,
            timelineDurationSeconds.isFinite,
            mediaDurationSeconds > 0,
            timelineDurationSeconds > 0
        else {
            return samples
        }

        let activeDuration = min(mediaDurationSeconds, timelineDurationSeconds)
        guard activeDuration > 0 else {
            return Array(repeating: 0, count: samples.count)
        }

        let targetCount = samples.count
        let sourceFraction = max(0, min(1, activeDuration / mediaDurationSeconds))
        let activeFraction = max(0, min(1, activeDuration / timelineDurationSeconds))
        let sourceCount = max(1, min(targetCount, Int((Double(targetCount) * sourceFraction).rounded())))
        let activeCount = max(1, min(targetCount, Int((Double(targetCount) * activeFraction).rounded())))

        let sourceSamples = Array(samples.prefix(sourceCount))
        let projected = resampleEnvelope(sourceSamples, to: activeCount)
        guard activeCount < targetCount else {
            return projected
        }

        return projected + Array(repeating: 0, count: targetCount - activeCount)
    }

    private static func resampleEnvelope(_ samples: [Float], to targetCount: Int) -> [Float] {
        guard !samples.isEmpty, targetCount > 0 else { return [] }
        if samples.count == targetCount {
            return samples
        }
        if samples.count > targetCount {
            return downsampleEnvelope(samples, to: targetCount)
        }
        return upsampleEnvelope(samples, to: targetCount)
    }

    private static func downsampleEnvelope(_ samples: [Float], to targetCount: Int) -> [Float] {
        let bucketSize = Double(samples.count) / Double(targetCount)
        var result: [Float] = []
        result.reserveCapacity(targetCount)

        for index in 0..<targetCount {
            let start = Int(Double(index) * bucketSize)
            let end = Int(Double(index + 1) * bucketSize)
            if start >= samples.count {
                result.append(0)
                continue
            }

            let clampedEnd = max(start + 1, min(end, samples.count))
            result.append(samples[start..<clampedEnd].max() ?? 0)
        }

        return result
    }

    private static func upsampleEnvelope(_ samples: [Float], to targetCount: Int) -> [Float] {
        guard samples.count >= 2 else {
            return Array(repeating: samples.first ?? 0, count: targetCount)
        }

        var result: [Float] = []
        result.reserveCapacity(targetCount)
        let lastIndex = samples.count - 1

        for outputIndex in 0..<targetCount {
            let position = Double(outputIndex) * Double(lastIndex) / Double(max(targetCount - 1, 1))
            let lowerIndex = Int(position.rounded(.down))
            let upperIndex = min(lastIndex, lowerIndex + 1)
            let blend = Float(position - Double(lowerIndex))
            let lower = samples[lowerIndex]
            let upper = samples[upperIndex]
            result.append(lower + ((upper - lower) * blend))
        }

        return result
    }
}
