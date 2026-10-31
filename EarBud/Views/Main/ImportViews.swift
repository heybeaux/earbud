import AppKit
import SwiftUI

/// `.droptarget`: shown over the window while audio files or folders are dragged in (mockup 23).
struct ImportDropTarget: View {
    var body: some View {
        let shape = RoundedRectangle(cornerRadius: 12, style: .continuous)
        VStack(spacing: 10) {
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(Palette.accent)
                .frame(width: 72, height: 72)
                .shadow(color: Color(red: 44 / 255, green: 122 / 255, blue: 107 / 255).opacity(0.35), radius: 12, y: 8)
                .overlay {
                    Image(systemName: "arrow.down.circle")
                        .font(.system(size: 34, weight: .medium))
                        .foregroundStyle(.white)
                }
            Text("Drop audio files or folders to import")
                .font(.system(size: 22, weight: .bold))
                .tracking(-0.22)
                .foregroundStyle(Palette.label)
            Text("EarBud copies them into your library and transcribes them on this Mac. Your originals are not changed.")
                .font(.system(size: 13.5))
                .cssLineHeight(1.45, size: 13.5)
                .foregroundStyle(Palette.label2)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 440)
            HStack(spacing: 6) {
                ForEach(ImportFormats.names, id: \.self) { name in
                    Text(name)
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(Palette.accent)
                        .padding(.horizontal, 7)
                        .padding(.vertical, 2)
                        .background(RoundedRectangle(cornerRadius: 5, style: .continuous).fill(Palette.formatTag))
                        .overlay(RoundedRectangle(cornerRadius: 5, style: .continuous).strokeBorder(Palette.formatTagBorder, lineWidth: Metrics.hairline))
                }
            }
            .padding(.top, 2)
        }
        .padding(24)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(shape.fill(.ultraThinMaterial))
        .background(shape.fill(Palette.dropTarget))
        .overlay(shape.strokeBorder(Palette.accent, lineWidth: 3))
        .clipShape(shape)
        .allowsHitTesting(false)
        .accessibilityElement(children: .combine)
    }
}

/// The import sheet: progress while files are copied, then the summary (mockup 24).
struct ImportSheetView: View {
    @Environment(AppModel.self) private var model
    var sheet: ImportSheet

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            switch sheet {
            case .importing(let progress): ImportProgressContent(progress: progress)
            case .finished(let summary): ImportSummaryBody(summary: summary) { model.dismissImportSummary() }
            }
        }
        .padding(EdgeInsets(top: 22, leading: 22, bottom: 18, trailing: 22))
        .frame(width: 480)
        .background(Palette.sheetBackground)
    }
}

/// Icon, title and subtitle at the top of the sheet.
private struct ImportSheetHeader: View {
    var title: String
    var subtitle: String

    var body: some View {
        HStack(spacing: 14) {
            Image(nsImage: NSApp.applicationIconImage)
                .resizable()
                .frame(width: 48, height: 48)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 15, weight: .bold))
                    .foregroundStyle(Palette.label)
                if !subtitle.isEmpty {
                    Text(subtitle)
                        .font(.system(size: 12.5))
                        .foregroundStyle(Palette.label2)
                        .lineLimit(2)
                        .truncationMode(.middle)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(.bottom, 16)
    }
}

private struct ImportProgressContent: View {
    var progress: ImportProgress

    var body: some View {
        ImportSheetHeader(title: progress.title, subtitle: progress.currentFileName ?? "")
        ProgressBar(value: progress.fraction)
            .padding(.bottom, 10)
        Text("New recordings appear in the list as each file is copied, and are transcribed on this Mac.")
            .font(Typography.caption)
            .foregroundStyle(Palette.label2)
    }
}

private struct ImportSummaryBody: View {
    var summary: ImportSummaryContent
    var dismiss: () -> Void

    var body: some View {
        ImportSheetHeader(title: summary.title, subtitle: summary.subtitle)
        HStack(spacing: 8) {
            CountBox(value: summary.report.importedIDs.count, label: "Imported")
            CountBox(value: summary.report.duplicates.count, label: "Already in EarBud")
            CountBox(value: summary.report.rejected.count, label: "Not imported")
        }
        .padding(.bottom, 14)
        if !summary.report.duplicates.isEmpty || !summary.report.rejected.isEmpty {
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    if !summary.report.duplicates.isEmpty {
                        FileSection(title: "Already in EarBud") {
                            ForEach(Array(summary.report.duplicates.enumerated()), id: \.offset) { index, file in
                                if index > 0 { FormDivider() }
                                FileRow(name: file.fileName, detail: "Already in EarBud as \u{201C}\(file.existingTitle)\u{201D}",
                                        symbol: "checkmark.circle.fill", tint: Palette.label3)
                            }
                        }
                    }
                    if !summary.report.rejected.isEmpty {
                        FileSection(title: "Not imported") {
                            ForEach(Array(summary.report.rejected.enumerated()), id: \.offset) { index, file in
                                if index > 0 { FormDivider() }
                                FileRow(name: file.fileName, detail: file.reason,
                                        symbol: "exclamationmark.triangle.fill", tint: Palette.orange)
                            }
                        }
                    }
                }
            }
            .scrollBounceBehavior(.basedOnSize)
            .frame(maxHeight: 300)
            .fixedSize(horizontal: false, vertical: true)
        }
        HStack {
            Spacer()
            Button("OK", action: dismiss)
                .buttonStyle(EarBudButtonStyle(kind: .primary, size: .large))
                .frame(minWidth: 76)
                .keyboardShortcut(.defaultAction)
        }
        .padding(.top, 4)
    }
}

/// `.counts span`: a number over a label.
private struct CountBox: View {
    var value: Int
    var label: String

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: 8, style: .continuous)
        VStack(alignment: .leading, spacing: 0) {
            Text("\(value)")
                .font(.system(size: 18, weight: .bold).monospacedDigit())
                .foregroundStyle(Palette.label)
            Text(label)
                .font(Typography.caption)
                .foregroundStyle(Palette.label2)
                .lineLimit(1)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(shape.fill(Palette.content))
        .overlay(shape.strokeBorder(Palette.groupBorder, lineWidth: Metrics.hairline))
        .accessibilityElement(children: .combine)
    }
}

/// `.gh` heading over a `.group` of file rows.
private struct FileSection<Rows: View>: View {
    var title: String
    @ViewBuilder var rows: Rows

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: 9, style: .continuous)
        Text(title)
            .font(.system(size: 11, weight: .semibold))
            .foregroundStyle(Palette.label3)
            .padding(.horizontal, 2)
            .padding(.bottom, 6)
        VStack(spacing: 0) { rows }
            .background(shape.fill(Palette.content))
            .overlay(shape.strokeBorder(Palette.groupBorder, lineWidth: Metrics.hairline))
            .padding(.bottom, 12)
    }
}

private struct FileRow: View {
    var name: String
    var detail: String
    var symbol: String
    var tint: Color

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: symbol)
                .font(.system(size: 16))
                .foregroundStyle(tint)
                .frame(width: 18, height: 18)
            VStack(alignment: .leading, spacing: 1) {
                Text(name)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(Palette.label)
                    .lineLimit(1)
                    .truncationMode(.middle)
                Text(detail)
                    .font(Typography.caption)
                    .foregroundStyle(Palette.label2)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .frame(minHeight: 46)
        .accessibilityElement(children: .combine)
    }
}
