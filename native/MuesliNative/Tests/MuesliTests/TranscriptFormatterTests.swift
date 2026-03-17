import Testing
import Foundation
import MuesliCore
@testable import MuesliNativeApp

@Suite("TranscriptFormatter")
struct TranscriptFormatterTests {

    @Test("merges mic and system segments sorted by time")
    func mergesSortedByTime() {
        let meetingStart = Date(timeIntervalSince1970: 0)
        let mic = [
            SpeechSegment(start: 0.0, end: 2.0, text: "Hello from mic"),
            SpeechSegment(start: 5.0, end: 7.0, text: "More from mic"),
        ]
        let system = [
            SpeechSegment(start: 3.0, end: 4.5, text: "Hello from system"),
        ]
        let result = TranscriptFormatter.merge(
            micSegments: mic, systemSegments: system, meetingStart: meetingStart
        )
        let lines = result.components(separatedBy: "\n")
        #expect(lines.count == 3)
        #expect(lines[0].contains("You: Hello from mic"))
        #expect(lines[1].contains("Others: Hello from system"))
        #expect(lines[2].contains("You: More from mic"))
    }

    @Test("includes timestamp in HH:mm:ss format")
    func timestampFormat() {
        var components = DateComponents()
        components.year = 2025; components.month = 1; components.day = 1
        components.hour = 14; components.minute = 30; components.second = 0
        let meetingStart = Calendar.current.date(from: components)!
        let mic = [SpeechSegment(start: 65.0, end: 67.0, text: "Test")]
        let result = TranscriptFormatter.merge(
            micSegments: mic, systemSegments: [], meetingStart: meetingStart
        )
        #expect(result.contains("[14:31:05]"))
    }

    @Test("handles empty segments")
    func emptySegments() {
        let result = TranscriptFormatter.merge(
            micSegments: [], systemSegments: [], meetingStart: Date()
        )
        #expect(result.isEmpty)
    }

    @Test("handles mic-only meeting")
    func micOnly() {
        let mic = [SpeechSegment(start: 0.0, end: 1.0, text: "Solo speaker")]
        let result = TranscriptFormatter.merge(
            micSegments: mic, systemSegments: [], meetingStart: Date(timeIntervalSince1970: 0)
        )
        #expect(result.contains("You: Solo speaker"))
        #expect(!result.contains("Others"))
    }

    @Test("handles system-only meeting")
    func systemOnly() {
        let system = [SpeechSegment(start: 0.0, end: 1.0, text: "Remote speaker")]
        let result = TranscriptFormatter.merge(
            micSegments: [], systemSegments: system, meetingStart: Date(timeIntervalSince1970: 0)
        )
        #expect(result.contains("Others: Remote speaker"))
        #expect(!result.contains("You"))
    }
}
