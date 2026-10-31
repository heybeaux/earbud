import SwiftUI

// MARK: - Buttons

/// `.btn`, `.btn.primary`, `.btn.lg`, `.btn.xl` and `.btn.stopbtn` from the mockups.
struct EarBudButtonStyle: ButtonStyle {
    enum Kind { case standard, primary, destructiveFill }
    enum Size { case regular, large, extraLarge }

    var kind: Kind = .standard
    var size: Size = .regular
    var fullWidth = false

    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        let height: CGFloat = switch size { case .regular: 24; case .large: 30; case .extraLarge: 36 }
        let padding: CGFloat = switch size { case .regular: 12; case .large: 18; case .extraLarge: 26 }
        let radius: CGFloat = switch size { case .regular: 6; case .large: 7; case .extraLarge: 8 }
        let fontSize: CGFloat = switch size { case .regular: 13; case .large: 13.5; case .extraLarge: 14 }
        let shape = RoundedRectangle(cornerRadius: radius, style: .continuous)

        configuration.label
            .font(.system(size: fontSize, weight: size == .extraLarge ? .semibold : .medium))
            .labelStyle(.titleAndIcon)
            .imageScale(.small)
            .foregroundStyle(kind == .standard ? Palette.label : .white)
            .padding(.horizontal, padding)
            .frame(maxWidth: fullWidth ? .infinity : nil)
            .frame(height: height)
            .background {
                switch kind {
                case .standard:
                    shape.fill(Palette.control)
                        .shadow(color: .black.opacity(0.12), radius: 0.75, y: 0.5)
                        .overlay(shape.strokeBorder(Palette.controlBorder, lineWidth: Metrics.hairline))
                case .primary:
                    shape.fill(LinearGradient(colors: [Palette.accentHi, Palette.accent], startPoint: .top, endPoint: .bottom))
                        .shadow(color: .black.opacity(0.2), radius: 0.75, y: 0.5)
                        .overlay(shape.strokeBorder(.black.opacity(0.12), lineWidth: Metrics.hairline))
                case .destructiveFill:
                    shape.fill(Palette.red)
                        .shadow(color: .black.opacity(0.2), radius: 0.75, y: 0.5)
                        .overlay(shape.strokeBorder(.black.opacity(0.12), lineWidth: Metrics.hairline))
                }
            }
            .contentShape(shape)
            .opacity(isEnabled ? (configuration.isPressed ? 0.8 : 1) : 0.45)
    }
}

/// `.tb-btn`: a borderless toolbar-style icon button with a hover fill.
struct IconButtonStyle: ButtonStyle {
    var size: CGFloat = 28
    @State private var hovering = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 15))
            .foregroundStyle(Palette.label2)
            .frame(minWidth: 32, minHeight: size)
            .background(RoundedRectangle(cornerRadius: 6).fill(hovering || configuration.isPressed ? Palette.fill : .clear))
            .contentShape(Rectangle())
            .onHover { hovering = $0 }
    }
}

// MARK: - Status

/// `.dot`: a 7 pt status dot.
struct StatusDot: View {
    var color: Color = Palette.green
    var size: CGFloat = 7
    var body: some View {
        Circle().fill(color).frame(width: size, height: size)
    }
}

/// `.spinner`: a small indeterminate progress ring.
struct Spinner: View {
    var size: CGFloat = 14
    var lineWidth: CGFloat = 2
    var track: Color = Palette.accentTintStrong
    var tint: Color = Palette.accent
    @State private var spinning = false

    var body: some View {
        ZStack {
            Circle().stroke(track, lineWidth: lineWidth)
            Circle().trim(from: 0, to: 0.25).stroke(tint, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                .rotationEffect(.degrees(spinning ? 360 : 0))
        }
        .frame(width: size, height: size)
        .onAppear {
            withAnimation(.linear(duration: 0.9).repeatForever(autoreverses: false)) { spinning = true }
        }
        .accessibilityLabel("Working")
    }
}

/// `.bar` / `.minibar`: a thin determinate progress bar.
struct ProgressBar: View {
    var value: Double
    var height: CGFloat = 6
    var track: Color = Palette.fill2
    var tint: Color = Palette.accent

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule().fill(track)
                Capsule().fill(tint).frame(width: max(0, min(1, value)) * geo.size.width)
            }
        }
        .frame(height: height)
        .accessibilityElement()
        .accessibilityValue("\(Int((value * 100).rounded())) percent")
    }
}

/// `.pill` status chips in the recording list.
struct StatusPill: View {
    enum Kind { case waiting, running, done, failed, incomplete }
    var kind: Kind
    var title: String
    var onAccent = false

    var body: some View {
        HStack(spacing: 4) {
            icon
            Text(title)
        }
        .font(Typography.pill)
        .foregroundStyle(foreground)
        .padding(.horizontal, 7)
        .frame(height: Metrics.pillHeight)
        .background(Capsule().fill(background))
    }

    @ViewBuilder private var icon: some View {
        switch kind {
        case .waiting: Image(systemName: "clock").font(.system(size: 9, weight: .semibold))
        case .running: Spinner(size: 10, lineWidth: 1.5, track: onAccent ? .white.opacity(0.35) : Palette.accentTintStrong, tint: onAccent ? .white : Palette.accent)
        case .done: Image(systemName: "checkmark").font(.system(size: 9, weight: .bold))
        case .failed, .incomplete: Image(systemName: "exclamationmark.triangle.fill").font(.system(size: 9))
        }
    }

    private var foreground: Color {
        if onAccent { return .white }
        switch kind {
        case .waiting: return Palette.label2
        case .running: return Palette.accent
        case .done: return Palette.pillDoneText
        case .failed: return Palette.pillFailText
        case .incomplete: return Palette.pillIncompleteText
        }
    }

    private var background: Color {
        if onAccent { return .white.opacity(0.2) }
        switch kind {
        case .waiting: return Palette.fill2
        case .running: return Palette.accentTint
        case .done: return Palette.pillDoneBackground
        case .failed: return Palette.pillFailBackground
        case .incomplete: return Palette.pillIncompleteBackground
        }
    }
}

// MARK: - Source

/// `.src`: a recording's source, shown in the list row and detail view
/// (mockup 25 "Source shown and shared library"): Fieldy, the imported file name,
/// or the microphone name.
struct SourceBadge: View {
    var source: RecordingSourceKind
    var onAccent = false

    var body: some View {
        HStack(spacing: 4) {
            icon
            Text(label).lineLimit(1)
        }
        .font(Typography.rowMeta)
        .foregroundStyle(onAccent ? .white.opacity(0.85) : Palette.label3)
    }

    @ViewBuilder private var icon: some View {
        switch source {
        case .fieldy: PodGlyph(size: 12, lineWidth: 1.8)
        case .imported: Image(systemName: "doc").font(.system(size: 10.5))
        case .microphone: Image(systemName: "mic").font(.system(size: 10.5))
        }
    }

    private var label: String {
        switch source {
        case .fieldy: "Fieldy"
        case .imported(let name): name
        case .microphone(let name): name
        }
    }
}

/// `.srcchip` / `.pill tonly`: the source and "Transcript only" line in the detail header.
struct SourceLine: View {
    var recording: RecordingItem

    var body: some View {
        HStack(spacing: 10) {
            SourceBadge(source: recording.source)
            if recording.isTranscriptOnly {
                TranscriptOnlyPill()
            } else if recording.timeFromFile {
                HStack(spacing: 4) {
                    Image(systemName: "info.circle").font(.system(size: 10.5))
                    Text("Time taken from the file")
                }
                .font(Typography.rowMeta)
                .foregroundStyle(Palette.label3)
            }
        }
    }
}

/// `.pill.tonly`: "Transcript only".
struct TranscriptOnlyPill: View {
    var body: some View {
        Text("Transcript only")
            .font(Typography.pill)
            .foregroundStyle(Palette.label2)
            .padding(.horizontal, 8)
            .frame(height: Metrics.pillHeight)
            .background(Capsule().fill(Palette.fill2))
    }
}

// MARK: - Grouped form

/// `.fsec`: a titled section with an optional footnote.
struct FormSection<Content: View>: View {
    var title: String?
    var footer: String?
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if let title {
                Text(title).font(Typography.sectionTitle).foregroundStyle(Palette.label)
                    .padding(.leading, 2).padding(.bottom, 7)
            }
            content
            if let footer {
                Text(footer).font(Typography.caption).foregroundStyle(Palette.label2)
                    .cssLineHeight(1.4, size: 11.5)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, 2).padding(.top, 6)
            }
        }
    }
}

/// `.group`: a rounded container. Put a `FormDivider` between rows.
struct FormGroup<Content: View>: View {
    var fill: Color = Palette.group
    @ViewBuilder var content: Content

    var body: some View {
        VStack(spacing: 0) {
            content
        }
        .background(RoundedRectangle(cornerRadius: Metrics.groupRadius, style: .continuous).fill(fill))
        .overlay(RoundedRectangle(cornerRadius: Metrics.groupRadius, style: .continuous).strokeBorder(Palette.groupBorder, lineWidth: Metrics.hairline))
    }
}

/// The hairline between `.row`s.
struct FormDivider: View {
    var body: some View {
        Rectangle().fill(Palette.separator).frame(height: Metrics.hairline)
    }
}

/// `.row`: one line in a grouped form.
struct FormRow<Leading: View, Trailing: View>: View {
    var title: String
    var detail: String?
    var alignTop = false
    var indent: CGFloat = 0
    var titleWeight: Font.Weight = .medium
    @ViewBuilder var leading: Leading
    @ViewBuilder var trailing: Trailing

    var body: some View {
        HStack(alignment: alignTop ? .top : .center, spacing: 12) {
            leading
            VStack(alignment: .leading, spacing: 1) {
                Text(title).font(.system(size: 13, weight: titleWeight)).foregroundStyle(Palette.label)
                if let detail {
                    Text(detail).font(Typography.caption).foregroundStyle(Palette.label2)
                        .cssLineHeight(1.35, size: 11.5)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            trailing
        }
        .padding(.vertical, 9)
        .padding(.leading, 14 + indent)
        .padding(.trailing, 14)
        .frame(minHeight: Metrics.rowMinHeight)
    }
}

extension FormRow where Leading == EmptyView {
    init(title: String, detail: String? = nil, alignTop: Bool = false, indent: CGFloat = 0, titleWeight: Font.Weight = .regular,
         @ViewBuilder trailing: () -> Trailing) {
        self.init(title: title, detail: detail, alignTop: alignTop, indent: indent, titleWeight: titleWeight,
                  leading: { EmptyView() }, trailing: trailing)
    }
}

/// `.ricon`: the coloured square icon at the start of a settings row.
struct RowIcon<Glyph: View>: View {
    var background: Color = Palette.accent
    @ViewBuilder var glyph: Glyph

    var body: some View {
        glyph
            .font(.system(size: 13, weight: .medium))
            .foregroundStyle(.white)
            .frame(width: Metrics.rowIcon, height: Metrics.rowIcon)
            .background(RoundedRectangle(cornerRadius: Metrics.rowIconRadius, style: .continuous).fill(background))
    }
}

extension RowIcon where Glyph == Image {
    init(systemName: String, background: Color = Palette.accent) {
        self.init(background: background) { Image(systemName: systemName) }
    }
}

/// `.radio`: a 15 pt radio button.
struct RadioMark: View {
    var isOn: Bool
    var body: some View {
        ZStack {
            if isOn {
                Circle().fill(Palette.accent)
                Circle().fill(.white).frame(width: 6, height: 6)
            } else {
                Circle().fill(Palette.control)
                    .shadow(color: .black.opacity(0.1), radius: 0.5, y: 0.5)
                    .overlay(Circle().strokeBorder(Palette.controlBorder, lineWidth: Metrics.hairline))
            }
        }
        .frame(width: 15, height: 15)
        .padding(.top, 2)
    }
}

/// A small switch tinted with the accent, as `.toggle` in the mockups.
struct AccentSwitch: View {
    @Binding var isOn: Bool
    var label: String

    var body: some View {
        Toggle(label, isOn: $isOn)
            .toggleStyle(.switch)
            .controlSize(.small)
            .labelsHidden()
            .tint(Palette.accent)
    }
}

// MARK: - Cards

extension View {
    /// `.estep`, `.player`, `.dhero`, `.txwork`: a soft card on `content-2`.
    func softCard(radius: CGFloat = 12, fill: Color = Palette.content2) -> some View {
        background(RoundedRectangle(cornerRadius: radius, style: .continuous).fill(fill))
            .overlay(RoundedRectangle(cornerRadius: radius, style: .continuous).strokeBorder(Palette.groupBorder, lineWidth: Metrics.hairline))
    }
}
