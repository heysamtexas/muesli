import SwiftUI

struct MeetingDetailView: View {
    let meeting: MeetingRecord?
    let controller: MuesliController
    let appState: AppState
    @State private var isSummarizing = false

    var body: some View {
        if let meeting {
            VStack(alignment: .leading, spacing: 0) {
                header(meeting)

                Divider()
                    .background(MuesliTheme.surfaceBorder)

                if isRawTranscript(meeting) {
                    transcriptCTA
                }

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
        VStack(alignment: .leading, spacing: MuesliTheme.spacing8) {
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
            }

            HStack(spacing: MuesliTheme.spacing8) {
                iconButton("doc.on.doc", label: "Copy notes") {
                    controller.copyToClipboard(notesContent(meeting))
                }
                iconButton("text.quote", label: "Copy transcript") {
                    controller.copyToClipboard(meeting.rawTranscript)
                }
                if isSummarizing {
                    HStack(spacing: 6) {
                        ProgressView()
                            .controlSize(.small)
                        Text("Summarizing...")
                            .font(.system(size: 11))
                            .foregroundStyle(MuesliTheme.textTertiary)
                    }
                    .padding(.horizontal, MuesliTheme.spacing8)
                } else {
                    iconButton("sparkles", label: "Re-summarize") {
                        isSummarizing = true
                        controller.resummarize(meeting: meeting) {
                            isSummarizing = false
                        }
                    }
                }
            }
        }
        .padding(.horizontal, MuesliTheme.spacing24)
        .padding(.vertical, MuesliTheme.spacing16)
    }

    @ViewBuilder
    private func iconButton(_ systemImage: String, label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 4) {
                Image(systemName: systemImage)
                    .font(.system(size: 10))
                Text(label)
                    .font(.system(size: 11, weight: .medium))
            }
            .foregroundStyle(MuesliTheme.textSecondary)
            .padding(.horizontal, MuesliTheme.spacing8)
            .padding(.vertical, 5)
            .background(MuesliTheme.surfacePrimary)
            .clipShape(RoundedRectangle(cornerRadius: MuesliTheme.cornerSmall))
            .overlay(
                RoundedRectangle(cornerRadius: MuesliTheme.cornerSmall)
                    .strokeBorder(MuesliTheme.surfaceBorder, lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }

    private var transcriptCTA: some View {
        HStack(spacing: MuesliTheme.spacing8) {
            if hasApiKey {
                Image(systemName: "sparkles")
                    .foregroundStyle(MuesliTheme.accent)
                Text("Click Re-summarize to generate AI meeting notes and title from this transcript")
                    .font(MuesliTheme.callout())
                    .foregroundStyle(MuesliTheme.textSecondary)
            } else {
                Image(systemName: "key.fill")
                    .foregroundStyle(MuesliTheme.accent)
                Text("Add your API key in Settings to generate meeting notes")
                    .font(MuesliTheme.callout())
                    .foregroundStyle(MuesliTheme.textSecondary)
                Spacer()
                Button("Open Settings") {
                    controller.openHistoryWindow(tab: .settings)
                }
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(MuesliTheme.accent)
                .buttonStyle(.plain)
            }
        }
        .padding(MuesliTheme.spacing12)
        .background(MuesliTheme.accent.opacity(0.08))
        .clipShape(RoundedRectangle(cornerRadius: MuesliTheme.cornerSmall))
        .padding(.horizontal, MuesliTheme.spacing24)
        .padding(.top, MuesliTheme.spacing12)
    }

    private var hasApiKey: Bool {
        let config = appState.config
        if appState.selectedMeetingSummaryBackend == .openAI {
            return !config.openAIAPIKey.isEmpty || ProcessInfo.processInfo.environment["OPENAI_API_KEY"] != nil
        } else {
            return !config.openRouterAPIKey.isEmpty || ProcessInfo.processInfo.environment["OPENROUTER_API_KEY"] != nil
        }
    }

    private func isRawTranscript(_ meeting: MeetingRecord) -> Bool {
        meeting.formattedNotes.isEmpty || meeting.formattedNotes.contains("## Raw Transcript")
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
