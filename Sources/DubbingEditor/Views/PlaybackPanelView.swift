import AVFoundation
import AppKit
import Foundation
import SwiftUI

@MainActor
struct PlaybackPanelView: View {
    @ObservedObject var model: EditorViewModel
    @State private var playheadProgress: Double = 0
    @State private var timeObserverToken: Any?
    @State private var isWaveformScrubbing = false
    @State private var waveformScrubGeneration: UInt64 = 0
    @State private var isEditingText = false
    @State private var isWindowFullscreen = false
    @AppStorage("shortcut_play_pause") private var shortcutPlayPause = "space"
    @AppStorage("shortcut_seek_backward") private var shortcutSeekBackward = "option+left"
    @AppStorage("shortcut_seek_forward") private var shortcutSeekForward = "option+right"

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Group {
                if model.videoURL == nil {
                    RoundedRectangle(cornerRadius: 12)
                        .fill(Color.black.opacity(0.85))
                        .overlay {
                            VStack(spacing: 8) {
                                Text("Neni nactene video")
                                    .foregroundStyle(.white)
                                Text("Pouzij tlacitko Import Video")
                                    .font(.caption)
                                    .foregroundStyle(.white.opacity(0.7))
                            }
                        }
                } else {
                    PlayerContainerView(player: model.player, model: model)
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            HStack(spacing: 8) {
                Button {
                    guard model.player.currentItem != nil else { return }
                    model.logPlaybackDebugEvent("PLAY_REQUESTED", source: "direct_play_button")
                    model.player.play()
                } label: {
                    Label {
                        Text("Play")
                    } icon: {
                        Image(systemName: "play.fill")
                    }
                }
                .buttonStyle(.bordered)
                .help(shortcutHint("Play/Pause", shortcutPlayPause))

                Button {
                    model.logPlaybackDebugEvent("PAUSE_REQUESTED", source: "direct_pause_button")
                    model.player.pause()
                } label: {
                    Label {
                        Text("Pause")
                    } icon: {
                        Image(systemName: "pause.fill")
                    }
                }
                .buttonStyle(.bordered)
                .help(shortcutHint("Play/Pause", shortcutPlayPause))

                Button {
                    model.seekBackwardStep()
                } label: {
                    Label {
                        Text("-\(seekStepLabel())s")
                    } icon: {
                        Image(systemName: "gobackward")
                    }
                }
                .buttonStyle(.bordered)
                .help(shortcutHint("Posun zpet", shortcutSeekBackward))

                Button {
                    model.seekForwardStep()
                } label: {
                    Label {
                        Text("+\(seekStepLabel())s")
                    } icon: {
                        Image(systemName: "goforward")
                    }
                }
                .buttonStyle(.bordered)
                .help(shortcutHint("Posun vpred", shortcutSeekForward))

                Spacer()

                Text(currentPlaybackTimeText())
                    .font(.system(.body, design: .monospaced))
                    .foregroundStyle(.secondary)
            }

            audioControlsRow

            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text("Audio Waveform")
                        .font(.headline)
                    if model.isBuildingWaveform {
                        ProgressView()
                            .controlSize(.small)
                    }
                    if model.isLightModeEnabled {
                        Text("low-power")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                if model.isDevModeEnabled {
                    devMetricsPanel
                }

                waveformSection
            }
        }
        .padding(14)
        .onAppear {
            updateFullscreenStateFromKeyWindow()
            installTimeObserver()
        }
        .onDisappear {
            removeTimeObserver()
        }
        .onChange(of: model.isLightModeEnabled) { _ in
            resetTimeObserver()
        }
        .onChange(of: model.editingLineID) { editingLineID in
            let nextIsEditing = editingLineID != nil
            if nextIsEditing != isEditingText {
                isEditingText = nextIsEditing
                resetTimeObserver()
            }
        }
        .onChange(of: model.isPlaybackActive) { _ in
            resetTimeObserver()
        }
        .onChange(of: isWindowFullscreen) { _ in
            resetTimeObserver()
        }
        .onChange(of: model.videoURL) { _ in
            if model.player.currentItem == nil {
                playheadProgress = 0
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: NSWindow.didEnterFullScreenNotification)) { _ in
            if !isWindowFullscreen {
                isWindowFullscreen = true
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: NSWindow.didExitFullScreenNotification)) { _ in
            if isWindowFullscreen {
                isWindowFullscreen = false
            }
        }
    }

    private func installTimeObserver() {
        guard timeObserverToken == nil else { return }

        let interval = CMTime(
            seconds: playbackRefreshIntervalSeconds(),
            preferredTimescale: 600
        )

        timeObserverToken = model.player.addPeriodicTimeObserver(
            forInterval: interval,
            queue: .main
        ) { time in
            MainActor.assumeIsolated {
                let seconds = max(0, time.seconds)
                guard seconds.isFinite else {
                    playheadProgress = 0
                    return
                }

                guard
                    let duration = model.player.currentItem?.duration.seconds,
                    duration.isFinite,
                    duration > 0
                else {
                    playheadProgress = 0
                    return
                }

                if isWaveformScrubbing {
                    return
                }

                let nextProgress = min(1, seconds / duration)
                let minDelta: Double
                if isWindowFullscreen && model.isPlaybackActive {
                    minDelta = isEditingText ? 0.008 : 0.0045
                } else if isWindowFullscreen {
                    minDelta = isEditingText ? 0.005 : 0.002
                } else {
                    minDelta = isEditingText ? 0.0035 : 0.0008
                }
                if abs(nextProgress - playheadProgress) > minDelta || nextProgress == 0 || nextProgress == 1 {
                    playheadProgress = nextProgress
                }
                model.handlePlaybackTick(currentSeconds: seconds)
            }
        }
    }

    private func removeTimeObserver() {
        if let token = timeObserverToken {
            model.player.removeTimeObserver(token)
            timeObserverToken = nil
        }
    }

    private func resetTimeObserver() {
        removeTimeObserver()
        installTimeObserver()
    }

    private func playbackRefreshIntervalSeconds() -> Double {
        if isWindowFullscreen {
            if model.isPlaybackActive {
                if isEditingText {
                    return model.isLightModeEnabled ? (1.0 / 3.0) : (1.0 / 5.0)
                }
                return model.isLightModeEnabled ? (1.0 / 4.0) : (1.0 / 8.0)
            }
            if isEditingText {
                return model.isLightModeEnabled ? (1.0 / 4.0) : (1.0 / 6.0)
            }
            return model.isLightModeEnabled ? (1.0 / 5.0) : (1.0 / 12.0)
        }

        if isEditingText {
            return model.isLightModeEnabled ? (1.0 / 6.0) : (1.0 / 12.0)
        }
        return model.isLightModeEnabled ? (1.0 / 10.0) : (1.0 / 24.0)
    }

    private func updateFullscreenStateFromKeyWindow() {
        let window = NSApp.keyWindow ?? NSApp.mainWindow
        isWindowFullscreen = window?.styleMask.contains(.fullScreen) ?? false
    }

    private func seekStepLabel() -> String {
        let value = model.playbackSeekStepSeconds
        if abs(value.rounded() - value) < 0.0001 {
            return String(Int(value.rounded()))
        }
        let formatted = String(format: "%.2f", value)
        let withoutTrailingZeros = formatted.replacingOccurrences(
            of: #"0+$"#,
            with: "",
            options: .regularExpression
        )
        return withoutTrailingZeros.replacingOccurrences(
            of: #"\.$"#,
            with: "",
            options: .regularExpression
        )
    }

    private func audioChannelStateText() -> String {
        if model.videoURL == nil {
            return "Audio: -"
        }
        if model.detectedAudioChannelCount <= 0 {
            return "Audio: ?"
        }
        if model.detectedAudioChannelCount == 1 {
            return "Audio: mono"
        }
        return "Audio: \(model.detectedAudioChannelCount)ch"
    }

    private var audioControlsRow: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 10) {
                Text("Kanaly")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)

                Button {
                    model.setLeftChannelMuted(!model.isLeftChannelMuted)
                } label: {
                    Text(model.isLeftChannelMuted ? "L: MUTE" : "L")
                        .font(.system(.caption, design: .monospaced).weight(.semibold))
                        .frame(minWidth: 58)
                }
                .buttonStyle(.borderedProminent)
                .tint(model.isLeftChannelMuted ? .red : .gray)
                .disabled(!model.canControlStereoChannels || model.isPreparingChannelDerivedAudio)
                .help("Zamuti levy kanal puvodni video audio stopy.")

                Button {
                    model.setRightChannelMuted(!model.isRightChannelMuted)
                } label: {
                    Text(model.isRightChannelMuted ? "R: MUTE" : "R")
                        .font(.system(.caption, design: .monospaced).weight(.semibold))
                        .frame(minWidth: 58)
                }
                .buttonStyle(.borderedProminent)
                .tint(model.isRightChannelMuted ? .red : .gray)
                .disabled(!model.canControlStereoChannels || model.isPreparingChannelDerivedAudio)
                .help("Zamuti pravy kanal puvodni video audio stopy.")

                Text(audioChannelStateText())
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            if model.isPreparingChannelDerivedAudio {
                Text("Pripravuji kanalovy stem pro video audio...")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            HStack(spacing: 10) {
                Text("Stopy")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)

                Button {
                    model.setVideoAudioMuted(!model.isVideoAudioMuted)
                } label: {
                    Text(model.isVideoAudioMuted ? "Video Audio: MUTE" : "Video Audio")
                        .font(.caption.weight(.semibold))
                }
                .buttonStyle(.borderedProminent)
                .tint(model.isVideoAudioMuted ? .red : .gray)
                .disabled(!model.hasVideoAudioTrack)
                .help("Zapina nebo vypina celou audio stopu z videa.")

                Button {
                    model.setExternalAudioMuted(!model.isExternalAudioMuted)
                } label: {
                    Text(model.isExternalAudioMuted ? "External Audio: MUTE" : "External Audio")
                        .font(.caption.weight(.semibold))
                }
                .buttonStyle(.borderedProminent)
                .tint(model.isExternalAudioMuted ? .red : .gray)
                .disabled(!model.hasExternalAudioTrack)
                .help("Zapina nebo vypina importovanou externi audio stopu.")

                Text(externalAudioStateText())
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func externalAudioStateText() -> String {
        guard model.videoURL != nil else {
            return "Externi audio: -"
        }
        guard model.hasExternalAudioTrack else {
            return "Externi audio: nenacteno"
        }
        return "Externi audio: \(model.externalAudioDisplayName ?? "nacteno")"
    }

    private func waveformEmptyStateText() -> String {
        if model.isBuildingWaveform {
            return "Nacitam waveform..."
        }
        if
            model.canControlStereoChannels,
            model.isLeftChannelMuted,
            model.isRightChannelMuted,
            model.externalWaveform.isEmpty
        {
            return "Oba kanaly jsou zamutovane"
        }
        return "Waveform se zobrazi po nacteni videa"
    }

    private func currentPlaybackTimeText() -> String {
        model.currentPlaybackTimecodeString(hideFrames: model.hideTimecodeFrames)
            ?? (model.hideTimecodeFrames ? "00:00:00" : "00:00:00:00")
    }

    @ViewBuilder
    private var waveformSection: some View {
        let showExternal = !model.externalWaveform.isEmpty

        if model.canControlStereoChannels {
            let showLeft = !model.isLeftChannelMuted && !model.waveformLeft.isEmpty
            let showRight = !model.isRightChannelMuted && !model.waveformRight.isEmpty

            if !showLeft && !showRight && !showExternal {
                RoundedRectangle(cornerRadius: 8)
                    .fill(Color(nsColor: .windowBackgroundColor).opacity(0.35))
                    .frame(height: 74)
                    .overlay {
                        Text(waveformEmptyStateText())
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
            } else {
                VStack(spacing: 6) {
                    if showLeft {
                        channelWaveformRow(label: "L", samples: model.waveformLeft)
                    }
                    if showRight {
                        channelWaveformRow(label: "R", samples: model.waveformRight)
                    }
                    if showExternal {
                        channelWaveformRow(label: "EXT", samples: model.externalWaveform)
                    }
                }
                .overlay(alignment: .topLeading) {
                    if let label = selectedLineWaveformLabel() {
                        Text(label)
                            .font(.caption2.monospaced())
                            .padding(.horizontal, 6)
                            .padding(.vertical, 3)
                            .background(Color.black.opacity(0.55), in: Capsule())
                            .foregroundStyle(.white)
                            .padding(6)
                    }
                }
            }
        } else {
            if model.waveform.isEmpty && !showExternal {
                RoundedRectangle(cornerRadius: 8)
                    .fill(Color(nsColor: .windowBackgroundColor).opacity(0.35))
                    .frame(height: 74)
                    .overlay {
                        Text(waveformEmptyStateText())
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
            } else {
                VStack(spacing: 6) {
                    if !model.waveform.isEmpty {
                        channelWaveformRow(label: showExternal ? "VID" : nil, samples: model.waveform)
                    }
                    if showExternal {
                        channelWaveformRow(label: "EXT", samples: model.externalWaveform)
                    }
                }
                .overlay(alignment: .topLeading) {
                    if let label = selectedLineWaveformLabel() {
                        Text(label)
                            .font(.caption2.monospaced())
                            .padding(.horizontal, 6)
                            .padding(.vertical, 3)
                            .background(Color.black.opacity(0.55), in: Capsule())
                            .foregroundStyle(.white)
                            .padding(6)
                    }
                }
            }
        }
    }

    private func channelWaveformRow(label: String?, samples: [Float]) -> some View {
        HStack(spacing: 8) {
            if let label {
                Text(label)
                    .font(.caption.weight(.semibold).monospaced())
                    .foregroundStyle(.secondary)
                    .frame(width: 28, alignment: .leading)
            }

            WaveformView(
                samples: samples,
                playheadProgress: playheadProgress,
                selectedRangeProgress: selectedLineWaveformRangeProgress(),
                isHighLoadMode: isWindowFullscreen && model.isPlaybackActive,
                onScrubBegan: beginWaveformScrub,
                onScrubChanged: updateWaveformScrub(progress:),
                onScrubEnded: endWaveformScrub(progress:)
            )
            .frame(height: 74)
            .allowsHitTesting(model.player.currentItem != nil)
        }
    }

    private func playbackDurationSeconds() -> Double? {
        guard
            let duration = model.player.currentItem?.duration.seconds,
            duration.isFinite,
            duration > 0
        else {
            return nil
        }
        return duration
    }

    private func selectedLineTimeRangeSeconds() -> ClosedRange<Double>? {
        guard
            let selectedID = model.selectedLineID,
            let line = model.lines.first(where: { $0.id == selectedID }),
            let startTimeline = TimecodeService.seconds(from: line.startTimecode, fps: model.fps)
        else {
            return nil
        }

        let parsedEndTimeline = TimecodeService.seconds(from: line.endTimecode, fps: model.fps)
        let endTimeline = max(startTimeline + 0.05, parsedEndTimeline ?? (startTimeline + 5))
        let start = model.playbackSeconds(fromTimelineSeconds: startTimeline)
        let end = max(start + 0.05, model.playbackSeconds(fromTimelineSeconds: endTimeline))
        return start...end
    }

    private func selectedLineWaveformRangeProgress() -> ClosedRange<Double>? {
        guard
            let secondsRange = selectedLineTimeRangeSeconds(),
            let duration = playbackDurationSeconds()
        else {
            return nil
        }

        let lower = max(0, min(1, secondsRange.lowerBound / duration))
        let upper = max(lower, min(1, secondsRange.upperBound / duration))
        return lower...upper
    }

    private func selectedLineWaveformLabel() -> String? {
        guard let secondsRange = selectedLineTimeRangeSeconds() else {
            return nil
        }
        let startTimeline = model.timelineSeconds(fromPlaybackSeconds: secondsRange.lowerBound)
        let endTimeline = model.timelineSeconds(fromPlaybackSeconds: secondsRange.upperBound)
        let startText = model.hideTimecodeFrames
            ? TimecodeService.timecodeWithoutFrames(from: startTimeline)
            : TimecodeService.timecode(from: startTimeline, fps: model.fps)
        let endText = model.hideTimecodeFrames
            ? TimecodeService.timecodeWithoutFrames(from: endTimeline)
            : TimecodeService.timecode(from: endTimeline, fps: model.fps)
        return "\(startText) - \(endText)"
    }

    private func beginWaveformScrub() {
        guard !isWaveformScrubbing else { return }
        isWaveformScrubbing = true
    }

    private func updateWaveformScrub(progress: Double) {
        seekToPlaybackProgress(progress, precise: false)
    }

    private func endWaveformScrub(progress: Double) {
        seekToPlaybackProgress(progress, precise: true)
        isWaveformScrubbing = false
    }

    private func seekToPlaybackProgress(_ progress: Double, precise: Bool) {
        guard let duration = playbackDurationSeconds() else { return }
        let clamped = max(0, min(1, progress))
        playheadProgress = clamped
        let targetSeconds = duration * clamped
        let target = CMTime(seconds: targetSeconds, preferredTimescale: 600)
        if precise {
            waveformScrubGeneration &+= 1
            let seekGeneration = waveformScrubGeneration
            model.logPlaybackDebugEvent(
                "SEEK_BEGIN",
                source: "waveform_scrub",
                seekGeneration: seekGeneration,
                currentSecondsOverride: targetSeconds,
                extraFields: [("precise", "true")]
            )
            model.player.seek(to: target, toleranceBefore: .zero, toleranceAfter: .zero) { finished in
                Task { @MainActor in
                    model.logPlaybackDebugEvent(
                        "SEEK_END",
                        source: "waveform_scrub",
                        seekGeneration: seekGeneration,
                        currentSecondsOverride: model.player.currentTime().seconds,
                        extraFields: [
                            ("finished", finished ? "true" : "false"),
                            ("precise", "true")
                        ]
                    )
                }
            }
        } else {
            let tolerance = CMTime(seconds: 0.05, preferredTimescale: 600)
            model.player.seek(to: target, toleranceBefore: tolerance, toleranceAfter: tolerance)
        }
    }

    private var devMetricsPanel: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("DEV MODE")
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.orange)
            Text("Video load: \(formatDuration(model.lastVideoLoadDuration))")
                .font(.caption2.monospaced())
                .foregroundStyle(.secondary)
            Text("Waveform build: \(formatDuration(model.lastWaveformBuildDuration))")
                .font(.caption2.monospaced())
                .foregroundStyle(.secondary)
            Text("Waveform source V/EXT: \(model.waveformSourceLabel() ?? "-") / \(model.externalWaveformSourceLabel() ?? "-")")
                .font(.caption2.monospaced())
                .foregroundStyle(.secondary)
            Text("Samples V(M/L/R)/EXT: \(model.waveform.count)/\(model.waveformLeft.count)/\(model.waveformRight.count)/\(model.externalWaveform.count)")
                .font(.caption2.monospaced())
                .foregroundStyle(.secondary)
            Text("Cache V/EXT: \(model.waveformCacheExists ? "yes" : "no") \(formatBytes(model.waveformCacheSizeBytes)) / \(model.externalWaveformCacheExists ? "yes" : "no") \(formatBytes(model.externalWaveformCacheSizeBytes))")
                .font(.caption2.monospaced())
                .foregroundStyle(.secondary)
            Text("Click -> Focus: \(formatDurationMilliseconds(model.devInteractionMetrics.clickToFocusMilliseconds)) [\(model.devInteractionMetrics.clickToFocusLabel)]")
                .font(.caption2.monospaced())
                .foregroundStyle(.secondary)
            Text("Commit -> LinesChanged: \(formatDurationMilliseconds(model.devInteractionMetrics.commitToLinesChangedMilliseconds)) [\(model.devInteractionMetrics.commitToLinesChangedLabel)]")
                .font(.caption2.monospaced())
                .foregroundStyle(.secondary)
            Text("LinesChanged -> CacheDone: \(formatDurationMilliseconds(model.devInteractionMetrics.linesChangedToCacheDoneMilliseconds)) [\(model.devInteractionMetrics.linesChangedToCacheDoneLabel)]")
                .font(.caption2.monospaced())
                .foregroundStyle(.secondary)
        }
        .padding(8)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(Color(nsColor: .controlBackgroundColor))
        )
    }

    private func formatDuration(_ value: TimeInterval?) -> String {
        guard let value else { return "-" }
        if value < 1 {
            return String(format: "%.0f ms", value * 1000)
        }
        return String(format: "%.2f s", value)
    }

    private func formatDurationMilliseconds(_ value: Double?) -> String {
        guard let value else { return "-" }
        return String(format: "%.0f ms", value)
    }

    private func formatBytes(_ value: UInt64?) -> String {
        guard let value else { return "-" }
        let formatter = ByteCountFormatter()
        formatter.allowedUnits = [.useKB, .useMB]
        formatter.countStyle = .file
        return formatter.string(fromByteCount: Int64(value))
    }
}
