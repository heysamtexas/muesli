import SwiftUI

struct MeetingListItemView: View {
    let record: MeetingRecord
    let isSelected: Bool
    let onSelect: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: MuesliTheme.spacing8) {
            Text(record.title)
                .font(MuesliTheme.headline())
                .foregroundStyle(MuesliTheme.textPrimary)
                .lineLimit(2)

            Text(formatMeta())
                .font(MuesliTheme.caption())
                .foregroundStyle(MuesliTheme.textSecondary)

            Text(previewText())
                .font(MuesliTheme.caption())
                .foregroundStyle(MuesliTheme.textTertiary)
                .lineLimit(2)
        }
        .padding(MuesliTheme.spacing16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(isSelected ? MuesliTheme.surfaceSelected : MuesliTheme.backgroundRaised)
        .clipShape(RoundedRectangle(cornerRadius: MuesliTheme.cornerLarge))
        .overlay(
            RoundedRectangle(cornerRadius: MuesliTheme.cornerLarge)
                .strokeBorder(
                    isSelected ? MuesliTheme.accent.opacity(0.35) : MuesliTheme.surfaceBorder,
                    lineWidth: 1
                )
        )
        .contentShape(Rectangle())
        .onTapGesture(perform: onSelect)
    }

    private func formatMeta() -> String {
        let time = formatTime(record.startTime)
        let duration = formatDuration(record.durationSeconds)
        return "\(time)  \u{2022}  \(duration)"
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

    private func previewText() -> String {
        let source = record.formattedNotes.isEmpty ? record.rawTranscript : record.formattedNotes
        let compact = source.split(whereSeparator: \.isWhitespace).joined(separator: " ")
        if compact.count > 88 {
            return String(compact.prefix(85)) + "..."
        }
        return compact
    }
}
