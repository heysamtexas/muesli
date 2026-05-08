import CommonCrypto
import Foundation
import HTTPTypes
import MuesliCore
import OpenAPIRuntime
import OpenAPIURLSession
import os

enum MeetingSyncError: LocalizedError {
    case sourceMeetingMissing(meetingID: Int64)
    case endpointNotConfigured
    case invalidEndpoint(String)
    case unauthorized
    case clientMeetingIDCollision(message: String)
    case validationFailed(message: String)
    case audioFileMissing(path: String)
    case audioFileUnreadable(path: String, underlying: Error)
    case audioUploadFailed(statusCode: Int, message: String)
    case serverError(statusCode: Int, message: String)
    case transport(underlying: Error)
    case undocumentedResponse(statusCode: Int)

    var errorDescription: String? {
        switch self {
        case .sourceMeetingMissing(let id):
            return "Local meeting \(id) is missing; can't sync."
        case .endpointNotConfigured:
            return "Meeting sync server URL is not configured."
        case .invalidEndpoint(let s):
            return "Meeting sync URL is invalid: \(s)"
        case .unauthorized:
            return "Server rejected the auth token."
        case .clientMeetingIDCollision(let msg):
            return "Server reported a clientMeetingId collision: \(msg)"
        case .validationFailed(let msg):
            return "Server rejected the meeting payload: \(msg)"
        case .audioFileMissing(let path):
            return "Recorded audio file is missing: \(path)"
        case .audioFileUnreadable(let path, let underlying):
            return "Couldn't read audio file at \(path): \(underlying.localizedDescription)"
        case .audioUploadFailed(let code, let msg):
            return "Audio upload failed (HTTP \(code)): \(msg)"
        case .serverError(let code, let msg):
            return "Sync server error (HTTP \(code)): \(msg)"
        case .transport(let underlying):
            return underlying.localizedDescription
        case .undocumentedResponse(let code):
            return "Sync server returned an undocumented HTTP \(code) response."
        }
    }

    /// Failures the worker should treat as terminal (no point retrying).
    var isTerminal: Bool {
        switch self {
        case .endpointNotConfigured,
             .invalidEndpoint,
             .unauthorized,
             .clientMeetingIDCollision,
             .validationFailed,
             .audioFileMissing,
             .undocumentedResponse:
            return true
        case .audioFileUnreadable,
             .audioUploadFailed,
             .serverError,
             .transport,
             .sourceMeetingMissing:
            return false
        }
    }
}

struct MeetingSyncResult: Sendable, Equatable {
    let serverMeetingID: String
    let audioUploaded: Bool
}

enum MeetingSyncConnectionTestResult: Sendable, Equatable {
    case success(version: String)
    case unauthorized
    case invalidEndpoint(String)
    case unreachable(String)
    case unexpectedStatus(Int)
}

protocol MeetingSyncClientProtocol: Sendable {
    func sync(meetingID: Int64) async throws -> MeetingSyncResult
    func testConnection(endpoint: String, token: String) async -> MeetingSyncConnectionTestResult
}

actor MeetingSyncClient: MeetingSyncClientProtocol {
    typealias ConfigProvider = @Sendable () -> AppConfig

    private static let logger = Logger(subsystem: "com.muesli.native", category: "MeetingSync")

    private let store: DictationStore
    private let configProvider: ConfigProvider
    private let urlSession: URLSession
    private let bodyChunkSize: Int

    init(
        store: DictationStore,
        configProvider: @escaping ConfigProvider,
        urlSession: URLSession = .shared,
        bodyChunkSize: Int = 1_048_576
    ) {
        self.store = store
        self.configProvider = configProvider
        self.urlSession = urlSession
        self.bodyChunkSize = bodyChunkSize
    }

    // MARK: - Public

    func sync(meetingID: Int64) async throws -> MeetingSyncResult {
        let config = configProvider()
        let endpoint = try Self.normalizedEndpoint(config.meetingSyncEndpoint)
        let token = config.meetingSyncAuthToken

        guard let meeting = try store.meeting(id: meetingID) else {
            throw MeetingSyncError.sourceMeetingMissing(meetingID: meetingID)
        }

        let audioPath = audioPathForUpload(meeting: meeting, config: config)
        let audioMetadata = try buildAudioMetadata(audioPath: audioPath)
        let request = buildCreateRequest(
            meeting: meeting,
            config: config,
            audio: audioMetadata
        )

        let client = makeClient(endpoint: endpoint, token: token)
        let createResponse = try await postMetadata(client: client, request: request)
        try store.recordMeetingSyncMetadataUploaded(
            meetingID: meetingID,
            serverMeetingID: createResponse.id,
            audioUploadURL: createResponse.audioUploadURL
        )

        var didUploadAudio = false
        if let audioPath, audioMetadata != nil {
            let uploadURL = try resolveAudioUploadURL(
                createResponse: createResponse,
                endpoint: endpoint,
                serverMeetingID: createResponse.id
            )
            try await streamAudioFile(at: audioPath, to: uploadURL, token: token)
            try store.recordMeetingSyncAudioUploaded(meetingID: meetingID)
            didUploadAudio = true
        }

        return MeetingSyncResult(
            serverMeetingID: createResponse.id,
            audioUploaded: didUploadAudio
        )
    }

    func testConnection(endpoint: String, token: String) async -> MeetingSyncConnectionTestResult {
        let normalized: URL
        do {
            normalized = try Self.normalizedEndpoint(endpoint)
        } catch let MeetingSyncError.invalidEndpoint(value) {
            return .invalidEndpoint(value)
        } catch {
            return .invalidEndpoint(endpoint)
        }
        let client = makeClient(endpoint: normalized, token: token)
        do {
            let output = try await client.getHealth(.init())
            switch output {
            case .ok(let body):
                let payload = try body.body.json
                return .success(version: payload.version)
            case .unauthorized:
                return .unauthorized
            case .undocumented(statusCode: let code, _):
                return .unexpectedStatus(code)
            }
        } catch {
            return .unreachable(error.localizedDescription)
        }
    }

    // MARK: - Internal helpers (testing seams)

    nonisolated static func clientMeetingID(installID: String, meetingID: Int64) -> String {
        let trimmed = installID.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            // Should never happen in production — MuesliController populates the
            // install ID before enqueuing — but guard so unit tests that bypass
            // the controller still produce a sensible id.
            return "muesli-\(meetingID)"
        }
        return "muesli-\(trimmed)-\(meetingID)"
    }

    nonisolated static func normalizedEndpoint(_ raw: String) throws -> URL {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            throw MeetingSyncError.endpointNotConfigured
        }
        var s = trimmed
        while s.hasSuffix("/") { s.removeLast() }
        if s.hasSuffix("/api/v1") { s.removeLast("/api/v1".count) }
        guard let url = URL(string: s),
              let scheme = url.scheme?.lowercased(),
              scheme == "http" || scheme == "https",
              url.host != nil else {
            throw MeetingSyncError.invalidEndpoint(raw)
        }
        return url
    }

    // MARK: - Private

    private func makeClient(endpoint: URL, token: String) -> Client {
        Client(
            serverURL: endpoint,
            configuration: .init(dateTranscoder: PermissiveISODateTranscoder()),
            transport: URLSessionTransport(configuration: .init(session: urlSession)),
            middlewares: [BearerAuthMiddleware(token: token)]
        )
    }

    private func audioPathForUpload(meeting: MeetingRecord, config: AppConfig) -> String? {
        guard config.meetingSyncIncludeAudio else { return nil }
        guard let path = meeting.savedRecordingPath, !path.isEmpty else { return nil }
        return path
    }

    private func buildAudioMetadata(audioPath: String?) throws -> Components.Schemas.AudioMetadata? {
        guard let audioPath else { return nil }
        let url = URL(fileURLWithPath: audioPath)
        guard FileManager.default.fileExists(atPath: url.path) else {
            throw MeetingSyncError.audioFileMissing(path: audioPath)
        }
        let attrs: [FileAttributeKey: Any]
        do {
            attrs = try FileManager.default.attributesOfItem(atPath: url.path)
        } catch {
            throw MeetingSyncError.audioFileUnreadable(path: audioPath, underlying: error)
        }
        let size = (attrs[.size] as? NSNumber)?.int64Value ?? 0
        let digest = try sha256Hex(of: url)
        return .init(
            available: true,
            format: .wav,
            sizeBytes: size,
            sha256: digest
        )
    }

    private func buildCreateRequest(
        meeting: MeetingRecord,
        config: AppConfig,
        audio: Components.Schemas.AudioMetadata?
    ) -> Components.Schemas.MeetingCreateRequest {
        let startDate = parseISODate(meeting.startTime) ?? Date()
        let endDate = startDate.addingTimeInterval(meeting.durationSeconds)
        let templatePayload: Components.Schemas.Template? = {
            guard let id = meeting.selectedTemplateID, !id.isEmpty else { return nil }
            return .init(
                id: id,
                name: meeting.selectedTemplateName ?? "",
                kind: meeting.selectedTemplateKind?.rawValue ?? ""
            )
        }()
        let formattedNotes = config.meetingSyncIncludeNotes ? meeting.formattedNotes : ""
        let manualNotes = config.meetingSyncIncludeManualNotes ? meeting.manualNotes : ""

        return .init(
            schemaVersion: ._1,
            clientMeetingId: Self.clientMeetingID(installID: config.meetingSyncInstallID, meetingID: meeting.id),
            title: meeting.title,
            startTime: startDate,
            endTime: endDate,
            durationSeconds: meeting.durationSeconds,
            calendarEventId: meeting.calendarEventID,
            transcript: meeting.rawTranscript,
            wordCount: meeting.wordCount,
            formattedNotes: formattedNotes,
            manualNotes: manualNotes,
            template: templatePayload,
            folder: nil,
            completedAt: endDate,
            audio: audio
        )
    }

    private func postMetadata(
        client: Client,
        request: Components.Schemas.MeetingCreateRequest
    ) async throws -> Components.Schemas.MeetingCreateResponse {
        let output: Operations.CreateMeeting.Output
        do {
            output = try await client.createMeeting(.init(body: .json(request)))
        } catch {
            throw MeetingSyncError.transport(underlying: error)
        }
        switch output {
        case .created(let response):
            return try response.body.json
        case .ok(let response):
            return try response.body.json
        case .unauthorized:
            throw MeetingSyncError.unauthorized
        case .conflict(let response):
            let message = (try? response.body.json.error) ?? "client_meeting_id_collision"
            throw MeetingSyncError.clientMeetingIDCollision(message: message)
        case .unprocessableContent(let response):
            let message = (try? response.body.json.error) ?? "validation_error"
            throw MeetingSyncError.validationFailed(message: message)
        case .undocumented(statusCode: let code, _):
            if (500..<600).contains(code) {
                throw MeetingSyncError.serverError(statusCode: code, message: "server returned \(code)")
            }
            throw MeetingSyncError.undocumentedResponse(statusCode: code)
        }
    }

    private func resolveAudioUploadURL(
        createResponse: Components.Schemas.MeetingCreateResponse,
        endpoint: URL,
        serverMeetingID: String
    ) throws -> URL {
        if let raw = createResponse.audioUploadURL,
           !raw.isEmpty,
           let url = URL(string: raw) {
            return url
        }
        // Fall back to the deterministic path on the configured server. Keeps
        // sync working if a buggy server forgets to populate the field.
        return endpoint
            .appendingPathComponent("api")
            .appendingPathComponent("v1")
            .appendingPathComponent("meetings")
            .appendingPathComponent(serverMeetingID)
            .appendingPathComponent("audio")
    }

    private func streamAudioFile(at path: String, to url: URL, token: String) async throws {
        let fileURL = URL(fileURLWithPath: path)
        guard FileManager.default.fileExists(atPath: fileURL.path) else {
            throw MeetingSyncError.audioFileMissing(path: path)
        }
        var request = URLRequest(url: url)
        request.httpMethod = "PUT"
        request.setValue("audio/wav", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")

        let (data, response): (Data, URLResponse)
        do {
            (data, response) = try await urlSession.upload(for: request, fromFile: fileURL)
        } catch {
            throw MeetingSyncError.transport(underlying: error)
        }
        guard let httpResponse = response as? HTTPURLResponse else {
            throw MeetingSyncError.audioUploadFailed(statusCode: -1, message: "no HTTP response")
        }
        let status = httpResponse.statusCode
        if (200..<300).contains(status) { return }

        let message = String(data: data, encoding: .utf8)?.prefix(800).trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        switch status {
        case 401:
            throw MeetingSyncError.unauthorized
        case 404:
            // Treat as terminal — server lost the meeting record; client must re-create.
            throw MeetingSyncError.validationFailed(message: "audio target meeting not found on server")
        case 413:
            throw MeetingSyncError.validationFailed(message: "audio body exceeds server limit")
        case 415:
            throw MeetingSyncError.validationFailed(message: "server rejected Content-Type audio/wav")
        case 422:
            throw MeetingSyncError.validationFailed(message: String(message))
        case 500..<600:
            throw MeetingSyncError.serverError(statusCode: status, message: String(message))
        default:
            throw MeetingSyncError.audioUploadFailed(statusCode: status, message: String(message))
        }
    }

    private func parseISODate(_ s: String) -> Date? {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let d = formatter.date(from: s) { return d }
        formatter.formatOptions = [.withInternetDateTime]
        return formatter.date(from: s)
    }

    private func sha256Hex(of url: URL) throws -> String {
        let handle: FileHandle
        do {
            handle = try FileHandle(forReadingFrom: url)
        } catch {
            throw MeetingSyncError.audioFileUnreadable(path: url.path, underlying: error)
        }
        defer { try? handle.close() }
        var hasher = SHA256Streaming()
        while true {
            let chunk: Data
            do {
                chunk = try handle.read(upToCount: bodyChunkSize) ?? Data()
            } catch {
                throw MeetingSyncError.audioFileUnreadable(path: url.path, underlying: error)
            }
            if chunk.isEmpty { break }
            hasher.update(chunk)
        }
        return hasher.finalizeHex()
    }
}

// MARK: - Date transcoder

/// Accepts the dialect Django/DRF emit (microsecond fractions, `+HH:MM` offsets,
/// trailing `Z`) and the dialect plain `ISO8601DateFormatter` produces. Encodes
/// in the millisecond-precision form Apple's stack defaults to.
struct PermissiveISODateTranscoder: DateTranscoder {
    private static let withFractional: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()

    private static let plain: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime]
        return f
    }()

    func encode(_ date: Date) throws -> String {
        Self.withFractional.string(from: date)
    }

    func decode(_ value: String) throws -> Date {
        // ISO8601DateFormatter rejects fractions with more than 3 decimal digits,
        // and Django emits 6 (microseconds). Trim to 3 before parsing.
        let trimmed = Self.truncateFractionalSeconds(value)
        if let date = Self.withFractional.date(from: trimmed) {
            return date
        }
        if let date = Self.plain.date(from: trimmed) {
            return date
        }
        throw DecodingError.dataCorrupted(
            DecodingError.Context(codingPath: [], debugDescription: "Expected ISO8601 date, got \(value)")
        )
    }

    static func truncateFractionalSeconds(_ value: String) -> String {
        value.replacingOccurrences(
            of: #"\.(\d{3})\d+"#,
            with: ".$1",
            options: .regularExpression
        )
    }
}

// MARK: - Bearer auth middleware

private struct BearerAuthMiddleware: ClientMiddleware {
    let token: String

    func intercept(
        _ request: HTTPRequest,
        body: HTTPBody?,
        baseURL: URL,
        operationID: String,
        next: @Sendable (HTTPRequest, HTTPBody?, URL) async throws -> (HTTPResponse, HTTPBody?)
    ) async throws -> (HTTPResponse, HTTPBody?) {
        var mutated = request
        if !token.isEmpty {
            mutated.headerFields[.authorization] = "Bearer \(token)"
        }
        return try await next(mutated, body, baseURL)
    }
}

// MARK: - SHA-256 (chunked)

private struct SHA256Streaming {
    private var context = CC_SHA256_CTX()
    private var initialized = false

    init() {
        CC_SHA256_Init(&context)
        initialized = true
    }

    mutating func update(_ data: Data) {
        guard initialized, !data.isEmpty else { return }
        data.withUnsafeBytes { buffer in
            _ = CC_SHA256_Update(&context, buffer.baseAddress, CC_LONG(buffer.count))
        }
    }

    mutating func finalizeHex() -> String {
        var digest = [UInt8](repeating: 0, count: Int(CC_SHA256_DIGEST_LENGTH))
        CC_SHA256_Final(&digest, &context)
        return digest.map { String(format: "%02x", $0) }.joined()
    }
}
