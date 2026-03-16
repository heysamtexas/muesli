import SwiftUI

struct MeetingsView: View {
    let appState: AppState
    let controller: MuesliController
    @State private var renamingFolderID: Int64?
    @State private var renamingFolderName: String = ""
    @State private var folderToDelete: MeetingFolder?
    @State private var showDeleteConfirmation = false

    private var filteredMeetings: [MeetingRecord] {
        guard let folderID = appState.selectedFolderID else {
            return appState.meetingRows
        }
        return appState.meetingRows.filter { $0.folderID == folderID }
    }

    private var detailMeeting: MeetingRecord? {
        if let id = appState.selectedMeetingID,
           let match = filteredMeetings.first(where: { $0.id == id }) {
            return match
        }
        return filteredMeetings.first
    }

    var body: some View {
        HSplitView {
            sidebar
                .frame(minWidth: 280, idealWidth: 320, maxWidth: 380)

            detailPane
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(MuesliTheme.backgroundBase)
        }
        .onChange(of: appState.selectedFolderID) { _, _ in
            if let selected = appState.selectedMeetingID,
               !filteredMeetings.contains(where: { $0.id == selected }) {
                appState.selectedMeetingID = filteredMeetings.first?.id
            }
        }
    }

    @ViewBuilder
    private var detailPane: some View {
        if filteredMeetings.isEmpty {
            emptyState
        } else {
            MeetingDetailView(
                meeting: detailMeeting,
                controller: controller,
                appState: appState
            )
            .id(detailMeeting?.id)
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

    // MARK: - Sidebar

    @ViewBuilder
    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header with folder create button
            HStack {
                Text("Meetings")
                    .font(MuesliTheme.title2())
                    .foregroundStyle(MuesliTheme.textPrimary)
                Spacer()
                Button(action: createNewFolder) {
                    Image(systemName: "folder.badge.plus")
                        .font(.system(size: 14))
                        .foregroundStyle(MuesliTheme.textSecondary)
                }
                .buttonStyle(.plain)
                .help("New Folder")
            }
            .padding(.horizontal, MuesliTheme.spacing16)
            .padding(.top, MuesliTheme.spacing20)
            .padding(.bottom, MuesliTheme.spacing8)

            // Folder list
            VStack(spacing: 2) {
                folderRow(
                    icon: "tray.2",
                    name: "All Meetings",
                    count: appState.meetingRows.count,
                    isSelected: appState.selectedFolderID == nil
                ) {
                    appState.selectedFolderID = nil
                }

                ForEach(appState.folders) { folder in
                    let count = appState.meetingRows.filter { $0.folderID == folder.id }.count
                    if renamingFolderID == folder.id {
                        folderRenameField(folder: folder)
                    } else {
                        folderRow(
                            icon: "folder",
                            name: folder.name,
                            count: count,
                            isSelected: appState.selectedFolderID == folder.id
                        ) {
                            appState.selectedFolderID = folder.id
                        }
                        .contextMenu {
                            Button("Rename") {
                                renamingFolderID = folder.id
                                renamingFolderName = folder.name
                            }
                            Divider()
                            Button("Delete", role: .destructive) {
                                folderToDelete = folder
                                showDeleteConfirmation = true
                            }
                        }
                    }
                }
            }
            .padding(.horizontal, MuesliTheme.spacing12)
            .padding(.bottom, MuesliTheme.spacing12)

            Divider()
                .background(MuesliTheme.surfaceBorder)

            // Meeting list for selected folder
            ScrollView {
                LazyVStack(spacing: MuesliTheme.spacing8) {
                    ForEach(filteredMeetings) { meeting in
                        MeetingListItemView(
                            record: meeting,
                            isSelected: appState.selectedMeetingID == meeting.id
                                || (appState.selectedMeetingID == nil && meeting.id == filteredMeetings.first?.id),
                            folders: appState.folders,
                            onSelect: { appState.selectedMeetingID = meeting.id },
                            onMove: { folderID in
                                controller.moveMeeting(id: meeting.id, toFolder: folderID)
                            }
                        )
                    }
                }
                .padding(.horizontal, MuesliTheme.spacing12)
                .padding(.vertical, MuesliTheme.spacing12)
            }
        }
        .background(MuesliTheme.backgroundDeep)
        .alert(
            "Delete \"\(folderToDelete?.name ?? "")\"?",
            isPresented: $showDeleteConfirmation
        ) {
            Button("Cancel", role: .cancel) {
                folderToDelete = nil
            }
            Button("Delete", role: .destructive) {
                if let folder = folderToDelete {
                    controller.deleteFolder(id: folder.id)
                }
                folderToDelete = nil
            }
        } message: {
            let count = folderToDelete.map { fid in
                appState.meetingRows.filter { $0.folderID == fid.id }.count
            } ?? 0
            if count > 0 {
                Text("\(count) meeting\(count == 1 ? "" : "s") in this folder will be moved to Unfiled.")
            } else {
                Text("This folder will be permanently removed.")
            }
        }
    }

    // MARK: - Folder Row

    @ViewBuilder
    private func folderRow(icon: String, name: String, count: Int, isSelected: Bool, action: @escaping () -> Void) -> some View {
        HStack(spacing: MuesliTheme.spacing8) {
            Image(systemName: icon)
                .font(.system(size: 13))
                .foregroundStyle(isSelected ? MuesliTheme.accent : MuesliTheme.textSecondary)
                .frame(width: 18)
            Text(name)
                .font(MuesliTheme.callout())
                .foregroundStyle(isSelected ? MuesliTheme.textPrimary : MuesliTheme.textSecondary)
                .lineLimit(1)
            Spacer()
            Text("\(count)")
                .font(MuesliTheme.caption())
                .foregroundStyle(MuesliTheme.textTertiary)
        }
        .padding(.horizontal, MuesliTheme.spacing12)
        .padding(.vertical, 6)
        .background(isSelected ? MuesliTheme.surfaceSelected : Color.clear)
        .clipShape(RoundedRectangle(cornerRadius: MuesliTheme.cornerSmall))
        .contentShape(Rectangle())
        .onTapGesture(perform: action)
    }

    @ViewBuilder
    private func folderRenameField(folder: MeetingFolder) -> some View {
        HStack(spacing: MuesliTheme.spacing8) {
            Image(systemName: "folder")
                .font(.system(size: 13))
                .foregroundStyle(MuesliTheme.accent)
                .frame(width: 18)
            TextField("Folder name", text: $renamingFolderName)
                .font(MuesliTheme.callout())
                .textFieldStyle(.plain)
                .onSubmit {
                    let trimmed = renamingFolderName.trimmingCharacters(in: .whitespacesAndNewlines)
                    if !trimmed.isEmpty {
                        controller.renameFolder(id: folder.id, name: trimmed)
                    }
                    renamingFolderID = nil
                }
        }
        .padding(.horizontal, MuesliTheme.spacing12)
        .padding(.vertical, 6)
        .background(MuesliTheme.surfaceSelected)
        .clipShape(RoundedRectangle(cornerRadius: MuesliTheme.cornerSmall))
    }

    // MARK: - Actions

    private func createNewFolder() {
        if let id = controller.createFolder(name: "New Folder") {
            renamingFolderID = id
            renamingFolderName = "New Folder"
        }
    }
}
