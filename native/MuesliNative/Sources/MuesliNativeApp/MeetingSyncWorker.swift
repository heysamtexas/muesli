import Foundation
import MuesliCore
import Network
import os

/// Drains the meeting_sync_queue table. One in-flight drain at a time.
/// Retries are governed by an exponential backoff schedule and capped at 12
/// attempts before an entry is marked `failed`. Network reachability changes
/// (`NWPathMonitor`) and explicit `kick()` calls trigger fresh drains.
@MainActor
final class MeetingSyncWorker {
    static let backoffSchedule: [TimeInterval] = [1, 5, 30, 300, 1800, 3600]
    static let maxAttempts = 12

    private static let logger = Logger(subsystem: "com.muesli.native", category: "MeetingSyncWorker")

    private let store: DictationStore
    private let client: MeetingSyncClientProtocol
    private let configProvider: @Sendable () -> AppConfig
    private let now: @Sendable () -> Date
    private let isoFormatter: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()

    private var pathMonitor: NWPathMonitor?
    private let pathMonitorQueue = DispatchQueue(label: "com.muesli.native.meeting-sync-path")
    private var draining = false
    private var pendingDrain = false
    private var kickWorkItem: DispatchWorkItem?
    private(set) var hasNetwork = true
    private var onStatsChanged: (@MainActor () -> Void)?

    init(
        store: DictationStore,
        client: MeetingSyncClientProtocol,
        configProvider: @escaping @Sendable () -> AppConfig,
        now: @escaping @Sendable () -> Date = Date.init
    ) {
        self.store = store
        self.client = client
        self.configProvider = configProvider
        self.now = now
    }

    // MARK: - Lifecycle

    func setStatsChangedCallback(_ callback: @escaping @MainActor () -> Void) {
        self.onStatsChanged = callback
    }

    func start() {
        let monitor = NWPathMonitor()
        monitor.pathUpdateHandler = { [weak self] path in
            let satisfied = path.status == .satisfied
            Task { @MainActor [weak self] in
                guard let self else { return }
                let wasOffline = !self.hasNetwork
                self.hasNetwork = satisfied
                if satisfied && wasOffline {
                    self.kick()
                }
            }
        }
        monitor.start(queue: pathMonitorQueue)
        self.pathMonitor = monitor
        kick()
    }

    func stop() {
        pathMonitor?.cancel()
        pathMonitor = nil
        kickWorkItem?.cancel()
        kickWorkItem = nil
    }

    // MARK: - Public API

    func kick() {
        guard configProvider().meetingSyncEnabled else { return }
        if draining {
            pendingDrain = true
            return
        }
        draining = true
        Task { @MainActor [weak self] in
            guard let self else { return }
            await self.drainOnce()
            self.draining = false
            if self.pendingDrain {
                self.pendingDrain = false
                self.kick()
            }
        }
    }

    /// Synchronous drain helper — used by tests so they can `await` deterministic
    /// results without polling. Bypasses the in-flight guard but otherwise behaves
    /// identically to `kick()`'s body.
    func drainNowForTesting() async {
        guard configProvider().meetingSyncEnabled else { return }
        await drainOnce()
    }

    // MARK: - Drain loop

    private func drainOnce() async {
        let entries: [MeetingSyncQueueEntry]
        do {
            entries = try store.meetingsAwaitingSync()
        } catch {
            Self.logger.error("read sync queue failed: \(error.localizedDescription, privacy: .public)")
            return
        }
        guard !entries.isEmpty else { return }
        guard configProvider().meetingSyncEnabled else { return }

        var earliestRetryDelay: TimeInterval?
        for entry in entries {
            if let delay = waitForNextAttempt(entry: entry) {
                earliestRetryDelay = min(earliestRetryDelay ?? delay, delay)
                continue
            }
            let attemptsAfterStart = entry.attempts + 1
            do {
                try store.markMeetingSyncStarting(meetingID: entry.meetingID, at: now())
                _ = try await client.sync(meetingID: entry.meetingID)
                try store.markMeetingSyncDone(meetingID: entry.meetingID, at: now())
                Self.logger.info("synced meeting \(entry.meetingID)")
            } catch let syncError as MeetingSyncError {
                let terminal = syncError.isTerminal || attemptsAfterStart >= Self.maxAttempts
                recordFailure(meetingID: entry.meetingID, error: syncError, terminal: terminal)
                if !terminal {
                    let delay = backoff(attempts: attemptsAfterStart)
                    earliestRetryDelay = min(earliestRetryDelay ?? delay, delay)
                }
            } catch {
                let terminal = attemptsAfterStart >= Self.maxAttempts
                recordFailure(meetingID: entry.meetingID, errorMessage: error.localizedDescription, terminal: terminal)
                if !terminal {
                    let delay = backoff(attempts: attemptsAfterStart)
                    earliestRetryDelay = min(earliestRetryDelay ?? delay, delay)
                }
            }
            onStatsChanged?()
        }
        if let earliestRetryDelay {
            scheduleKick(after: earliestRetryDelay)
        }
        onStatsChanged?()
    }

    private func waitForNextAttempt(entry: MeetingSyncQueueEntry) -> TimeInterval? {
        guard entry.attempts > 0,
              let raw = entry.lastAttemptAt,
              let lastAttemptDate = parseISO(raw) else {
            return nil
        }
        let scheduled = lastAttemptDate.addingTimeInterval(backoff(attempts: entry.attempts))
        let delay = scheduled.timeIntervalSince(now())
        return delay > 0 ? delay : nil
    }

    private func recordFailure(meetingID: Int64, error: MeetingSyncError, terminal: Bool) {
        recordFailure(meetingID: meetingID, errorMessage: error.errorDescription ?? "sync failed", terminal: terminal)
    }

    private func recordFailure(meetingID: Int64, errorMessage: String, terminal: Bool) {
        do {
            try store.recordMeetingSyncFailure(meetingID: meetingID, error: errorMessage, terminal: terminal)
        } catch {
            Self.logger.error("record failure persistence error: \(error.localizedDescription, privacy: .public)")
        }
        let level: OSLogType = terminal ? .error : .info
        Self.logger.log(level: level, "meeting \(meetingID) sync failure (terminal=\(terminal)): \(errorMessage, privacy: .public)")
    }

    private func scheduleKick(after delay: TimeInterval) {
        kickWorkItem?.cancel()
        let bounded = max(delay, 0.5)
        let item = DispatchWorkItem { [weak self] in
            Task { @MainActor [weak self] in
                self?.kick()
            }
        }
        kickWorkItem = item
        DispatchQueue.main.asyncAfter(deadline: .now() + bounded, execute: item)
    }

    // MARK: - Helpers (testing seams are static)

    nonisolated static func backoff(attempts: Int) -> TimeInterval {
        guard !backoffSchedule.isEmpty else { return 60 }
        let safeAttempts = max(attempts, 1)
        let index = min(safeAttempts - 1, backoffSchedule.count - 1)
        return backoffSchedule[index]
    }

    private func backoff(attempts: Int) -> TimeInterval {
        Self.backoff(attempts: attempts)
    }

    private func parseISO(_ s: String) -> Date? {
        if let date = isoFormatter.date(from: s) { return date }
        let plain = ISO8601DateFormatter()
        plain.formatOptions = [.withInternetDateTime]
        return plain.date(from: s)
    }
}
