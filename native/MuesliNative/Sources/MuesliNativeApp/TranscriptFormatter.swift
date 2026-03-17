import Foundation
import MuesliCore

enum TranscriptFormatter {
    static func merge(micSegments: [SpeechSegment], systemSegments: [SpeechSegment], meetingStart: Date) -> String {
        let taggedMic = micSegments.map { TaggedSegment(segment: $0, speaker: "You") }
        let taggedSystem = systemSegments.map { TaggedSegment(segment: $0, speaker: "Others") }
        let tagged = (taggedMic + taggedSystem).sorted { $0.segment.start < $1.segment.start }

        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = .current
        formatter.dateFormat = "HH:mm:ss"

        return tagged.map { taggedSegment in
            let timestamp = meetingStart.addingTimeInterval(taggedSegment.segment.start)
            return "[\(formatter.string(from: timestamp))] \(taggedSegment.speaker): \(taggedSegment.segment.text)"
        }.joined(separator: "\n")
    }
}

private struct TaggedSegment {
    let segment: SpeechSegment
    let speaker: String
}
