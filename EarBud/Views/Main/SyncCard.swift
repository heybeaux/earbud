import SwiftUI

/// `.syncard`: progress at the top of the list while a sync runs (mockup 15),
/// then a short result once it ends.
struct SyncCard: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 8) {
                icon
                Text(headline)
                    .font(.system(size: 13.5, weight: .semibold))
                    .foregroundStyle(Palette.label)
            }
            if case .running(let p) = model.sync, p.phase == .copying || p.phase == .finishing {
                HStack {
                    Text("Recording \(max(1, p.fileIndex)) of \(p.fileCount)")
                    Spacer()
                    Text("\(model.formatting.bytes(p.bytesReceived)) of \(model.formatting.bytes(p.bytesExpected))")
                }
                .font(Typography.rowMeta)
                .foregroundStyle(Palette.label2)
                .padding(.top, 8)
                ProgressBar(value: p.fraction, track: Palette.accent.opacity(0.16))
                    .padding(.top, 6)
            }
            if let tip {
                Text(tip)
                    .font(Typography.rowMeta)
                    .foregroundStyle(Palette.label2)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, 8)
            }
        }
        .padding(.horizontal, 14)
        .padding(.top, 13)
        .padding(.bottom, 12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 11, style: .continuous).fill(Palette.accentTint))
        .overlay(RoundedRectangle(cornerRadius: 11, style: .continuous).strokeBorder(Palette.accent.opacity(0.22), lineWidth: Metrics.hairline))
        .padding(.horizontal, 10)
        .padding(.top, 12)
        .padding(.bottom, 4)
        .accessibilityElement(children: .combine)
    }

    @ViewBuilder private var icon: some View {
        switch model.sync {
        case .finished(.copied, _), .finished(.nothingNew, _):
            Image(systemName: "checkmark.circle.fill").foregroundStyle(Palette.green)
        case .finished:
            Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(Palette.orange)
        default:
            Image(systemName: "arrow.triangle.2.circlepath").foregroundStyle(Palette.accent)
        }
    }

    private var headline: String {
        switch model.sync {
        case .idle:
            return ""
        case .running(let p):
            switch p.phase {
            case .connecting: return "Connecting to your Fieldy"
            case .checking: return "Checking for new recordings"
            case .copying, .finishing: return p.fileCount == 1 ? "Copying 1 recording" : "Copying \(p.fileCount) recordings"
            }
        case .finished(let outcome, _):
            switch outcome {
            case .copied(let n): return n == 1 ? "1 recording copied" : "\(n) recordings copied"
            case .nothingNew: return "No new recordings"
            case .interrupted(let saved): return saved == 1 ? "Sync stopped. 1 recording was saved." : "Sync stopped. \(saved) recordings were saved."
            case .failed: return "Sync didn't finish"
            }
        }
    }

    private var tip: String? {
        switch model.sync {
        case .running: return "Keep your Fieldy near this Mac until it's done."
        case .finished(.copied, _): return "Transcripts are being made on this Mac."
        case .finished(.nothingNew, _): return "Everything on your Fieldy is already here."
        case .finished(.interrupted, _): return "Keep your Fieldy near this Mac and sync again to get the rest."
        case .finished(.failed(let message), _): return message
        case .idle: return nil
        }
    }
}
