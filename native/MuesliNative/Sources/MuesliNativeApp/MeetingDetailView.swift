import SwiftUI

struct MeetingDetailView: View {
    let meeting: MeetingRecord?
    let controller: MuesliController

    var body: some View {
        if let meeting {
            VStack(alignment: .leading, spacing: 0) {
                header(meeting)

                Divider()
                    .background(MuesliTheme.surfaceBorder)

                MeetingNotesView(markdown: notesContent(meeting))
            }
            .background(MuesliTheme.backgroundBase)
        } else {
            VStack(spacing: MuesliTheme.spacing12) {
                Text("No meeting selected")
                    .font(MuesliTheme.title3())
                    .foregroundStyle(MuesliTheme.textSecondary)
                Text("Select a meeting from the list to view its notes")
                    .font(MuesliTheme.callout())
                    .foregroundStyle(MuesliTheme.textTertiary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(MuesliTheme.backgroundBase)
        }
    }

    @ViewBuilder
    private func header(_ meeting: MeetingRecord) -> some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: MuesliTheme.spacing4) {
                Text(meeting.title)
                    .font(.system(size: 26, weight: .bold))
                    .foregroundStyle(MuesliTheme.textPrimary)

                Text(formatMeta(meeting))
                    .font(MuesliTheme.callout())
                    .foregroundStyle(MuesliTheme.textSecondary)
            }

            Spacer()

            HStack(spacing: MuesliTheme.spacing8) {
                pillButton("Copy notes") {
                    controller.copyToClipboard(notesContent(meeting))
                }
                pillButton("Copy transcript") {
                    controller.copyToClipboard(meeting.rawTranscript)
                }
            }
        }
        .padding(.horizontal, MuesliTheme.spacing24)
        .padding(.vertical, MuesliTheme.spacing20)
    }

    @ViewBuilder
    private func pillButton(_ title: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(MuesliTheme.textPrimary)
                .padding(.horizontal, MuesliTheme.spacing12)
                .padding(.vertical, MuesliTheme.spacing8)
                .background(MuesliTheme.surfacePrimary)
                .clipShape(RoundedRectangle(cornerRadius: MuesliTheme.cornerMedium))
                .overlay(
                    RoundedRectangle(cornerRadius: MuesliTheme.cornerMedium)
                        .strokeBorder(MuesliTheme.surfaceBorder, lineWidth: 1)
                )
        }
        .buttonStyle(.plain)
    }

    private func notesContent(_ meeting: MeetingRecord) -> String {
        if meeting.formattedNotes.isEmpty {
            return "# \(meeting.title)\n\n## Raw Transcript\n\n\(meeting.rawTranscript)"
        }
        return meeting.formattedNotes
    }

    private func formatMeta(_ meeting: MeetingRecord) -> String {
        let time = formatTime(meeting.startTime)
        let duration = formatDuration(meeting.durationSeconds)
        return "\(time)  \u{2022}  \(duration)  \u{2022}  \(meeting.wordCount) words"
    }

    private func formatTime(_ raw: String) -> String {
        let clean = raw.replacingOccurrences(of: "T", with: " ")
        if clean.count > 16 {
            return String(clean.prefix(16))
        }
        return clean
    }

    private func formatDuration(_ seconds: Double) -> String {
        let rounded = Int(seconds.rounded())
        if rounded >= 3600 {
            return "\(rounded / 3600)h \((rounded % 3600) / 60)m"
        }
        if rounded >= 60 {
            let m = rounded / 60
            let s = rounded % 60
            return s == 0 ? "\(m)m" : "\(m)m \(s)s"
        }
        return "\(rounded)s"
    }
}
