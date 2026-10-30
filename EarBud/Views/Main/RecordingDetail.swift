import AppKit
import SwiftUI

/// `.detail`: title, actions, player and the timestamped transcript.
struct RecordingDetail: View {
    @Environment(AppModel.self) private var model
    let recording: RecordingItem
    @State private var renaming = false
    @State private var draftTitle = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            PlayerBar(recording: recording)
                .padding(.horizontal, Metrics.detailPaddingH)
            TranscriptView(recording: recording)
        }
        .background(Palette.content)
        .alert("Rename Recording", isPresented: $renaming) {
            TextField("Title", text: $draftTitle)
            Button("Rename") { Task { await model.rename(recording.id, to: draftTitle) } }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Give this recording a title to find it more easily.")
        }
    }

    private var header: some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(Typography.detailTitle)
                    .kerning(-0.22)
                    .foregroundStyle(Palette.label)
                    .textSelection(.enabled)
                Text(subtitle)
                    .font(Typography.detailSubtitle)
                    .foregroundStyle(Palette.label2)
            }
            Spacer()
            HStack(spacing: 2) {
                Button {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(model.transcriptText(), forType: .string)
                } label: {
                    Image(systemName: "doc.on.doc")
                }
                .help("Copy transcript")
                .disabled(model.segments.isEmpty)

                ShareLink(item: model.transcriptText(timestamps: true), subject: Text(title)) {
                    Image(systemName: "square.and.arrow.up")
                }
                .help("Share transcript")
                .disabled(model.segments.isEmpty)

                Menu {
                    RecordingActionsMenu(recording: recording, onRename: startRename)
                } label: {
                    Image(systemName: "ellipsis.circle")
                }
                .menuIndicator(.hidden)
                .help("More")
            }
            .buttonStyle(IconButtonStyle())
            .menuStyle(.borderlessButton)
            .fixedSize()
        }
        .padding(.horizontal, Metrics.detailPaddingH)
        .padding(.top, 22)
        .padding(.bottom, 14)
    }

    private func startRename() {
        draftTitle = recording.title ?? ""
        renaming = true
    }

    private var title: String {
        if let title = recording.title, !recording.isUntitled { return title }
        return model.formatting.untitledHeading(recording.recordedAt, now: model.now())
    }

    private var subtitle: String {
        let f = model.formatting
        var parts = [f.day(recording.recordedAt, now: model.now()), f.time(recording.recordedAt), f.spokenDuration(recording.duration)]
        if let copied = recording.copiedAt, model.now().timeIntervalSince(copied) < 3_600 {
            let ago = f.ago(copied, now: model.now())
            parts.append("Copied \(ago)")
        }
        return parts.joined(separator: " · ")
    }
}

/// Rename, Show in Finder, Export and Delete: shared by the "more" button and the list's context menu.
struct RecordingActionsMenu: View {
    @Environment(AppModel.self) private var model
    let recording: RecordingItem
    var onRename: (() -> Void)? = nil

    var body: some View {
        if let onRename {
            Button("Rename…", action: onRename)
        }
        Button("Show in Finder") { Task { await model.showInFinder(recording.id) } }
        Button("Export Transcript…") { Task { await exportTranscript() } }
            .disabled(!recording.transcript.isFinished)
        if case .failed = recording.transcript {
            Button("Try Transcribing Again") { model.retryTranscription(recording.id) }
        }
        Divider()
        Button("Move to Recently Deleted", role: .destructive) { Task { await model.moveToTrash(recording.id) } }
    }

    @MainActor
    private func exportTranscript() async {
        if model.selectedID != recording.id { await model.select(recording.id) }
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.plainText]
        let stamp = recording.recordedAt.formatted(.iso8601.year().month().day().dateSeparator(.dash).time(includingFractionalSeconds: false).timeSeparator(.omitted))
        panel.nameFieldStringValue = "EarBud \(stamp).txt"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        let heading = recording.title ?? model.formatting.untitledHeading(recording.recordedAt, now: model.now())
        let text = heading + "\n\n" + model.transcriptText(timestamps: true) + "\n"
        try? text.write(to: url, atomically: true, encoding: .utf8)
    }
}

/// `.player`: back 15, play/pause, forward 15, waveform scrubber, time and speed.
struct PlayerBar: View {
    @Environment(AppModel.self) private var model
    let recording: RecordingItem

    var body: some View {
        let player = model.player
        HStack(spacing: 14) {
            Button { player.skip(by: -15) } label: {
                Image(systemName: "gobackward.15").font(.system(size: 17))
            }
            .buttonStyle(.plain)
            .foregroundStyle(Palette.label2)
            .help("Back 15 seconds")

            Button { player.togglePlay() } label: {
                Image(systemName: player.isPlaying ? "pause.fill" : "play.fill")
                    .font(.system(size: 15))
                    .offset(x: player.isPlaying ? 0 : 1)
                    .foregroundStyle(.white)
                    .frame(width: Metrics.playButton, height: Metrics.playButton)
                    .background(Circle().fill(Palette.accent).shadow(color: .black.opacity(0.15), radius: 1, y: 1))
            }
            .buttonStyle(.plain)
            .help(player.isPlaying ? "Pause" : "Play")
            .accessibilityLabel(player.isPlaying ? "Pause" : "Play")

            Button { player.skip(by: 15) } label: {
                Image(systemName: "goforward.15").font(.system(size: 17))
            }
            .buttonStyle(.plain)
            .foregroundStyle(Palette.label2)
            .help("Forward 15 seconds")

            WaveformScrubber(seed: recording.waveformSeed, progress: player.progress, isEnabled: player.isReady) { fraction in
                player.seek(fraction: fraction)
            }

            Text("\(model.formatting.clock(player.currentTime)) / \(model.formatting.clock(recording.duration))")
                .font(Typography.playerTime)
                .foregroundStyle(Palette.label2)
                .frame(minWidth: 82)

            SpeedPicker(rate: Binding(get: { player.rate }, set: { player.rate = $0 }))
        }
        .disabled(!player.isReady)
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .softCard(radius: Metrics.playerRadius)
    }
}

/// `.seg`: 1× / 1.5× / 2×.
struct SpeedPicker: View {
    @Binding var rate: Float

    var body: some View {
        HStack(spacing: 0) {
            ForEach(PlaybackController.speeds, id: \.self) { speed in
                let on = speed == rate
                Button { rate = speed } label: {
                    Text(label(speed))
                        .font(Typography.speed)
                        .foregroundStyle(Palette.label)
                        .padding(.horizontal, 9)
                        .frame(height: 20)
                        .background {
                            if on {
                                RoundedRectangle(cornerRadius: 5, style: .continuous).fill(Palette.controlOn)
                                    .shadow(color: .black.opacity(0.2), radius: 0.75, y: 0.5)
                            }
                        }
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Speed \(label(speed))")
                .accessibilityAddTraits(on ? .isSelected : [])
            }
        }
        .padding(2)
        .background(RoundedRectangle(cornerRadius: 7, style: .continuous).fill(Palette.fill2))
        .fixedSize()
    }

    private func label(_ speed: Float) -> String {
        speed == speed.rounded() ? "\(Int(speed))×" : "\(speed.formatted())×"
    }
}
