import AppKit
import SwiftUI

struct WaveformView: View {
    let samples: [Float]
    let playheadProgress: Double
    let selectedRangeProgress: ClosedRange<Double>?
    let isHighLoadMode: Bool
    let onScrubBegan: () -> Void
    let onScrubChanged: (Double) -> Void
    let onScrubEnded: (Double) -> Void

    @State private var isScrubbing = false
    @State private var zoomScale: Double = 1
    @State private var zoomCenterProgress: Double = 0.5
    @State private var cachedRenderKey: WaveformRenderKey?
    @State private var cachedBarPeaks: [Float] = []

    var body: some View {
        GeometryReader { geometry in
            let visible = visibleRange()
            let horizontalPadding: CGFloat = 4
            let availableWidth = max(1, geometry.size.width - (horizontalPadding * 2))
            let maxRenderableBars = isHighLoadMode ? 900 : 1400
            let barCount = max(1, min(maxRenderableBars, Int(availableWidth)))
            let renderKey = makeRenderKey(barCount: barCount, visible: visible)
            let barPeaks = peaksForRendering(renderKey: renderKey, barCount: barCount, visible: visible)
            ZStack(alignment: .leading) {
                RoundedRectangle(cornerRadius: 8)
                    .fill(Color(nsColor: .windowBackgroundColor).opacity(0.4))

                if samples.isEmpty {
                    Text("Waveform se zobrazi po nacteni videa")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 10)
                } else {
                    if let selectedRect = selectedRangeRect(in: visible, width: geometry.size.width) {
                        Rectangle()
                            .fill(Color.blue.opacity(0.16))
                            .frame(width: selectedRect.width)
                            .offset(x: selectedRect.minX)
                    }

                    Canvas { context, size in
                        let centerY = size.height / 2
                        let maxHalfHeight = max(2, (size.height / 2) - 3)

                        var bars = Path()
                        for barIndex in 0..<barCount {
                            let bucketPeak = barIndex < barPeaks.count ? barPeaks[barIndex] : 0

                            let amplitude = CGFloat(max(0, min(1, bucketPeak)))
                            let barHeight = max(2, amplitude * maxHalfHeight * 2)
                            let x = horizontalPadding + CGFloat(barIndex)
                            let y = centerY - (barHeight / 2)
                            bars.addRect(CGRect(x: x, y: y, width: 1, height: barHeight))
                        }

                        context.fill(bars, with: .color(.cyan.opacity(0.9)))
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)

                    if let playheadX = xPosition(for: max(0, min(1, playheadProgress)), in: visible, width: geometry.size.width) {
                        Rectangle()
                            .fill(Color.orange)
                            .frame(width: 2)
                            .offset(x: playheadX)
                    }
                }
            }
            .overlay {
                if !samples.isEmpty {
                    WaveformInputCaptureView(
                        onScrubBegan: { localX in
                            isScrubbing = true
                            onScrubBegan()
                            onScrubChanged(progressFromLocal(localX, in: visible))
                        },
                        onScrubChanged: { localX in
                            onScrubChanged(progressFromLocal(localX, in: visible))
                        },
                        onScrubEnded: { localX in
                            onScrubEnded(progressFromLocal(localX, in: visible))
                            isScrubbing = false
                        },
                        onZoom: { zoomUnits, localX in
                            applyZoom(units: zoomUnits, anchorLocalProgress: localX)
                        },
                        onPan: { progressDelta in
                            applyPan(progressDelta: progressDelta)
                        },
                        onResetZoom: {
                            resetZoom()
                        }
                    )
                }
            }
            .task(id: renderKey) {
                rebuildPeakCache(for: renderKey, barCount: barCount, visible: visible)
            }
            .onChange(of: samples.count) { count in
                if count == 0 {
                    resetZoom()
                } else {
                    clampZoomState()
                }
            }
        }
    }

    private struct WaveformRenderKey: Hashable {
        let sampleSignature: UInt64
        let barCount: Int
        let visibleLowerKey: Int
        let visibleUpperKey: Int
    }

    private func visibleRange() -> ClosedRange<Double> {
        let clampedScale = max(1, min(40, zoomScale))
        let windowLength = 1.0 / clampedScale
        guard windowLength < 1 else {
            return 0...1
        }

        let center = max(0, min(1, zoomCenterProgress))
        let half = windowLength / 2
        let lower = max(0, min(center - half, 1 - windowLength))
        let upper = min(1, lower + windowLength)
        return lower...upper
    }

    private func makeRenderKey(barCount: Int, visible: ClosedRange<Double>) -> WaveformRenderKey {
        WaveformRenderKey(
            sampleSignature: sampleSignature(),
            barCount: barCount,
            visibleLowerKey: quantizeProgress(visible.lowerBound),
            visibleUpperKey: quantizeProgress(visible.upperBound)
        )
    }

    private func quantizeProgress(_ value: Double) -> Int {
        Int((max(0, min(1, value)) * 100_000).rounded())
    }

    private func sampleSignature() -> UInt64 {
        guard !samples.isEmpty else { return 0 }
        let mid = samples[samples.count / 2]
        let first = UInt64(samples[0].bitPattern)
        let middle = UInt64(mid.bitPattern) << 1
        let last = UInt64(samples[samples.count - 1].bitPattern) << 2
        return first ^ middle ^ last ^ UInt64(samples.count)
    }

    private func peaksForRendering(
        renderKey: WaveformRenderKey,
        barCount: Int,
        visible: ClosedRange<Double>
    ) -> [Float] {
        if cachedRenderKey == renderKey, cachedBarPeaks.count == barCount {
            return cachedBarPeaks
        }
        return computePeaks(barCount: barCount, visible: visible)
    }

    private func rebuildPeakCache(
        for renderKey: WaveformRenderKey,
        barCount: Int,
        visible: ClosedRange<Double>
    ) {
        if cachedRenderKey == renderKey, cachedBarPeaks.count == barCount {
            return
        }
        cachedBarPeaks = computePeaks(barCount: barCount, visible: visible)
        cachedRenderKey = renderKey
    }

    private func computePeaks(barCount: Int, visible: ClosedRange<Double>) -> [Float] {
        guard !samples.isEmpty, barCount > 0 else { return [] }

        let windowLength = max(0.000_001, visible.upperBound - visible.lowerBound)
        let maxSampleIndex = max(0, samples.count - 1)
        let maxSampleIndexDouble = Double(maxSampleIndex)
        var peaks = Array(repeating: Float(0), count: barCount)

        for barIndex in 0..<barCount {
            let startLocalProgress = Double(barIndex) / Double(barCount)
            let endLocalProgress = Double(barIndex + 1) / Double(barCount)
            let startAbsoluteProgress = visible.lowerBound + (startLocalProgress * windowLength)
            let endAbsoluteProgress = visible.lowerBound + (endLocalProgress * windowLength)

            let startSampleIndex = min(
                maxSampleIndex,
                max(0, Int((startAbsoluteProgress * maxSampleIndexDouble).rounded(.down)))
            )
            let endSampleIndexExclusive = min(
                samples.count,
                max(
                    startSampleIndex + 1,
                    Int((endAbsoluteProgress * maxSampleIndexDouble).rounded(.up)) + 1
                )
            )

            var bucketPeak: Float = 0
            for sampleIndex in startSampleIndex..<endSampleIndexExclusive {
                bucketPeak = max(bucketPeak, samples[sampleIndex])
            }
            peaks[barIndex] = bucketPeak
        }

        return peaks
    }

    private func selectedRangeRect(in visible: ClosedRange<Double>, width: CGFloat) -> CGRect? {
        guard let selectedRangeProgress else { return nil }

        let lower = max(selectedRangeProgress.lowerBound, visible.lowerBound)
        let upper = min(selectedRangeProgress.upperBound, visible.upperBound)
        guard upper > lower else { return nil }

        let localLower = (lower - visible.lowerBound) / max(0.000_001, visible.upperBound - visible.lowerBound)
        let localUpper = (upper - visible.lowerBound) / max(0.000_001, visible.upperBound - visible.lowerBound)

        let x = CGFloat(localLower) * width
        let w = max(2, CGFloat(localUpper - localLower) * width)
        return CGRect(x: x, y: 0, width: w, height: 0)
    }

    private func xPosition(for absoluteProgress: Double, in visible: ClosedRange<Double>, width: CGFloat) -> CGFloat? {
        guard absoluteProgress >= visible.lowerBound, absoluteProgress <= visible.upperBound else {
            return nil
        }
        let local = (absoluteProgress - visible.lowerBound) / max(0.000_001, visible.upperBound - visible.lowerBound)
        return CGFloat(local) * width
    }

    private func sampleIndexForProgress(_ progress: Double) -> Int {
        guard samples.count > 1 else { return 0 }
        let clamped = max(0, min(1, progress))
        return min(samples.count - 1, Int(clamped * Double(samples.count - 1)))
    }

    private func progressFromLocal(_ localProgress: Double, in visible: ClosedRange<Double>) -> Double {
        let local = max(0, min(1, localProgress))
        return visible.lowerBound + (local * (visible.upperBound - visible.lowerBound))
    }

    private func applyZoom(units: CGFloat, anchorLocalProgress: Double) {
        guard !samples.isEmpty else { return }

        let oldRange = visibleRange()
        let oldLength = max(0.000_001, oldRange.upperBound - oldRange.lowerBound)
        let local = max(0, min(1, anchorLocalProgress))
        let anchorAbsolute = oldRange.lowerBound + (local * oldLength)

        let factor = exp(Double(units))
        let nextScale = max(1, min(40, zoomScale * factor))
        guard abs(nextScale - zoomScale) > 0.000_01 else { return }

        let newLength = 1.0 / nextScale
        if newLength >= 1 {
            zoomScale = 1
            zoomCenterProgress = 0.5
            return
        }

        var newLower = anchorAbsolute - (local * newLength)
        newLower = max(0, min(newLower, 1 - newLength))

        zoomScale = nextScale
        zoomCenterProgress = newLower + (newLength / 2)
    }

    private func applyPan(progressDelta: Double) {
        guard !samples.isEmpty else { return }

        let currentRange = visibleRange()
        let currentLength = max(0.000_001, currentRange.upperBound - currentRange.lowerBound)
        guard currentLength < 0.999_999 else { return }

        let maxLower = max(0, 1 - currentLength)
        let clampedDelta = max(-0.03, min(0.03, progressDelta))
        // Boost precision while zoomed in, but cap speed when zoomed out to avoid long jumps.
        let zoomAdaptiveMultiplier = max(0.05, min(0.65, currentLength * 1.35))
        var newLower = currentRange.lowerBound - (clampedDelta * zoomAdaptiveMultiplier)
        newLower = max(0, min(maxLower, newLower))
        zoomCenterProgress = newLower + (currentLength / 2)
    }

    private func resetZoom() {
        zoomScale = 1
        zoomCenterProgress = 0.5
        cachedRenderKey = nil
        cachedBarPeaks = []
    }

    private func clampZoomState() {
        zoomScale = max(1, min(40, zoomScale))
        zoomCenterProgress = max(0, min(1, zoomCenterProgress))
    }
}

private struct WaveformInputCaptureView: NSViewRepresentable {
    let onScrubBegan: (Double) -> Void
    let onScrubChanged: (Double) -> Void
    let onScrubEnded: (Double) -> Void
    let onZoom: (CGFloat, Double) -> Void
    let onPan: (Double) -> Void
    let onResetZoom: () -> Void

    func makeNSView(context: Context) -> WaveformInputCaptureNSView {
        let view = WaveformInputCaptureNSView()
        view.onScrubBegan = onScrubBegan
        view.onScrubChanged = onScrubChanged
        view.onScrubEnded = onScrubEnded
        view.onZoom = onZoom
        view.onPan = onPan
        view.onResetZoom = onResetZoom
        return view
    }

    func updateNSView(_ nsView: WaveformInputCaptureNSView, context: Context) {
        nsView.onScrubBegan = onScrubBegan
        nsView.onScrubChanged = onScrubChanged
        nsView.onScrubEnded = onScrubEnded
        nsView.onZoom = onZoom
        nsView.onPan = onPan
        nsView.onResetZoom = onResetZoom
    }
}

private final class WaveformInputCaptureNSView: NSView {
    var onScrubBegan: ((Double) -> Void)?
    var onScrubChanged: ((Double) -> Void)?
    var onScrubEnded: ((Double) -> Void)?
    var onZoom: ((CGFloat, Double) -> Void)?
    var onPan: ((Double) -> Void)?
    var onResetZoom: (() -> Void)?

    override var acceptsFirstResponder: Bool { true }

    override func mouseDown(with event: NSEvent) {
        window?.makeFirstResponder(self)
        if event.clickCount == 2 {
            onResetZoom?()
            return
        }
        let progress = localProgress(from: event)
        onScrubBegan?(progress)
    }

    override func mouseDragged(with event: NSEvent) {
        onScrubChanged?(localProgress(from: event))
    }

    override func mouseUp(with event: NSEvent) {
        onScrubEnded?(localProgress(from: event))
    }

    override func scrollWheel(with event: NSEvent) {
        let useZoomMode = event.modifierFlags.contains(.option) || event.modifierFlags.contains(.command)
        if useZoomMode {
            let dominantDelta = abs(event.scrollingDeltaY) >= abs(event.scrollingDeltaX)
                ? event.scrollingDeltaY
                : event.scrollingDeltaX
            let factor: CGFloat = event.hasPreciseScrollingDeltas ? 0.0085 : 0.05
            let zoomUnits = dominantDelta * factor
            if abs(zoomUnits) > 0.000_01 {
                onZoom?(zoomUnits, localProgress(from: event))
            }
            return
        }

        let dominantDelta = abs(event.scrollingDeltaX) >= abs(event.scrollingDeltaY)
            ? event.scrollingDeltaX
            : event.scrollingDeltaY
        let width = max(1, bounds.width)
        let normalized = Double(dominantDelta / width)
        guard abs(normalized) > 0.000_001 else { return }

        let sign = normalized >= 0 ? 1.0 : -1.0
        var magnitude = abs(normalized) * (event.hasPreciseScrollingDeltas ? 1.75 : 1.15)

        if !event.momentumPhase.isEmpty {
            // Prevent inertial overshoot from large trackpad flicks.
            magnitude *= 0.22
        }

        // Piecewise response: sensitive near-zero, strongly damped for fast swipes.
        let knee = 0.008
        if magnitude > knee {
            magnitude = knee + ((magnitude - knee) * 0.18)
        }

        let minNudge = event.hasPreciseScrollingDeltas ? 0.00025 : 0.00015
        let shapedDelta = sign * max(minNudge, min(0.03, magnitude))
        if abs(shapedDelta) > 0.000_01 {
            onPan?(shapedDelta)
        }
    }

    override func magnify(with event: NSEvent) {
        let zoomUnits = CGFloat(event.magnification)
        if abs(zoomUnits) > 0.000_01 {
            onZoom?(zoomUnits, localProgress(from: event))
        }
    }

    private func localProgress(from event: NSEvent) -> Double {
        let point = convert(event.locationInWindow, from: nil)
        let width = max(1, bounds.width)
        return Double(max(0, min(1, point.x / width)))
    }
}
