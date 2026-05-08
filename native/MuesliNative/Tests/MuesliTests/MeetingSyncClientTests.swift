import Foundation
import Testing
import MuesliCore
@testable import MuesliNativeApp

@Suite("MeetingSyncClient", .serialized)
struct MeetingSyncClientTests {

    @Test("normalizedEndpoint trims trailing slash and /api/v1 suffix")
    func normalizedEndpointTrims() throws {
        let a = try MeetingSyncClient.normalizedEndpoint("http://localhost:8000")
        #expect(a.absoluteString == "http://localhost:8000")
        let b = try MeetingSyncClient.normalizedEndpoint("https://meetings.example.com/")
        #expect(b.absoluteString == "https://meetings.example.com")
        let c = try MeetingSyncClient.normalizedEndpoint("https://meetings.example.com/api/v1/")
        #expect(c.absoluteString == "https://meetings.example.com")
        let d = try MeetingSyncClient.normalizedEndpoint("  https://example.com/api/v1  ")
        #expect(d.absoluteString == "https://example.com")
    }

    @Test("normalizedEndpoint rejects empty / non-http URLs")
    func normalizedEndpointRejectsBadValues() {
        #expect(throws: MeetingSyncError.self) {
            _ = try MeetingSyncClient.normalizedEndpoint("")
        }
        #expect(throws: MeetingSyncError.self) {
            _ = try MeetingSyncClient.normalizedEndpoint("ftp://example.com")
        }
        #expect(throws: MeetingSyncError.self) {
            _ = try MeetingSyncClient.normalizedEndpoint("not-a-url")
        }
    }

    @Test("PermissiveISODateTranscoder accepts microsecond + millisecond + second precision")
    func permissiveDateDecoder() throws {
        let transcoder = PermissiveISODateTranscoder()
        // Django default — microseconds + +HH:MM offset.
        let micro = try transcoder.decode("2026-05-08T21:50:41.823160+00:00")
        // Apple default — milliseconds + Z.
        let milli = try transcoder.decode("2026-05-08T21:50:41.823Z")
        // Plain — no fractional seconds.
        let plain = try transcoder.decode("2026-05-08T21:50:41Z")
        #expect(abs(micro.timeIntervalSince(milli)) < 0.01)
        #expect(abs(plain.timeIntervalSince(milli)) < 1.0)
    }

    @Test("PermissiveISODateTranscoder fails fast on garbage")
    func permissiveDateDecoderRejectsGarbage() {
        let transcoder = PermissiveISODateTranscoder()
        #expect(throws: (any Error).self) {
            _ = try transcoder.decode("not a date")
        }
    }

    @Test("clientMeetingID combines install id and local row id")
    func clientMeetingIDFormat() {
        #expect(MeetingSyncClient.clientMeetingID(installID: "7e9c1a40", meetingID: 1) == "muesli-7e9c1a40-1")
        #expect(MeetingSyncClient.clientMeetingID(installID: "abc", meetingID: 42) == "muesli-abc-42")
        // Install id whitespace stripped; empty fallback emits the legacy form.
        #expect(MeetingSyncClient.clientMeetingID(installID: "  ", meetingID: 9) == "muesli-9")
        #expect(MeetingSyncClient.clientMeetingID(installID: " trim ", meetingID: 5) == "muesli-trim-5")
    }

    @Test("MeetingSyncError.isTerminal matches the worker's retry classification")
    func errorTerminalClassification() {
        // Terminal: server told us the request shape is wrong, or auth is bad.
        #expect(MeetingSyncError.unauthorized.isTerminal)
        #expect(MeetingSyncError.invalidEndpoint("x").isTerminal)
        #expect(MeetingSyncError.endpointNotConfigured.isTerminal)
        #expect(MeetingSyncError.clientMeetingIDCollision(message: "x").isTerminal)
        #expect(MeetingSyncError.validationFailed(message: "x").isTerminal)
        #expect(MeetingSyncError.audioFileMissing(path: "/x").isTerminal)
        // Retryable: network/transport/server hiccups.
        #expect(!MeetingSyncError.transport(underlying: NSError(domain: "", code: 0)).isTerminal)
        #expect(!MeetingSyncError.serverError(statusCode: 500, message: "x").isTerminal)
        #expect(!MeetingSyncError.audioUploadFailed(statusCode: 502, message: "x").isTerminal)
    }

    @Test("testConnection returns success on 200 health response")
    func testConnectionSuccess() async throws {
        let session = makeStubbedSession()
        StubURLProtocol.responder = { request in
            #expect(request.url?.path == "/api/v1/health")
            #expect(request.value(forHTTPHeaderField: "Authorization") == "Bearer secret-token")
            let body = try! JSONSerialization.data(withJSONObject: ["ok": true, "version": "1.0.0-stub"])
            let response = HTTPURLResponse(
                url: request.url!,
                statusCode: 200,
                httpVersion: "HTTP/1.1",
                headerFields: ["Content-Type": "application/json"]
            )!
            return (response, body)
        }
        defer { StubURLProtocol.responder = nil }

        let store = try makeStore()
        let client = MeetingSyncClient(
            store: store,
            configProvider: { AppConfig() },
            urlSession: session
        )
        let result = await client.testConnection(endpoint: "http://localhost:9999", token: "secret-token")
        #expect(result == .success(version: "1.0.0-stub"))
    }

    @Test("testConnection maps 401 to unauthorized")
    func testConnectionUnauthorized() async throws {
        let session = makeStubbedSession()
        StubURLProtocol.responder = { request in
            let body = try! JSONSerialization.data(withJSONObject: ["error": "bad token", "code": "unauthorized"])
            let response = HTTPURLResponse(
                url: request.url!,
                statusCode: 401,
                httpVersion: "HTTP/1.1",
                headerFields: ["Content-Type": "application/json"]
            )!
            return (response, body)
        }
        defer { StubURLProtocol.responder = nil }

        let store = try makeStore()
        let client = MeetingSyncClient(
            store: store,
            configProvider: { AppConfig() },
            urlSession: session
        )
        let result = await client.testConnection(endpoint: "http://localhost:9999", token: "wrong")
        #expect(result == .unauthorized)
    }

    @Test("testConnection on invalid URL reports invalidEndpoint")
    func testConnectionInvalidURL() async {
        let store = try! makeStore()
        let client = MeetingSyncClient(
            store: store,
            configProvider: { AppConfig() }
        )
        let result = await client.testConnection(endpoint: "", token: "x")
        if case .invalidEndpoint = result { /* ok */ }
        else { Issue.record("expected invalidEndpoint, got \(result)") }
    }

    @Test("sync POSTs metadata and PUTs audio in two separate requests")
    func syncPostsThenPutsAudio() async throws {
        // Set up a temp WAV file so the client can sha256 + upload it.
        let tempWav = FileManager.default.temporaryDirectory.appendingPathComponent("sync-test-\(UUID().uuidString).wav")
        try Data([0x52, 0x49, 0x46, 0x46, 0xff, 0xff, 0xff, 0xff]).write(to: tempWav)
        defer { try? FileManager.default.removeItem(at: tempWav) }

        let store = try makeStore()
        let meetingID = try store.insertMeeting(
            title: "Audio test",
            calendarEventID: nil,
            startTime: Date(timeIntervalSince1970: 1_700_000_000),
            endTime: Date(timeIntervalSince1970: 1_700_000_120),
            rawTranscript: "hello",
            formattedNotes: "## Notes",
            micAudioPath: nil,
            systemAudioPath: nil,
            savedRecordingPath: tempWav.path
        )
        try store.enqueueMeetingSync(meetingID: meetingID)
        try store.markMeetingSyncStarting(meetingID: meetingID)

        let session = makeStubbedSession()
        let observed = ObservedRequests()
        StubURLProtocol.responder = { request in
            observed.append(request)
            if request.httpMethod == "POST", request.url?.path == "/api/v1/meetings" {
                let payload: [String: Any] = [
                    "id": "srv-meeting-uuid",
                    "clientMeetingId": "muesli-\(meetingID)",
                    "audioUploadURL": "http://localhost:9999/api/v1/meetings/srv-meeting-uuid/audio",
                    "createdAt": "2026-05-08T10:00:00Z",
                ]
                let body = try! JSONSerialization.data(withJSONObject: payload)
                let response = HTTPURLResponse(
                    url: request.url!,
                    statusCode: 201,
                    httpVersion: "HTTP/1.1",
                    headerFields: ["Content-Type": "application/json"]
                )!
                return (response, body)
            }
            if request.httpMethod == "PUT" {
                let payload: [String: Any] = [
                    "id": "srv-meeting-uuid",
                    "audioBytes": 8,
                    "audioStoredAt": "2026-05-08T10:01:00Z",
                ]
                let body = try! JSONSerialization.data(withJSONObject: payload)
                let response = HTTPURLResponse(
                    url: request.url!,
                    statusCode: 200,
                    httpVersion: "HTTP/1.1",
                    headerFields: ["Content-Type": "application/json"]
                )!
                return (response, body)
            }
            let response = HTTPURLResponse(url: request.url!, statusCode: 500, httpVersion: nil, headerFields: nil)!
            return (response, Data())
        }
        defer { StubURLProtocol.responder = nil }

        var config = AppConfig()
        config.meetingSyncEnabled = true
        config.meetingSyncEndpoint = "http://localhost:9999"
        config.meetingSyncAuthToken = "secret-token"
        config.meetingSyncIncludeAudio = true
        let client = MeetingSyncClient(
            store: store,
            configProvider: { config },
            urlSession: session
        )

        let result = try await client.sync(meetingID: meetingID)
        #expect(result.serverMeetingID == "srv-meeting-uuid")
        #expect(result.audioUploaded == true)

        let urls = observed.snapshot().compactMap { $0.url?.path }
        #expect(urls.contains("/api/v1/meetings"))
        #expect(urls.contains("/api/v1/meetings/srv-meeting-uuid/audio"))

        let entry = try store.meetingSyncEntry(meetingID: meetingID)
        #expect(entry?.serverMeetingID == "srv-meeting-uuid")
        #expect(entry?.audioUploaded == true)
        #expect(entry?.audioUploadURL == nil)
    }

    @Test("sync without audio path skips the audio PUT")
    func syncSkipsAudioWhenPathMissing() async throws {
        let store = try makeStore()
        let meetingID = try store.insertMeeting(
            title: "No audio",
            calendarEventID: nil,
            startTime: Date(),
            endTime: Date().addingTimeInterval(60),
            rawTranscript: "hi",
            formattedNotes: "",
            micAudioPath: nil,
            systemAudioPath: nil,
            savedRecordingPath: nil
        )
        try store.enqueueMeetingSync(meetingID: meetingID)
        try store.markMeetingSyncStarting(meetingID: meetingID)

        let session = makeStubbedSession()
        let observed = ObservedRequests()
        StubURLProtocol.responder = { request in
            observed.append(request)
            let payload: [String: Any] = [
                "id": "srv-no-audio",
                "clientMeetingId": "muesli-\(meetingID)",
                "createdAt": "2026-05-08T10:00:00Z",
            ]
            let body = try! JSONSerialization.data(withJSONObject: payload)
            let response = HTTPURLResponse(
                url: request.url!,
                statusCode: 201,
                httpVersion: "HTTP/1.1",
                headerFields: ["Content-Type": "application/json"]
            )!
            return (response, body)
        }
        defer { StubURLProtocol.responder = nil }

        var config = AppConfig()
        config.meetingSyncEnabled = true
        config.meetingSyncEndpoint = "http://localhost:9999"
        config.meetingSyncAuthToken = "secret-token"
        let client = MeetingSyncClient(
            store: store,
            configProvider: { config },
            urlSession: session
        )

        let result = try await client.sync(meetingID: meetingID)
        #expect(result.audioUploaded == false)
        #expect(observed.snapshot().count == 1)
    }

    @Test(
        "live: testConnection + sync end-to-end against MUESLI_LIVE_SYNC_BASE_URL",
        .enabled(if: ProcessInfo.processInfo.environment["MUESLI_LIVE_SYNC_BASE_URL"] != nil
                 && ProcessInfo.processInfo.environment["MUESLI_LIVE_SYNC_TOKEN"] != nil)
    )
    func liveSyncEndToEnd() async throws {
        let env = ProcessInfo.processInfo.environment
        guard let endpoint = env["MUESLI_LIVE_SYNC_BASE_URL"],
              let token = env["MUESLI_LIVE_SYNC_TOKEN"] else { return }

        let store = try makeStore()
        let wav = FileManager.default.temporaryDirectory.appendingPathComponent("muesli-live-\(UUID().uuidString).wav")
        try Data([0x52, 0x49, 0x46, 0x46, 0x24, 0x00, 0x00, 0x00, 0x57, 0x41, 0x56, 0x45]).write(to: wav)
        defer { try? FileManager.default.removeItem(at: wav) }

        let meetingID = try store.insertMeeting(
            title: "Muesli live smoke",
            calendarEventID: nil,
            startTime: Date(),
            endTime: Date().addingTimeInterval(45),
            rawTranscript: "live sync transcript",
            formattedNotes: "## Live Notes",
            micAudioPath: nil,
            systemAudioPath: nil,
            savedRecordingPath: wav.path
        )
        try store.enqueueMeetingSync(meetingID: meetingID)
        try store.markMeetingSyncStarting(meetingID: meetingID)

        var config = AppConfig()
        config.meetingSyncEnabled = true
        config.meetingSyncEndpoint = endpoint
        config.meetingSyncAuthToken = token
        config.meetingSyncIncludeAudio = true
        config.meetingSyncIncludeNotes = true
        config.meetingSyncIncludeManualNotes = true
        // Per-run install id keeps clientMeetingId unique across runs against
        // the same persistent server.
        config.meetingSyncInstallID = String(UUID().uuidString.lowercased().prefix(8))

        let client = MeetingSyncClient(
            store: store,
            configProvider: { config }
        )

        let testResult = await client.testConnection(endpoint: endpoint, token: token)
        if case .success = testResult {} else {
            Issue.record("expected .success from testConnection, got \(testResult)")
        }

        let result = try await client.sync(meetingID: meetingID)
        #expect(!result.serverMeetingID.isEmpty)
        #expect(result.audioUploaded == true)

        let entry = try store.meetingSyncEntry(meetingID: meetingID)
        #expect(entry?.serverMeetingID == result.serverMeetingID)
        #expect(entry?.audioUploaded == true)
        #expect(entry?.audioUploadURL == nil)

        // Bad token → unauthorized + no DB mutation.
        let bad = await client.testConnection(endpoint: endpoint, token: "definitely-not-the-token")
        #expect(bad == .unauthorized)
    }

    @Test("sync surfaces 401 as unauthorized")
    func syncSurfacesUnauthorized() async throws {
        let store = try makeStore()
        let meetingID = try store.insertMeeting(
            title: "401",
            calendarEventID: nil,
            startTime: Date(),
            endTime: Date().addingTimeInterval(30),
            rawTranscript: "",
            formattedNotes: "",
            micAudioPath: nil,
            systemAudioPath: nil
        )
        try store.enqueueMeetingSync(meetingID: meetingID)
        try store.markMeetingSyncStarting(meetingID: meetingID)

        let session = makeStubbedSession()
        StubURLProtocol.responder = { request in
            let body = try! JSONSerialization.data(withJSONObject: ["error": "no", "code": "unauthorized"])
            let response = HTTPURLResponse(
                url: request.url!,
                statusCode: 401,
                httpVersion: "HTTP/1.1",
                headerFields: ["Content-Type": "application/json"]
            )!
            return (response, body)
        }
        defer { StubURLProtocol.responder = nil }

        var config = AppConfig()
        config.meetingSyncEnabled = true
        config.meetingSyncEndpoint = "http://localhost:9999"
        config.meetingSyncAuthToken = "wrong"
        let client = MeetingSyncClient(
            store: store,
            configProvider: { config },
            urlSession: session
        )

        await #expect(throws: MeetingSyncError.self) {
            _ = try await client.sync(meetingID: meetingID)
        }
    }

    // MARK: - Helpers

    private func makeStore() throws -> DictationStore {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("muesli-sync-client-\(UUID().uuidString).db")
        let store = DictationStore(databaseURL: url)
        try store.migrateIfNeeded()
        return store
    }

    private func makeStubbedSession() -> URLSession {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [StubURLProtocol.self]
        return URLSession(configuration: config)
    }
}

// MARK: - URLProtocol stub

final class StubURLProtocol: URLProtocol {
    nonisolated(unsafe) static var responder: ((URLRequest) -> (HTTPURLResponse, Data))?

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        guard let responder = StubURLProtocol.responder else {
            client?.urlProtocol(self, didFailWithError: NSError(domain: "stub", code: -1))
            return
        }
        let (response, data) = responder(request)
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        if !data.isEmpty {
            client?.urlProtocol(self, didLoad: data)
        }
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}

private final class ObservedRequests: @unchecked Sendable {
    private let lock = NSLock()
    private var requests: [URLRequest] = []

    func append(_ request: URLRequest) {
        lock.lock(); defer { lock.unlock() }
        requests.append(request)
    }

    func snapshot() -> [URLRequest] {
        lock.lock(); defer { lock.unlock() }
        return requests
    }
}
