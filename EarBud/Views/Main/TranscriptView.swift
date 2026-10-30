import SwiftUI

/// `.tx`: the timestamped transcript. Click a line to play from there.
struct TranscriptView: View {
    @Environment(AppModel.self) private var model
    let recording: RecordingItem

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            ScrollViewReader { proxy in
                ScrollView {
                    VStack(alignment: .leading, spacing: 0) {
                        content
                    }
                    .padding(.horizontal, 20)
                    .padding(.bottom, 24)
                }
                .onChange(of: focusSegment) { _, position in
                    guard let position else { return }
                    withAnimation(.easeInOut(duration: 0.25)) { proxy.scrollTo(position, anchor: UnitPoint(x: 0, y: 0.3)) }
                }
                .onAppear {
                    if let position = focusSegment { proxy.scrollTo(position, anchor: UnitPoint(x: 0, y: 0.3)) }
                }
            }
        }
        .padding(.top, 16)
    }

    // MARK: Header

    private var header: some View {
        HStack(spacing: 8) {
            Text("TRANSCRIPT")
                .font(Typography.transcriptHeader)
                .kerning(0.44)
                .foregroundStyle(Palette.label3)
            Spacer()
            if model.isSearching, !model.transcriptMatches.isEmpty {
                HStack(spacing: 2) {
                    Text("Match \(model.matchIndex + 1) of \(model.transcriptMatches.count)")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(Palette.label2)
                    Button { model.showMatch(offset: -1) } label: { Image(systemName: "chevron.up").font(.system(size: 11, weight: .semibold)) }
                        .help("Previous match")
                    Button { model.showMatch(offset: 1) } label: { Image(systemName: "chevron.down").font(.system(size: 11, weight: .semibold)) }
                        .help("Next match")
                }
                .buttonStyle(IconButtonStyle(size: 22))
            } else if recording.transcript == .done, !model.segments.isEmpty {
                Text("Click a line to play from there")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(Palette.label3)
            }
        }
        .padding(.horizontal, 32)
        .padding(.top, 4)
        .padding(.bottom, 10)
        .frame(minHeight: 30)
    }

    // MARK: Content

    @ViewBuilder private var content: some View {
        switch recording.transcript {
        case .done:
            lines
        case .transcribing(let progress, let secondsLeft):
            lines
            GhostLine(start: model.segments.last?.end ?? 0)
            TranscribingCard(progress: progress, secondsLeft: secondsLeft)
        case .waiting(let position):
            TranscriptNotice(symbol: "clock", title: "Waiting to make the transcript",
                             message: (position <= 1 ? "Next in line. " : "Number \(position) in line. ") + "You can listen while you wait. Nothing leaves your Mac.")
        case .noSpeech:
            TranscriptNotice(symbol: "waveform.slash", title: "No speech detected",
                             message: "EarBud listened to this recording and didn't hear anyone talking.")
        case .failed:
            TranscriptNotice(symbol: "exclamationmark.triangle.fill", title: "EarBud couldn't make a transcript",
                             message: "The audio is fine. You can still listen.", tint: Palette.orange) {
                Button("Try again") { model.retryTranscription(recording.id) }
                    .buttonStyle(EarBudButtonStyle())
            }
        case .none:
            TranscriptNotice(symbol: "text.bubble", title: "No transcript yet",
                             message: "Transcripts start once a speech model is installed. You can choose one in Settings.")
        }
    }

    private var lines: some View {
        ForEach(model.segments) { segment in
            SegmentRow(segment: segment, style: style(for: segment), query: model.activeQuery,
                       currentOccurrence: model.currentMatch?.segmentPosition == segment.position ? model.currentMatch?.occurrence : nil)
                .id(segment.position)
                .onTapGesture { model.player.play(from: segment.start) }
        }
    }

    // MARK: Playback position

    private var engaged: Bool {
        model.player.loadedID == recording.id && (model.player.isPlaying || model.player.currentTime > 0)
    }

    private var playingSegment: Int? {
        guard engaged else { return nil }
        return TranscriptTiming.currentSegment(at: model.player.currentTime, in: model.segments)
    }

    /// The line to keep in view: the current search match, or the playing line.
    private var focusSegment: Int? {
        model.currentMatch?.segmentPosition ?? (model.player.isPlaying ? playingSegment : nil)
    }

    private func style(for segment: TranscriptSegment) -> SegmentRow.Style {
        if let match = model.currentMatch {
            return segment.position == match.segmentPosition ? .current : .upcoming
        }
        guard let playing = playingSegment else { return engaged ? .upcoming : .plain }
        if segment.position < playing { return .past }
        return segment.position == playing ? .current : .upcoming
    }
}

/// `.segm`: one transcript line.
struct SegmentRow: View {
    enum Style { case plain, past, current, upcoming }

    @Environment(AppModel.self) private var model
    var segment: TranscriptSegment
    var style: Style
    var query: String
    var currentOccurrence: Int?
    @State private var hovering = false

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Text(model.formatting.timestamp(segment.start))
                .font(Typography.timestamp)
                .foregroundStyle(timestampColor)
                .frame(width: Metrics.timestampColumn, alignment: .leading)
            Text(Highlighting.attributed(segment.text, query: query, current: currentOccurrence))
                .font(Typography.segment)
                .cssLineHeight(1.5, size: 14)
                .foregroundStyle(style == .past ? Palette.label2 : Palette.label)
                .frame(maxWidth: .infinity, alignment: .leading)
                .textSelection(.enabled)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(RoundedRectangle(cornerRadius: Metrics.segmentRadius, style: .continuous).fill(background))
        .contentShape(Rectangle())
        .onHover { hovering = $0 }
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isButton)
        .accessibilityHint("Plays from \(model.formatting.timestamp(segment.start))")
    }

    private var background: Color {
        if style == .current { return Palette.currentSegment }
        return hovering ? Palette.fill : .clear
    }

    private var timestampColor: Color {
        switch style {
        case .plain, .current: Palette.accent
        case .past, .upcoming: Palette.label3
        }
    }
}

/// `.segm.ghost`: the line being worked on.
struct GhostLine: View {
    @Environment(AppModel.self) private var model
    var start: TimeInterval

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Text(model.formatting.timestamp(start))
                .font(Typography.timestamp)
                .foregroundStyle(Palette.label3)
                .frame(width: Metrics.timestampColumn, alignment: .leading)
            VStack(alignment: .leading, spacing: 11) {
                GeometryReader { geo in
                    VStack(alignment: .leading, spacing: 11) {
                        Capsule().fill(Palette.fill2).frame(width: geo.size.width * 0.92, height: 9)
                        Capsule().fill(Palette.fill2).frame(width: geo.size.width * 0.58, height: 9)
                    }
                }
                .frame(height: 29)
            }
            .padding(.top, 4)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .accessibilityHidden(true)
    }
}

/// `.txwork`: "Making the transcript on this Mac".
struct TranscribingCard: View {
    @Environment(AppModel.self) private var model
    var progress: Double
    var secondsLeft: TimeInterval?

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Spinner(size: 16)
                .padding(.top, 1)
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text("Making the transcript on this Mac")
                        .font(Typography.bodySemibold)
                        .foregroundStyle(Palette.label)
                    Spacer()
                    Text(percentText)
                        .font(Typography.footnote)
                        .foregroundStyle(Palette.label2)
                }
                ProgressBar(value: progress, height: 4)
                Text("You can listen while you wait. Lines appear as they're ready, and nothing leaves your Mac.")
                    .font(Typography.rowMeta)
                    .foregroundStyle(Palette.label2)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, 3)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .softCard(radius: 10)
        .padding(.horizontal, 12)
        .padding(.top, 6)
    }

    private var percentText: String {
        let pct = "\(Int((progress * 100).rounded()))%"
        guard let secondsLeft else { return pct }
        return "\(pct) · \(model.formatting.timeLeft(secondsLeft))"
    }
}

/// A transcript-area message: waiting, no speech, failed, no model.
struct TranscriptNotice<Actions: View>: View {
    var symbol: String
    var title: String
    var message: String
    var tint: Color = Palette.accent
    @ViewBuilder var actions: Actions

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: symbol)
                .font(.system(size: 16))
                .foregroundStyle(tint)
                .frame(width: 18)
            VStack(alignment: .leading, spacing: 4) {
                Text(title).font(Typography.bodySemibold).foregroundStyle(Palette.label)
                Text(message).font(Typography.callout).foregroundStyle(Palette.label2)
                    .fixedSize(horizontal: false, vertical: true)
                actions.padding(.top, 6)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .softCard(radius: 10)
        .padding(.horizontal, 12)
        .padding(.top, 6)
    }
}

extension TranscriptNotice where Actions == EmptyView {
    init(symbol: String, title: String, message: String, tint: Color = Palette.accent) {
        self.init(symbol: symbol, title: title, message: message, tint: tint) { EmptyView() }
    }
}
