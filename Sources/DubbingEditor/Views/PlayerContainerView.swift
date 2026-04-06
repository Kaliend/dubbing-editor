import AVFoundation
import AppKit
import QuartzCore
import SwiftUI

struct PlayerContainerView: NSViewRepresentable {
    let player: AVPlayer
    let model: EditorViewModel

    func makeNSView(context: Context) -> ScrubbablePlayerLayerView {
        let view = ScrubbablePlayerLayerView()
        view.player = player
        view.debugModel = model
        return view
    }

    func updateNSView(_ nsView: ScrubbablePlayerLayerView, context: Context) {
        if nsView.player !== player {
            nsView.player = player
        }
        if nsView.debugModel !== model {
            nsView.debugModel = model
        }
    }
}

final class ScrubbablePlayerLayerView: NSView {
    private let playerLayer = AVPlayerLayer()
    private var shouldResumePlaybackAfterScrub = false
    private var lastScrubSeekTimestamp: TimeInterval = 0
    private var lastScrubInteractionTimestamp: TimeInterval = 0
    private var scrubSeekGeneration: UInt64 = 0
    private var activeScrubTraceGeneration: UInt64?
    private var pendingScrubTraceEndWorkItem: DispatchWorkItem?
    weak var debugModel: EditorViewModel?

    var player: AVPlayer? {
        didSet {
            playerLayer.player = player
            shouldResumePlaybackAfterScrub = false
            lastScrubSeekTimestamp = 0
            lastScrubInteractionTimestamp = 0
            scrubSeekGeneration = 0
            activeScrubTraceGeneration = nil
            pendingScrubTraceEndWorkItem?.cancel()
            pendingScrubTraceEndWorkItem = nil
        }
    }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.backgroundColor = NSColor.black.cgColor
        playerLayer.videoGravity = .resizeAspect
        playerLayer.drawsAsynchronously = true
        layer?.addSublayer(playerLayer)
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        wantsLayer = true
        layer?.backgroundColor = NSColor.black.cgColor
        playerLayer.videoGravity = .resizeAspect
        playerLayer.drawsAsynchronously = true
        layer?.addSublayer(playerLayer)
    }

    override func layout() {
        super.layout()
        playerLayer.frame = bounds
    }

    override func scrollWheel(with event: NSEvent) {
        guard
            let player,
            player.currentItem != nil
        else {
            return
        }

        if player.timeControlStatus == .playing, !shouldResumePlaybackAfterScrub {
            shouldResumePlaybackAfterScrub = true
            player.pause()
        }

        let dominantDelta = abs(event.scrollingDeltaX) >= abs(event.scrollingDeltaY)
            ? event.scrollingDeltaX
            : event.scrollingDeltaY
        guard abs(dominantDelta) > 0.000_01 else { return }

        // Trackpad tuning: sensitive for small moves, controlled for fast swipes.
        var deltaSeconds = Double(dominantDelta) * (event.hasPreciseScrollingDeltas ? 0.012 : 0.075)
        if !event.momentumPhase.isEmpty {
            deltaSeconds *= 0.22
        }

        let sign = deltaSeconds >= 0 ? 1.0 : -1.0
        let magnitude = abs(deltaSeconds)
        let dampedMagnitude = magnitude <= 0.10
            ? magnitude
            : (0.10 + (magnitude - 0.10) * 0.24)
        deltaSeconds = sign * min(1.2, dampedMagnitude)

        let currentSeconds = player.currentTime().seconds
        let safeCurrent = currentSeconds.isFinite ? currentSeconds : 0
        let durationSeconds = player.currentItem?.duration.seconds ?? 0
        let safeDuration = durationSeconds.isFinite ? durationSeconds : 0
        let targetSeconds = max(0, min(safeDuration, safeCurrent + deltaSeconds))
        let targetTime = CMTime(seconds: targetSeconds, preferredTimescale: 600)
        let tolerance = CMTime(seconds: 0.05, preferredTimescale: 600)
        let now = CACurrentMediaTime()
        let isNewScrubBurst = now - lastScrubInteractionTimestamp > 0.25
        lastScrubInteractionTimestamp = now
        if now - lastScrubSeekTimestamp < 0.01 {
            return
        }
        lastScrubSeekTimestamp = now

        scrubSeekGeneration &+= 1
        let seekGeneration = scrubSeekGeneration
        activeScrubTraceGeneration = seekGeneration
        pendingScrubTraceEndWorkItem?.cancel()
        pendingScrubTraceEndWorkItem = nil
        if isNewScrubBurst {
            debugModel?.logPlaybackDebugEventFromUI(
                "SEEK_BEGIN",
                source: "scroll_scrub",
                seekGeneration: seekGeneration,
                itemOverride: player.currentItem,
                currentSecondsOverride: targetSeconds,
                extraFields: [("deltaSeconds", String(format: "%.3f", deltaSeconds))]
            )
        }
        player.seek(to: targetTime, toleranceBefore: tolerance, toleranceAfter: tolerance) { [weak self] finished in
            DispatchQueue.main.async {
                guard let self, let player = self.player else { return }
                guard seekGeneration == self.scrubSeekGeneration else { return }
                let traceGeneration = self.activeScrubTraceGeneration ?? seekGeneration
                if !finished {
                    self.debugModel?.logPlaybackDebugEventFromUI(
                        "SEEK_END",
                        source: "scroll_scrub",
                        seekGeneration: traceGeneration,
                        itemOverride: player.currentItem,
                        currentSecondsOverride: player.currentTime().seconds,
                        extraFields: [("finished", "false")]
                    )
                    return
                }

                let workItem = DispatchWorkItem { [weak self] in
                    guard let self, let player = self.player else { return }
                    self.debugModel?.logPlaybackDebugEventFromUI(
                        "SEEK_END",
                        source: "scroll_scrub",
                        seekGeneration: traceGeneration,
                        itemOverride: player.currentItem,
                        currentSecondsOverride: player.currentTime().seconds,
                        extraFields: [("finished", "true")]
                    )
                    if self.shouldResumePlaybackAfterScrub {
                        self.shouldResumePlaybackAfterScrub = false
                        self.debugModel?.logPlaybackDebugEventFromUI(
                            "PLAY_REQUESTED",
                            source: "scroll_scrub_resume",
                            seekGeneration: traceGeneration,
                            itemOverride: player.currentItem
                        )
                        player.play()
                    }
                    self.activeScrubTraceGeneration = nil
                    self.pendingScrubTraceEndWorkItem = nil
                }
                self.pendingScrubTraceEndWorkItem = workItem
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.18, execute: workItem)
            }
        }
    }
}
