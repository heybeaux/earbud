import SwiftUI

/// `.listcol`: recordings grouped by day, newest first.
struct RecordingList: View {
    @Environment(AppModel.self) private var model
    @FocusState private var focused: Bool

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0) {
                    if model.sync != .idle {
                        SyncCard()
                    }
                    if model.isSearching {
                        SearchResultsBar()
                    }
                    ForEach(model.listGroups) { group in
                        DayHeader(title: group.title, count: group.items.count)
                        ForEach(Array(group.items.enumerated()), id: \.element.id) { index, entry in
                            let previous = index > 0 ? group.items[index - 1].id : nil
                            RecordingRow(
                                entry: entry, query: model.activeQuery,
                                isSelected: entry.id == model.selectedID,
                                showsSeparator: index > 0 && previous != model.selectedID && entry.id != model.selectedID)
                            .id(entry.id)
                            .onTapGesture { model.choose(entry.id) }
                        }
                    }
                    if model.isSearching && model.searchResults?.isEmpty == true {
                        Text("Try a different word, or check the spelling.")
                            .font(Typography.callout)
                            .foregroundStyle(Palette.label3)
                            .padding(.horizontal, Metrics.dayPaddingH)
                            .padding(.top, 6)
                    }
                }
                .padding(.bottom, 12)
            }
            .onChange(of: model.selectedID) { _, id in
                guard let id else { return }
                withAnimation(.easeOut(duration: 0.15)) { proxy.scrollTo(id) }
            }
        }
        .background(Palette.content)
        .focusable()
        .focused($focused)
        .focusEffectDisabled()
        .onKeyPress(.downArrow) { model.selectAdjacent(1); return .handled }
        .onKeyPress(.upArrow) { model.selectAdjacent(-1); return .handled }
        .onKeyPress(.space) { model.player.togglePlay(); return .handled }
        .accessibilityLabel("Recordings")
    }
}

/// `.day`: "Today 3".
struct DayHeader: View {
    var title: String
    var count: Int

    var body: some View {
        HStack {
            Text(title).font(Typography.dayHeader).foregroundStyle(Palette.label)
            Spacer()
            Text("\(count)").font(Typography.dayCount).foregroundStyle(Palette.label3)
        }
        .padding(.horizontal, Metrics.dayPaddingH)
        .padding(.top, 14)
        .padding(.bottom, 6)
        .accessibilityAddTraits(.isHeader)
    }
}

/// `.resbar`: "3 recordings mention “Powell River”".
struct SearchResultsBar: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        let count = model.searchResults?.count ?? 0
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass").font(.system(size: 11))
            Text(text(count))
        }
        .font(Typography.footnote)
        .foregroundStyle(Palette.label2)
        .padding(.horizontal, Metrics.dayPaddingH)
        .padding(.top, 12)
        .padding(.bottom, 2)
    }

    private func text(_ count: Int) -> String {
        let q = "\u{201C}\(model.activeQuery)\u{201D}"
        switch count {
        case 0: return "No recordings mention \(q)"
        case 1: return "1 recording mentions \(q)"
        default: return "\(count) recordings mention \(q)"
        }
    }
}

/// `.rec`: one recording in the list.
struct RecordingRow: View {
    @Environment(AppModel.self) private var model
    var entry: ListEntry
    var query: String
    var isSelected: Bool
    var showsSeparator: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(title)
                    .font(isUntitled ? Typography.rowTitleUntitled : Typography.rowTitle)
                    .foregroundStyle(isSelected ? .white : Palette.label)
                    .lineLimit(1)
                Spacer(minLength: 4)
                Text(meta)
                    .font(Typography.rowMeta)
                    .foregroundStyle(isSelected ? .white : Palette.label2)
                    .lineLimit(1)
            }
            preview
                .font(Typography.rowPreview)
                .lineLimit(2)
                .cssLineHeight(1.35, size: 12.5)
                .frame(maxWidth: .infinity, alignment: .leading)
            if let item {
                HStack(spacing: 8) {
                    SourceBadge(source: item.source, onAccent: isSelected)
                    if item.isTranscriptOnly { TranscriptOnlyPill() }
                }
                .padding(.top, 2)
            }
            status
            if case .recording(_, let info?) = entry {
                Text(info.matchCount == 1 ? "1 match" : "\(info.matchCount) matches")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(isSelected ? .white.opacity(0.75) : Palette.label3)
            }
        }
        .padding(.horizontal, Metrics.rowPaddingH)
        .padding(.top, Metrics.rowPaddingTop)
        .padding(.bottom, Metrics.rowPaddingBottom)
        .background(RoundedRectangle(cornerRadius: Metrics.rowRadius, style: .continuous).fill(isSelected ? Palette.selectedRow : .clear))
        .overlay(alignment: .top) {
            if showsSeparator { Rectangle().fill(Palette.separator).frame(height: Metrics.hairline).padding(.horizontal, 2) }
        }
        .contentShape(Rectangle())
        .padding(.horizontal, Metrics.rowInset)
        .contextMenu { if case .recording(let item, _) = entry { RecordingActionsMenu(recording: item) } }
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(isSelected ? [.isSelected, .isButton] : .isButton)
    }

    private var recordedAt: Date { entry.date }

    private var item: RecordingItem? {
        if case .recording(let item, _) = entry { return item }
        return nil
    }

    private var isUntitled: Bool { item?.isUntitled ?? true }

    private var title: String {
        if let item, let title = item.title, !item.isUntitled { return title }
        return model.formatting.time(recordedAt)
    }

    private var meta: String {
        guard let item else { return "Copying…" }
        let length = model.formatting.clock(item.duration)
        return item.isUntitled ? length : "\(model.formatting.time(item.recordedAt)) · \(length)"
    }

    @ViewBuilder private var preview: some View {
        let mutedColor: Color = isSelected ? .white.opacity(0.85) : Palette.label3
        let textColor: Color = isSelected ? .white.opacity(0.85) : Palette.label2
        switch entry {
        case .copying:
            Text("Coming over from your Fieldy").italic().foregroundStyle(mutedColor)
        case .recording(let item, let info):
            if let info {
                Text(Highlighting.attributed(info.snippet, query: query, onAccent: isSelected)).foregroundStyle(textColor)
            } else {
                switch item.transcript {
                case .noSpeech:
                    Text("No speech detected").italic().foregroundStyle(mutedColor)
                case .failed:
                    Text("Audio is fine. You can still listen.").italic().foregroundStyle(mutedColor)
                default:
                    if let preview = item.preview {
                        Text(preview).foregroundStyle(textColor)
                    } else {
                        Text("Transcript will appear here").italic().foregroundStyle(mutedColor)
                    }
                }
            }
        }
    }

    @ViewBuilder private var status: some View {
        let secondary: Color = isSelected ? .white.opacity(0.9) : Palette.label2
        switch entry {
        case .copying(_, let fraction):
            ProgressBar(value: fraction, height: 4, track: isSelected ? .white.opacity(0.25) : Palette.fill2)
                .frame(width: 120)
                .padding(.top, 4)
        case .recording(let item, nil) where hasStatus(item):
            HStack(spacing: 6) {
                switch item.transcript {
                case .waiting(let position):
                    StatusPill(kind: .waiting, title: "Waiting", onAccent: isSelected)
                    Text(position <= 1 ? "Next in line" : "Number \(position) in line").foregroundStyle(secondary)
                case .transcribing(let progress, _):
                    StatusPill(kind: .running, title: "Transcribing", onAccent: isSelected)
                    ProgressBar(value: progress, height: 4, track: isSelected ? .white.opacity(0.25) : Palette.fill2,
                                tint: isSelected ? .white : Palette.accent)
                        .frame(width: 64)
                    Text("\(Int((progress * 100).rounded()))%").foregroundStyle(secondary)
                case .failed:
                    StatusPill(kind: .failed, title: "Transcription failed", onAccent: isSelected)
                    Spacer()
                    Button("Try again") { model.retryTranscription(item.id) }
                        .buttonStyle(EarBudButtonStyle())
                        .font(.system(size: 11.5))
                        .controlSize(.small)
                case .done where recentlyFinished(item):
                    StatusPill(kind: .done, title: "Done", onAccent: isSelected)
                default:
                    if item.audio == .incomplete {
                        StatusPill(kind: .incomplete, title: "Incomplete", onAccent: isSelected)
                    }
                }
            }
            .font(Typography.rowMeta)
            .padding(.top, 4)
        default:
            EmptyView()
        }
    }

    private func recentlyFinished(_ item: RecordingItem) -> Bool {
        guard let at = item.transcribedAt else { return false }
        return model.now().timeIntervalSince(at) < 600
    }

    private func hasStatus(_ item: RecordingItem) -> Bool {
        switch item.transcript {
        case .waiting, .transcribing, .failed: true
        case .done: recentlyFinished(item) || item.audio == .incomplete
        default: item.audio == .incomplete
        }
    }
}
