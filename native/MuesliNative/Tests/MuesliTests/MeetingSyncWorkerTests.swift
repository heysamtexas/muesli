import Foundation
import Testing
import MuesliCore
@testable import MuesliNativeApp

@Suite("MeetingSyncWorker", .serialized)
struct MeetingSyncWorkerTests {

    private func makeStore() throws -> DictationStore {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("muesli-sync-worker-\(UUID().uuidString).db")
        let store = DictationStore(databaseURL: url)
        try store.migrateIfNeeded()
        return store
    }

    private func enqueueMeeting(_ store: DictationStore) throws -> Int64 {
        let id = try store.insertMeeting(
            title: "Sync target",
            calendarEventID: nil,
            startTime: Date(),
            endTime: Date().addingTimeInterval(60),
            rawTranscript: "hi",
            formattedNotes: "",
            micAudioPath: nil,
            systemAudioPath: nil
        )
        try store.enqueueMeetingSync(meetingID: id)
        return id
    }

    @Test("backoff schedule clamps to last entry past 6 attempts")
    func backoffSchedule() {
        #expect(MeetingSyncWorker.backoff(attempts: 1) == 1)
        #expect(MeetingSyncWorker.backoff(attempts: 2) == 5)
        #expect(MeetingSyncWorker.backoff(attempts: 3) == 30)
        #expect(MeetingSyncWorker.backoff(attempts: 4) == 300)
        #expect(MeetingSyncWorker.backoff(attempts: 5) == 1800)
        #expect(MeetingSyncWorker.backoff(attempts: 6) == 3600)
        #expect(MeetingSyncWorker.backoff(attempts: 7) == 3600)
        #expect(MeetingSyncWorker.backoff(attempts: 12) == 3600)
        #expect(MeetingSyncWorker.backoff(attempts: 0) == 1)
    }

    @Test("successful drain marks entry done")
    @MainActor
    func successfulDrainMarksDone() async throws {
        let store = try makeStore()
        let meetingID = try enqueueMeeting(store)

        var config = AppConfig()
        config.meetingSyncEnabled = true
        let client = StubSyncClient(behavior: .success)

        let worker = MeetingSyncWorker(
            store: store,
            client: client,
            configProvider: { config }
        )

        await runWorkerOnce(worker: worker)

        let entry = try store.meetingSyncEntry(meetingID: meetingID)
        #expect(entry?.status == .done)
        #expect(client.callCount == 1)
    }

    @Test("transient failure marks entry pending and records error")
    @MainActor
    func transientFailureKeepsPending() async throws {
        let store = try makeStore()
        let meetingID = try enqueueMeeting(store)

        var config = AppConfig()
        config.meetingSyncEnabled = true
        let client = StubSyncClient(behavior: .fail(MeetingSyncError.transport(underlying: NSError(domain: "x", code: 1))))

        let worker = MeetingSyncWorker(
            store: store,
            client: client,
            configProvider: { config }
        )

        await runWorkerOnce(worker: worker)

        let entry = try store.meetingSyncEntry(meetingID: meetingID)
        #expect(entry?.status == .pending)
        #expect(entry?.attempts == 1)
        #expect(entry?.lastError != nil)
    }

    @Test("terminal failure marks entry failed")
    @MainActor
    func terminalFailureMarksFailed() async throws {
        let store = try makeStore()
        let meetingID = try enqueueMeeting(store)

        var config = AppConfig()
        config.meetingSyncEnabled = true
        let client = StubSyncClient(behavior: .fail(MeetingSyncError.unauthorized))

        let worker = MeetingSyncWorker(
            store: store,
            client: client,
            configProvider: { config }
        )

        await runWorkerOnce(worker: worker)

        let entry = try store.meetingSyncEntry(meetingID: meetingID)
        #expect(entry?.status == .failed)
    }

    @Test("max-attempts cap converts non-terminal failures to terminal")
    @MainActor
    func maxAttemptsCapsRetries() async throws {
        let store = try makeStore()
        let meetingID = try enqueueMeeting(store)

        // Pre-set attempts to maxAttempts - 1 so the next failure trips the cap.
        for _ in 0..<(MeetingSyncWorker.maxAttempts - 1) {
            try store.markMeetingSyncStarting(meetingID: meetingID, at: Date(timeIntervalSinceNow: -1))
        }
        try store.recordMeetingSyncFailure(meetingID: meetingID, error: "transient", terminal: false)

        var config = AppConfig()
        config.meetingSyncEnabled = true
        let client = StubSyncClient(behavior: .fail(MeetingSyncError.transport(underlying: NSError(domain: "x", code: 1))))

        let worker = MeetingSyncWorker(
            store: store,
            client: client,
            configProvider: { config },
            now: { Date(timeIntervalSinceNow: 60 * 60 * 24) }   // bypass backoff wait
        )
        await runWorkerOnce(worker: worker)

        let entry = try store.meetingSyncEntry(meetingID: meetingID)
        #expect(entry?.status == .failed)
        #expect(entry?.attempts == MeetingSyncWorker.maxAttempts)
    }

    @Test("entry inside backoff window is skipped")
    @MainActor
    func backoffWindowSkipsEntry() async throws {
        let store = try makeStore()
        let meetingID = try enqueueMeeting(store)
        try store.markMeetingSyncStarting(meetingID: meetingID, at: Date())
        try store.recordMeetingSyncFailure(meetingID: meetingID, error: "transient", terminal: false)

        var config = AppConfig()
        config.meetingSyncEnabled = true
        let client = StubSyncClient(behavior: .success)

        let worker = MeetingSyncWorker(
            store: store,
            client: client,
            configProvider: { config },
            now: { Date() }   // immediately after the failed attempt
        )
        await runWorkerOnce(worker: worker)

        // Should not have been re-attempted yet (backoff[1] = 1s).
        #expect(client.callCount == 0)
        let entry = try store.meetingSyncEntry(meetingID: meetingID)
        #expect(entry?.attempts == 1)
        #expect(entry?.status == .pending)
    }

    @Test("disabled sync makes kick a no-op")
    @MainActor
    func disabledSyncSkipsDrain() async throws {
        let store = try makeStore()
        let meetingID = try enqueueMeeting(store)

        var config = AppConfig()
        config.meetingSyncEnabled = false
        let client = StubSyncClient(behavior: .success)
        let worker = MeetingSyncWorker(
            store: store,
            client: client,
            configProvider: { config }
        )

        await runWorkerOnce(worker: worker)

        #expect(client.callCount == 0)
        let entry = try store.meetingSyncEntry(meetingID: meetingID)
        #expect(entry?.status == .pending)
    }

    // MARK: - Helpers

    @MainActor
    private func runWorkerOnce(worker: MeetingSyncWorker) async {
        await worker.drainNowForTesting()
    }
}

private final class StubSyncClient: MeetingSyncClientProtocol, @unchecked Sendable {
    enum Behavior {
        case success
        case fail(MeetingSyncError)
    }

    private let lock = NSLock()
    private var _callCount = 0
    private let behavior: Behavior

    init(behavior: Behavior) {
        self.behavior = behavior
    }

    var callCount: Int {
        lock.lock()
        let value = _callCount
        lock.unlock()
        return value
    }

    func sync(meetingID: Int64) async throws -> MeetingSyncResult {
        lock.lock()
        _callCount += 1
        let behavior = self.behavior
        lock.unlock()
        switch behavior {
        case .success:
            return MeetingSyncResult(serverMeetingID: "srv-\(meetingID)", audioUploaded: false)
        case .fail(let error):
            throw error
        }
    }

    func testConnection(endpoint: String, token: String) async -> MeetingSyncConnectionTestResult {
        .success(version: "1.0.0-test")
    }
}
