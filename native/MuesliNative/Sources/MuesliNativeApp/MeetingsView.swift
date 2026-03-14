import SwiftUI

struct MeetingsView: View {
    let appState: AppState
    let controller: MuesliController

    var body: some View {
        if appState.meetingRows.isEmpty {
            emptyState
        } else {
            HSplitView {
                meetingList
                    .frame(minWidth: 280, idealWidth: 320, maxWidth: 380)

                MeetingDetailView(
                    meeting: appState.selectedMeeting,
                    controller: controller
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
    }

    @ViewBuilder
    private var emptyState: some View {
        VStack(spacing: MuesliTheme.spacing12) {
            Image(systemName: "person.2.wave.2")
                .font(.system(size: 40, weight: .thin))
                .foregroundStyle(MuesliTheme.textTertiary)
            Text("No meetings yet")
                .font(MuesliTheme.title3())
                .foregroundStyle(MuesliTheme.textSecondary)
            Text("Start a recording from the menu bar to create your first meeting note")
                .font(MuesliTheme.callout())
                .foregroundStyle(MuesliTheme.textTertiary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 300)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    @ViewBuilder
    private var meetingList: some View {
        VStack(alignment: .leading, spacing: MuesliTheme.spacing12) {
            VStack(alignment: .leading, spacing: MuesliTheme.spacing4) {
                Text("Meetings")
                    .font(MuesliTheme.title2())
                    .foregroundStyle(MuesliTheme.textPrimary)
                Text("Chronological notes")
                    .font(MuesliTheme.callout())
                    .foregroundStyle(MuesliTheme.textSecondary)
            }
            .padding(.horizontal, MuesliTheme.spacing16)
            .padding(.top, MuesliTheme.spacing20)

            ScrollView {
                LazyVStack(spacing: MuesliTheme.spacing8) {
                    ForEach(appState.meetingRows) { meeting in
                        MeetingListItemView(
                            record: meeting,
                            isSelected: appState.selectedMeetingID == meeting.id
                                || (appState.selectedMeetingID == nil && meeting.id == appState.meetingRows.first?.id)
                        ) {
                            appState.selectedMeetingID = meeting.id
                        }
                    }
                }
                .padding(.horizontal, MuesliTheme.spacing12)
                .padding(.bottom, MuesliTheme.spacing12)
            }
        }
        .background(MuesliTheme.backgroundDeep)
    }
}
