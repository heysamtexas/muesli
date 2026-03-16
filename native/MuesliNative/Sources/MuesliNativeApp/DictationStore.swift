import Foundation
import SQLite3

final class DictationStore {
    private let databaseURL: URL

    init() {
        let supportURL = AppIdentity.supportDirectoryURL
        self.databaseURL = supportURL.appendingPathComponent("muesli.db")
    }

    init(databaseURL: URL) {
        self.databaseURL = databaseURL
    }

    func migrateIfNeeded() throws {
        let db = try openDatabase()
        defer { sqlite3_close(db) }

        let createSQL = """
        CREATE TABLE IF NOT EXISTS dictations (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            timestamp TEXT NOT NULL,
            duration_seconds REAL,
            raw_text TEXT,
            app_context TEXT,
            word_count INTEGER NOT NULL DEFAULT 0,
            source TEXT NOT NULL DEFAULT 'dictation',
            started_at TEXT,
            ended_at TEXT,
            created_at TEXT DEFAULT (datetime('now'))
        );
        CREATE INDEX IF NOT EXISTS idx_dictations_timestamp ON dictations(timestamp DESC);

        CREATE TABLE IF NOT EXISTS meetings (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            title TEXT NOT NULL,
            calendar_event_id TEXT,
            start_time TEXT NOT NULL,
            end_time TEXT,
            duration_seconds REAL,
            raw_transcript TEXT,
            formatted_notes TEXT,
            mic_audio_path TEXT,
            system_audio_path TEXT,
            word_count INTEGER NOT NULL DEFAULT 0,
            source TEXT NOT NULL DEFAULT 'meeting',
            created_at TEXT DEFAULT (datetime('now'))
        );
        CREATE INDEX IF NOT EXISTS idx_meetings_start_time ON meetings(start_time DESC);
        """
        try exec(createSQL, db: db)

        // Migration: meeting folders
        let foldersSQL = """
        CREATE TABLE IF NOT EXISTS meeting_folders (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            name TEXT NOT NULL,
            sort_order INTEGER NOT NULL DEFAULT 0,
            created_at TEXT DEFAULT (datetime('now'))
        );
        """
        try exec(foldersSQL, db: db)

        // Add folder_id column to meetings (safe if already exists)
        if sqlite3_exec(db, "ALTER TABLE meetings ADD COLUMN folder_id INTEGER REFERENCES meeting_folders(id)", nil, nil, nil) != SQLITE_OK {
            // Column may already exist — that's fine
        }
        // Index for folder lookups
        let _ = sqlite3_exec(db, "CREATE INDEX IF NOT EXISTS idx_meetings_folder ON meetings(folder_id)", nil, nil, nil)
    }

    func insertDictation(
        text: String,
        durationSeconds: Double,
        appContext: String = "",
        startedAt: Date,
        endedAt: Date
    ) throws {
        let db = try openDatabase()
        defer { sqlite3_close(db) }

        let sql = """
        INSERT INTO dictations
        (timestamp, duration_seconds, raw_text, app_context, word_count, source, started_at, ended_at)
        VALUES (?, ?, ?, ?, ?, 'dictation', ?, ?)
        """
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else {
            throw lastError(db)
        }
        defer { sqlite3_finalize(statement) }

        let timestamp = ISO8601DateFormatter().string(from: endedAt)
        let started = ISO8601DateFormatter().string(from: startedAt)
        let ended = ISO8601DateFormatter().string(from: endedAt)
        sqlite3_bind_text(statement, 1, (timestamp as NSString).utf8String, -1, nil)
        sqlite3_bind_double(statement, 2, durationSeconds)
        sqlite3_bind_text(statement, 3, (text as NSString).utf8String, -1, nil)
        sqlite3_bind_text(statement, 4, (appContext as NSString).utf8String, -1, nil)
        sqlite3_bind_int(statement, 5, Int32(Self.countWords(in: text)))
        sqlite3_bind_text(statement, 6, (started as NSString).utf8String, -1, nil)
        sqlite3_bind_text(statement, 7, (ended as NSString).utf8String, -1, nil)

        guard sqlite3_step(statement) == SQLITE_DONE else {
            throw lastError(db)
        }
    }

    func recentDictations(limit: Int = 10) throws -> [DictationRecord] {
        let db = try openDatabase()
        defer { sqlite3_close(db) }

        let sql = """
        SELECT id, timestamp, duration_seconds, raw_text, app_context, word_count
        FROM dictations
        ORDER BY id DESC
        LIMIT ?
        """
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else {
            throw lastError(db)
        }
        defer { sqlite3_finalize(statement) }
        sqlite3_bind_int(statement, 1, Int32(limit))

        var rows: [DictationRecord] = []
        while sqlite3_step(statement) == SQLITE_ROW {
            rows.append(
                DictationRecord(
                    id: sqlite3_column_int64(statement, 0),
                    timestamp: stringColumn(statement, index: 1),
                    durationSeconds: sqlite3_column_double(statement, 2),
                    rawText: stringColumn(statement, index: 3),
                    appContext: stringColumn(statement, index: 4),
                    wordCount: Int(sqlite3_column_int(statement, 5))
                )
            )
        }
        return rows
    }

    func recentMeetings(limit: Int = 10) throws -> [MeetingRecord] {
        let db = try openDatabase()
        defer { sqlite3_close(db) }

        let sql = """
        SELECT id, title, start_time, duration_seconds, raw_transcript, formatted_notes, word_count, folder_id
        FROM meetings
        ORDER BY id DESC
        LIMIT ?
        """
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else {
            throw lastError(db)
        }
        defer { sqlite3_finalize(statement) }
        sqlite3_bind_int(statement, 1, Int32(limit))

        var rows: [MeetingRecord] = []
        while sqlite3_step(statement) == SQLITE_ROW {
            let folderID: Int64? = sqlite3_column_type(statement, 7) == SQLITE_NULL
                ? nil : sqlite3_column_int64(statement, 7)
            rows.append(
                MeetingRecord(
                    id: sqlite3_column_int64(statement, 0),
                    title: stringColumn(statement, index: 1),
                    startTime: stringColumn(statement, index: 2),
                    durationSeconds: sqlite3_column_double(statement, 3),
                    rawTranscript: stringColumn(statement, index: 4),
                    formattedNotes: stringColumn(statement, index: 5),
                    wordCount: Int(sqlite3_column_int(statement, 6)),
                    folderID: folderID
                )
            )
        }
        return rows
    }

    func insertMeeting(
        title: String,
        calendarEventID: String?,
        startTime: Date,
        endTime: Date,
        rawTranscript: String,
        formattedNotes: String,
        micAudioPath: String?,
        systemAudioPath: String?
    ) throws {
        let db = try openDatabase()
        defer { sqlite3_close(db) }

        let sql = """
        INSERT INTO meetings
        (title, calendar_event_id, start_time, end_time, duration_seconds, raw_transcript, formatted_notes, mic_audio_path, system_audio_path, word_count, source)
        VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, 'meeting')
        """
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else {
            throw lastError(db)
        }
        defer { sqlite3_finalize(statement) }

        let formatter = ISO8601DateFormatter()
        let startString = formatter.string(from: startTime)
        let endString = formatter.string(from: endTime)
        let durationSeconds = max(endTime.timeIntervalSince(startTime), 0)
        let wordCount = Self.countWords(in: rawTranscript)

        sqlite3_bind_text(statement, 1, (title as NSString).utf8String, -1, nil)
        bindOptionalText(calendarEventID, at: 2, statement: statement)
        sqlite3_bind_text(statement, 3, (startString as NSString).utf8String, -1, nil)
        sqlite3_bind_text(statement, 4, (endString as NSString).utf8String, -1, nil)
        sqlite3_bind_double(statement, 5, durationSeconds)
        sqlite3_bind_text(statement, 6, (rawTranscript as NSString).utf8String, -1, nil)
        sqlite3_bind_text(statement, 7, (formattedNotes as NSString).utf8String, -1, nil)
        bindOptionalText(micAudioPath, at: 8, statement: statement)
        bindOptionalText(systemAudioPath, at: 9, statement: statement)
        sqlite3_bind_int(statement, 10, Int32(wordCount))

        guard sqlite3_step(statement) == SQLITE_DONE else {
            throw lastError(db)
        }
    }

    func dictationStats() throws -> DictationStats {
        let db = try openDatabase()
        defer { sqlite3_close(db) }

        let sql = """
        SELECT
            COUNT(*) AS total_sessions,
            COALESCE(SUM(word_count), 0) AS total_words,
            COALESCE(SUM(duration_seconds), 0) AS total_duration_seconds
        FROM dictations
        """
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else {
            throw lastError(db)
        }
        defer { sqlite3_finalize(statement) }
        guard sqlite3_step(statement) == SQLITE_ROW else {
            return DictationStats(totalWords: 0, totalSessions: 0, averageWordsPerSession: 0, averageWPM: 0, currentStreakDays: 0, longestStreakDays: 0)
        }

        let totalSessions = Int(sqlite3_column_int(statement, 0))
        let totalWords = Int(sqlite3_column_int(statement, 1))
        let totalDuration = sqlite3_column_double(statement, 2)
        let streaks = try dictationStreaks(db: db)
        return DictationStats(
            totalWords: totalWords,
            totalSessions: totalSessions,
            averageWordsPerSession: totalSessions > 0 ? Double(totalWords) / Double(totalSessions) : 0,
            averageWPM: totalDuration > 0 ? Double(totalWords) / (totalDuration / 60.0) : 0,
            currentStreakDays: streaks.current,
            longestStreakDays: streaks.longest
        )
    }

    func meetingStats() throws -> MeetingStats {
        let db = try openDatabase()
        defer { sqlite3_close(db) }

        let sql = """
        SELECT
            COUNT(*) AS total_meetings,
            COALESCE(SUM(word_count), 0) AS total_words,
            COALESCE(SUM(duration_seconds), 0) AS total_duration_seconds
        FROM meetings
        """
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else {
            throw lastError(db)
        }
        defer { sqlite3_finalize(statement) }
        guard sqlite3_step(statement) == SQLITE_ROW else {
            return MeetingStats(totalWords: 0, totalMeetings: 0, averageWPM: 0)
        }

        let totalMeetings = Int(sqlite3_column_int(statement, 0))
        let totalWords = Int(sqlite3_column_int(statement, 1))
        let totalDuration = sqlite3_column_double(statement, 2)
        return MeetingStats(
            totalWords: totalWords,
            totalMeetings: totalMeetings,
            averageWPM: totalDuration > 0 ? Double(totalWords) / (totalDuration / 60.0) : 0
        )
    }

    func clearDictations() throws {
        let db = try openDatabase()
        defer { sqlite3_close(db) }
        try exec("DELETE FROM dictations", db: db)
    }

    func clearMeetings() throws {
        let db = try openDatabase()
        defer { sqlite3_close(db) }
        try exec("DELETE FROM meetings", db: db)
    }

    func updateMeeting(id: Int64, title: String, formattedNotes: String) throws {
        let db = try openDatabase()
        defer { sqlite3_close(db) }
        let sql = "UPDATE meetings SET title = ?, formatted_notes = ? WHERE id = ?"
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else {
            throw lastError(db)
        }
        defer { sqlite3_finalize(statement) }
        sqlite3_bind_text(statement, 1, (title as NSString).utf8String, -1, nil)
        sqlite3_bind_text(statement, 2, (formattedNotes as NSString).utf8String, -1, nil)
        sqlite3_bind_int64(statement, 3, id)
        guard sqlite3_step(statement) == SQLITE_DONE else {
            throw lastError(db)
        }
    }

    func updateMeetingNotes(id: Int64, formattedNotes: String) throws {
        let db = try openDatabase()
        defer { sqlite3_close(db) }
        let sql = "UPDATE meetings SET formatted_notes = ? WHERE id = ?"
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else {
            throw lastError(db)
        }
        defer { sqlite3_finalize(statement) }
        sqlite3_bind_text(statement, 1, (formattedNotes as NSString).utf8String, -1, nil)
        sqlite3_bind_int64(statement, 2, id)
        guard sqlite3_step(statement) == SQLITE_DONE else {
            throw lastError(db)
        }
    }

    func updateMeetingTitle(id: Int64, title: String) throws {
        let db = try openDatabase()
        defer { sqlite3_close(db) }
        let sql = "UPDATE meetings SET title = ? WHERE id = ?"
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else {
            throw lastError(db)
        }
        defer { sqlite3_finalize(statement) }
        sqlite3_bind_text(statement, 1, (title as NSString).utf8String, -1, nil)
        sqlite3_bind_int64(statement, 2, id)
        guard sqlite3_step(statement) == SQLITE_DONE else {
            throw lastError(db)
        }
    }

    // MARK: - Folder CRUD

    @discardableResult
    func createFolder(name: String) throws -> Int64 {
        let db = try openDatabase()
        defer { sqlite3_close(db) }
        let sql = "INSERT INTO meeting_folders (name) VALUES (?)"
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else {
            throw lastError(db)
        }
        defer { sqlite3_finalize(statement) }
        sqlite3_bind_text(statement, 1, (name as NSString).utf8String, -1, nil)
        guard sqlite3_step(statement) == SQLITE_DONE else {
            throw lastError(db)
        }
        return sqlite3_last_insert_rowid(db)
    }

    func renameFolder(id: Int64, name: String) throws {
        let db = try openDatabase()
        defer { sqlite3_close(db) }
        let sql = "UPDATE meeting_folders SET name = ? WHERE id = ?"
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else {
            throw lastError(db)
        }
        defer { sqlite3_finalize(statement) }
        sqlite3_bind_text(statement, 1, (name as NSString).utf8String, -1, nil)
        sqlite3_bind_int64(statement, 2, id)
        guard sqlite3_step(statement) == SQLITE_DONE else {
            throw lastError(db)
        }
    }

    func deleteFolder(id: Int64) throws {
        let db = try openDatabase()
        defer { sqlite3_close(db) }
        // Move meetings to unfiled
        var s1: OpaquePointer?
        guard sqlite3_prepare_v2(db, "UPDATE meetings SET folder_id = NULL WHERE folder_id = ?", -1, &s1, nil) == SQLITE_OK else {
            throw lastError(db)
        }
        sqlite3_bind_int64(s1, 1, id)
        sqlite3_step(s1)
        sqlite3_finalize(s1)
        // Delete folder
        var s2: OpaquePointer?
        guard sqlite3_prepare_v2(db, "DELETE FROM meeting_folders WHERE id = ?", -1, &s2, nil) == SQLITE_OK else {
            throw lastError(db)
        }
        sqlite3_bind_int64(s2, 1, id)
        sqlite3_step(s2)
        sqlite3_finalize(s2)
    }

    func listFolders() throws -> [MeetingFolder] {
        let db = try openDatabase()
        defer { sqlite3_close(db) }
        let sql = "SELECT id, name, created_at FROM meeting_folders ORDER BY sort_order ASC, id ASC"
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else {
            throw lastError(db)
        }
        defer { sqlite3_finalize(statement) }
        var rows: [MeetingFolder] = []
        while sqlite3_step(statement) == SQLITE_ROW {
            rows.append(MeetingFolder(
                id: sqlite3_column_int64(statement, 0),
                name: stringColumn(statement, index: 1),
                createdAt: stringColumn(statement, index: 2)
            ))
        }
        return rows
    }

    func moveMeeting(id: Int64, toFolder folderID: Int64?) throws {
        let db = try openDatabase()
        defer { sqlite3_close(db) }
        let sql = "UPDATE meetings SET folder_id = ? WHERE id = ?"
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else {
            throw lastError(db)
        }
        defer { sqlite3_finalize(statement) }
        if let folderID {
            sqlite3_bind_int64(statement, 1, folderID)
        } else {
            sqlite3_bind_null(statement, 1)
        }
        sqlite3_bind_int64(statement, 2, id)
        guard sqlite3_step(statement) == SQLITE_DONE else {
            throw lastError(db)
        }
    }

    func databasePath() -> URL {
        databaseURL
    }

    static func countWords(in text: String) -> Int {
        text.split(whereSeparator: \.isWhitespace).count
    }

    private func openDatabase() throws -> OpaquePointer? {
        try FileManager.default.createDirectory(
            at: databaseURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        var db: OpaquePointer?
        if sqlite3_open(databaseURL.path, &db) != SQLITE_OK {
            throw lastError(db)
        }
        if sqlite3_exec(db, "PRAGMA journal_mode=WAL", nil, nil, nil) != SQLITE_OK {
            throw lastError(db)
        }
        return db
    }

    private func exec(_ sql: String, db: OpaquePointer?) throws {
        if sqlite3_exec(db, sql, nil, nil, nil) != SQLITE_OK {
            throw lastError(db)
        }
    }

    private func lastError(_ db: OpaquePointer?) -> NSError {
        NSError(
            domain: "MuesliDB",
            code: Int(sqlite3_errcode(db)),
            userInfo: [NSLocalizedDescriptionKey: String(cString: sqlite3_errmsg(db))]
        )
    }

    private func stringColumn(_ statement: OpaquePointer?, index: Int32) -> String {
        guard let pointer = sqlite3_column_text(statement, index) else { return "" }
        return String(cString: pointer)
    }

    private func bindOptionalText(_ value: String?, at index: Int32, statement: OpaquePointer?) {
        if let value {
            sqlite3_bind_text(statement, index, (value as NSString).utf8String, -1, nil)
        } else {
            sqlite3_bind_null(statement, index)
        }
    }

    private func dictationStreaks(db: OpaquePointer?) throws -> (current: Int, longest: Int) {
        let sql = "SELECT DISTINCT date(timestamp) AS used_day FROM dictations ORDER BY used_day ASC"
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else {
            throw lastError(db)
        }
        defer { sqlite3_finalize(statement) }

        var days: [Date] = []
        let formatter = ISO8601DateFormatter()
        while sqlite3_step(statement) == SQLITE_ROW {
            let raw = stringColumn(statement, index: 0)
            if let date = formatter.date(from: "\(raw)T00:00:00Z") {
                days.append(date)
            }
        }
        return Self.computeStreak(days: days)
    }

    private static func computeStreak(days: [Date]) -> (current: Int, longest: Int) {
        let calendar = Calendar.current
        let normalized = days
            .map { calendar.startOfDay(for: $0) }
            .sorted()
        guard !normalized.isEmpty else { return (0, 0) }

        var longest = 1
        var run = 1
        for index in 1..<normalized.count {
            let previous = normalized[index - 1]
            let current = normalized[index]
            if let next = calendar.date(byAdding: .day, value: 1, to: previous), calendar.isDate(next, inSameDayAs: current) {
                run += 1
            } else if !calendar.isDate(previous, inSameDayAs: current) {
                longest = max(longest, run)
                run = 1
            }
        }
        longest = max(longest, run)

        let today = calendar.startOfDay(for: Date())
        let anchor: Date
        if calendar.isDate(normalized.last!, inSameDayAs: today) {
            anchor = today
        } else if let yesterday = calendar.date(byAdding: .day, value: -1, to: today),
                  calendar.isDate(normalized.last!, inSameDayAs: yesterday) {
            anchor = yesterday
        } else {
            return (0, longest)
        }

        var current = 0
        var cursor = anchor
        let set = Set(normalized)
        while set.contains(cursor) {
            current += 1
            guard let previous = calendar.date(byAdding: .day, value: -1, to: cursor) else { break }
            cursor = previous
        }
        return (current, longest)
    }
}
