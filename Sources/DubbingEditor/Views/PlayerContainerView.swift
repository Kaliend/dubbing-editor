import AVFoundation
import AppKit
import SwiftUI

struct PlayerContainerView: NSViewRepresentable, Equatable {
    let player: AVPlayer

    static func == (lhs: PlayerContainerView, rhs: PlayerContainerView) -> Bool {
        lhs.player === rhs.player
    }

    func makeNSView(context: Context) -> ScrubbablePlayerLayerView {
        let view = ScrubbablePlayerLayerView()
        view.player = player
        return view
    }

    func updateNSView(_ nsView: ScrubbablePlayerLayerView, context: Context) {
        if nsView.player !== player {
            nsView.player = player
        }
    }
}

final class ScrubbablePlayerLayerView: NSView {
    private let playerLayer = AVPlayerLayer()
    private var shouldResumePlaybackAfterScrub = false
    private var lastScrubSeekTimestamp: TimeInterval = 0
    private var lastScrubInteractionTimestamp: TimeInterval = 0
    private var scrubSeekGeneration: UInt64 = 0

    var player: AVPlayer? {
        didSet {
            playerLayer.player = player
            shouldResumePlaybackAfterScrub = false
            lastScrubSeekTimestamp = 0
            lastScrubInteractionTimestamp = 0
            scrubSeekGeneration = 0
        }
    }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        commonInit()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        commonInit()
    }

    private func commonInit() {
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
        lastScrubInteractionTimestamp = now
        if now - lastScrubSeekTimestamp < 0.01 {
            return
        }
        lastScrubSeekTimestamp = now

        scrubSeekGeneration &+= 1
        let seekGeneration = scrubSeekGeneration
        player.seek(to: targetTime, toleranceBefore: tolerance, toleranceAfter: tolerance) { [weak self] finished in
            DispatchQueue.main.async {
                guard let self, self.player != nil else { return }
                guard seekGeneration == self.scrubSeekGeneration else { return }
                if !finished {
                    return
                }

                DispatchQueue.main.asyncAfter(deadline: .now() + 0.18) { [weak self] in
                    guard let self, let player = self.player else { return }
                    guard seekGeneration == self.scrubSeekGeneration else { return }
                    if self.shouldResumePlaybackAfterScrub {
                        self.shouldResumePlaybackAfterScrub = false
                        player.play()
                    }
                }
            }
        }
    }
}
