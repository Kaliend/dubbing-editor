import Foundation

struct ProjectWorkTracker: Equatable, Sendable {
    private(set) var accumulatedSeconds: TimeInterval
    private(set) var isWindowActive: Bool
    private(set) var lastActivityAt: Date?
    private(set) var activeSessionStartedAt: Date?
    let activityGracePeriodSeconds: TimeInterval

    init(
        accumulatedSeconds: TimeInterval = 0,
        activityGracePeriodSeconds: TimeInterval = 30
    ) {
        self.accumulatedSeconds = max(0, accumulatedSeconds)
        self.isWindowActive = false
        self.lastActivityAt = nil
        self.activeSessionStartedAt = nil
        self.activityGracePeriodSeconds = activityGracePeriodSeconds
    }

    func currentTrackedSeconds(at now: Date) -> TimeInterval {
        guard let activeSessionStartedAt else {
            return accumulatedSeconds
        }

        let clampedEnd = min(now, activeTrackingDeadline ?? now)
        return accumulatedSeconds + max(0, clampedEnd.timeIntervalSince(activeSessionStartedAt))
    }

    func isActivelyTracking(at now: Date) -> Bool {
        guard isWindowActive, let deadline = activeTrackingDeadline else {
            return false
        }
        return now <= deadline
    }

    mutating func restorePersistedSeconds(_ seconds: TimeInterval) {
        accumulatedSeconds = max(0, seconds)
        isWindowActive = false
        lastActivityAt = nil
        activeSessionStartedAt = nil
    }

    @discardableResult
    mutating func noteActivity(at now: Date) -> Bool {
        lastActivityAt = now
        return refresh(at: now).didPause
    }

    @discardableResult
    mutating func setWindowActive(_ isActive: Bool, at now: Date) -> Bool {
        isWindowActive = isActive
        return refresh(at: now).didPause
    }

    @discardableResult
    mutating func sync(at now: Date) -> Bool {
        refresh(at: now).didPause
    }

    @discardableResult
    mutating func forcePause(at now: Date) -> Bool {
        guard let activeSessionStartedAt else {
            return false
        }

        let clampedEnd = min(now, activeTrackingDeadline ?? now)
        accumulatedSeconds += max(0, clampedEnd.timeIntervalSince(activeSessionStartedAt))
        self.activeSessionStartedAt = nil
        return true
    }

    private var activeTrackingDeadline: Date? {
        lastActivityAt?.addingTimeInterval(activityGracePeriodSeconds)
    }

    private mutating func refresh(at now: Date) -> Transition {
        if isActivelyTracking(at: now) {
            if activeSessionStartedAt == nil {
                activeSessionStartedAt = now
                return Transition(didPause: false)
            }
            return Transition(didPause: false)
        }

        guard let activeSessionStartedAt else {
            return Transition(didPause: false)
        }

        let clampedEnd = min(now, activeTrackingDeadline ?? now)
        accumulatedSeconds += max(0, clampedEnd.timeIntervalSince(activeSessionStartedAt))
        self.activeSessionStartedAt = nil
        return Transition(didPause: true)
    }
}

private struct Transition {
    let didPause: Bool
}
