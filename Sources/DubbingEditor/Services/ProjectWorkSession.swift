import Foundation

@MainActor
final class ProjectWorkSession: ObservableObject {
    @Published private(set) var shouldShowDuration = false

    var onTrackedWorkDidAccumulate: (() -> Void)?

    private var tracker = ProjectWorkTracker()
    private var timer: DispatchSourceTimer?
    private var hasTrackedContext = false
    private var lastKnownWindowActive = false
    private let timerIntervalSeconds: TimeInterval

    init(timerIntervalSeconds: TimeInterval = 1) {
        self.timerIntervalSeconds = timerIntervalSeconds
    }

    deinit {
        timer?.setEventHandler {}
        timer?.cancel()
    }

    func currentTrackedSeconds(at date: Date = Date()) -> Double {
        tracker.currentTrackedSeconds(at: date)
    }

    func durationLabel(at date: Date = Date()) -> String {
        Self.formattedWorkedDuration(currentTrackedSeconds(at: date))
    }

    func noteActivity(at date: Date = Date()) {
        guard hasTrackedContext else { return }
        let didPause = tracker.noteActivity(at: date)
        handleStateTransition(at: date, didPause: didPause)
    }

    func setWindowActive(_ isActive: Bool, at date: Date = Date()) {
        lastKnownWindowActive = isActive
        let didPause = tracker.setWindowActive(isActive, at: date)
        handleStateTransition(at: date, didPause: didPause)
    }

    func restorePersistedSeconds(_ seconds: Double?, hasTrackedContext: Bool, at date: Date = Date()) {
        tracker.restorePersistedSeconds(seconds ?? 0)
        self.hasTrackedContext = hasTrackedContext
        if hasTrackedContext {
            _ = tracker.setWindowActive(lastKnownWindowActive, at: date)
        }
        updatePresentationState(at: date)
        reconcileTimer(at: date)
    }

    func resetPersistedSeconds(hasTrackedContext: Bool, at date: Date = Date()) {
        restorePersistedSeconds(0, hasTrackedContext: hasTrackedContext, at: date)
    }

    func setHasTrackedContext(_ hasTrackedContext: Bool, at date: Date = Date()) {
        guard self.hasTrackedContext != hasTrackedContext else {
            updatePresentationState(at: date)
            reconcileTimer(at: date)
            return
        }

        self.hasTrackedContext = hasTrackedContext
        let didPause: Bool
        if hasTrackedContext {
            didPause = tracker.setWindowActive(lastKnownWindowActive, at: date)
        } else {
            didPause = tracker.forcePause(at: date)
        }
        handleStateTransition(at: date, didPause: didPause)
    }

    private func handleStateTransition(at date: Date, didPause: Bool) {
        updatePresentationState(at: date)
        reconcileTimer(at: date)
        if didPause {
            onTrackedWorkDidAccumulate?()
        }
    }

    private func updatePresentationState(at date: Date) {
        let nextValue = hasTrackedContext || currentTrackedSeconds(at: date) > 0
        guard shouldShowDuration != nextValue else { return }
        shouldShowDuration = nextValue
    }

    private func reconcileTimer(at date: Date) {
        let shouldRun = hasTrackedContext && tracker.isActivelyTracking(at: date)
        if shouldRun {
            guard timer == nil else { return }
            let timer = DispatchSource.makeTimerSource(queue: .main)
            timer.schedule(deadline: .now() + timerIntervalSeconds, repeating: timerIntervalSeconds)
            timer.setEventHandler { [weak self] in
                self?.handleTimerTick()
            }
            self.timer = timer
            timer.resume()
            return
        }

        guard let timer else { return }
        timer.setEventHandler {}
        timer.cancel()
        self.timer = nil
    }

    private func handleTimerTick() {
        let now = Date()
        let didPause = tracker.sync(at: now)
        handleStateTransition(at: now, didPause: didPause)
    }

    private static func formattedWorkedDuration(_ seconds: TimeInterval) -> String {
        let clampedSeconds = max(0, Int(seconds.rounded(.down)))
        let hours = clampedSeconds / 3_600
        let minutes = (clampedSeconds % 3_600) / 60
        let remainingSeconds = clampedSeconds % 60
        return String(format: "%02d:%02d:%02d", hours, minutes, remainingSeconds)
    }
}
