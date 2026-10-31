import SwiftUI

/// Sync History: each sync, newest first. No mockup; built from the shared form styles.
struct SyncHistoryPane: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                let groups = LibraryGrouping.byDay(model.history, date: \.startedAt, now: model.now(), formatting: model.formatting)
                if groups.isEmpty {
                    ContentUnavailableMessage(symbol: "clock", title: "No syncs yet",
                                              message: "Each time you sync, EarBud notes what came over from your Fieldy.")
                }
                ForEach(groups) { group in
                    FormSection(title: group.title) {
                        FormGroup {
                            ForEach(Array(group.items.enumerated()), id: \.element.id) { index, entry in
                                if index > 0 { FormDivider() }
                                SyncHistoryRow(entry: entry)
                            }
                        }
                    }
                }
            }
            .frame(maxWidth: 640, alignment: .leading)
            .padding(.horizontal, 28)
            .padding(.vertical, 22)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .background(Palette.content)
    }
}

private struct SyncHistoryRow: View {
    @Environment(AppModel.self) private var model
    var entry: SyncHistoryItem

    var body: some View {
        FormRow(title: title, detail: detail, alignTop: entry.message != nil, titleWeight: .medium) {
            Image(systemName: symbol)
                .font(.system(size: 15))
                .foregroundStyle(tint)
                .frame(width: 20)
        } trailing: {
            Text(model.formatting.time(entry.startedAt))
                .font(Typography.caption)
                .foregroundStyle(Palette.label2)
        }
    }

    private var title: String {
        switch entry.result {
        case .success: entry.recordingCount == 1 ? "1 recording copied" : "\(entry.recordingCount) recordings copied"
        case .nothingNew: "No new recordings"
        case .interrupted: "Sync stopped part way"
        case .failed: "Sync didn't finish"
        }
    }

    private var detail: String? {
        if let message = entry.message { return message }
        guard entry.recordingCount > 0 else { return nil }
        return "\(model.formatting.spokenDuration(entry.totalSeconds)) of audio · \(model.formatting.bytes(entry.bytes))"
    }

    private var symbol: String {
        switch entry.result {
        case .success: "checkmark.circle.fill"
        case .nothingNew: "circle.dashed"
        case .interrupted, .failed: "exclamationmark.triangle.fill"
        }
    }

    private var tint: Color {
        switch entry.result {
        case .success: Palette.green
        case .nothingNew: Palette.label3
        case .interrupted, .failed: Palette.orange
        }
    }
}

/// Recently Deleted (mockup 27): deleted audio kept apart from fully deleted
/// recordings, each for 30 days, with Restore / Restore Audio, and Empty Recently Deleted…
struct RecentlyDeletedPane: View {
    @Environment(AppModel.self) private var model
    @State private var confirmingEmpty = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                if model.deleted.isEmpty && model.deletedAudio.isEmpty {
                    ContentUnavailableMessage(symbol: "trash", title: "Nothing here",
                                              message: "Recordings and audio you delete stay here for 30 days, in case you change your mind.")
                } else {
                    if !model.deletedAudio.isEmpty {
                        FormSection(title: "Deleted audio",
                                    footer: "The transcripts are still in your library, marked Transcript only. Restore the audio to play or export it again.") {
                            FormGroup {
                                ForEach(Array(model.deletedAudio.enumerated()), id: \.element.id) { index, item in
                                    if index > 0 { FormDivider() }
                                    DeletedAudioRow(item: item)
                                }
                            }
                        }
                    }
                    if !model.deleted.isEmpty {
                        FormSection(title: "Deleted recordings", footer: "Audio and transcript together. EarBud removes these for good 30 days after you delete them.") {
                            FormGroup {
                                ForEach(Array(model.deleted.enumerated()), id: \.element.id) { index, item in
                                    if index > 0 { FormDivider() }
                                    DeletedRow(item: item)
                                }
                            }
                        }
                    }
                }
            }
            .frame(maxWidth: 640, alignment: .leading)
            .padding(.horizontal, 28)
            .padding(.vertical, 22)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .background(Palette.content)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button("Empty Recently Deleted…") { confirmingEmpty = true }
                    .disabled(model.deleted.isEmpty && model.deletedAudio.isEmpty)
            }
        }
        .confirmationDialog("Empty Recently Deleted?", isPresented: $confirmingEmpty, titleVisibility: .visible) {
            Button("Empty Recently Deleted", role: .destructive) { Task { await model.emptyRecentlyDeleted() } }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This removes the deleted audio and recordings for good. You can't undo this.")
        }
    }
}

private struct DeletedRow: View {
    @Environment(AppModel.self) private var model
    var item: RecordingItem

    var body: some View {
        let f = model.formatting
        let now = model.now()
        let title = item.isUntitled ? f.untitledHeading(item.recordedAt, now: now) : (item.title ?? "")
        let left = item.deletedAt.map { max(0, 30 - Int(now.timeIntervalSince($0) / 86_400)) } ?? 30
        let detail = item.transcript == .noSpeech
            ? "\(sourceLabel) · \(f.clock(item.duration)) · No speech detected"
            : "\(sourceLabel) · \(f.spokenDuration(item.duration)) · removed for good in \(left) days"
        FormRow(title: title, detail: detail, titleWeight: .medium) {
            Image(systemName: "trash")
                .foregroundStyle(Palette.label3)
                .frame(width: 20)
        } trailing: {
            Button("Restore") { Task { await model.restore(item.id) } }
                .buttonStyle(EarBudButtonStyle())
        }
    }

    private var sourceLabel: String {
        switch item.source {
        case .fieldy: "Fieldy"
        case .imported(let name): name
        case .microphone(let name): name
        }
    }
}

private struct DeletedAudioRow: View {
    @Environment(AppModel.self) private var model
    var item: RecordingItem

    var body: some View {
        let f = model.formatting
        let now = model.now()
        let title = item.isUntitled ? f.untitledHeading(item.recordedAt, now: now) : (item.title ?? "")
        let left = item.audioDeletedAt.map { max(0, 30 - Int(now.timeIntervalSince($0) / 86_400)) } ?? 30
        let sizePart = item.audioBytes.map { " · \(f.bytes($0)) of audio" } ?? ""
        FormRow(title: title, detail: "\(sourceLabel) · \(f.spokenDuration(item.duration))\(sizePart)", titleWeight: .medium) {
            Image(systemName: "waveform")
                .foregroundStyle(Palette.accent)
                .frame(width: 20, height: 20)
                .background(Circle().fill(Palette.accentTint))
        } trailing: {
            HStack(spacing: 10) {
                Text("\(left) days left").font(Typography.caption).foregroundStyle(Palette.label2)
                Button("Restore Audio") { Task { await model.restoreAudio(item.id) } }
                    .buttonStyle(EarBudButtonStyle())
            }
        }
    }

    private var sourceLabel: String {
        switch item.source {
        case .fieldy: "Fieldy"
        case .imported(let name): name
        case .microphone(let name): name
        }
    }
}
