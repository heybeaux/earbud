import SwiftUI

/// Bar heights for the player scrubber, using the same formula as `kit.js` so a
/// recording always draws the same shape. Values are fractions of the bar area, 0.1...1.
enum WaveformShape {
    static func bars(count: Int, seed: Int) -> [Double] {
        let s = Double(seed)
        return (0..<count).map { i in
            let x = Double(i)
            let v = abs(sin(x * 0.37 * s + s) * 0.55 + sin(x * 1.13 + s * 2) * 0.3 + sin(x * 0.09) * 0.25)
            let pct = max(10, min(100, (18 + v * 90).rounded()))
            return pct / 100
        }
    }
}

/// `.wave`: waveform bars with a playhead. Click or drag to seek.
struct WaveformScrubber: View {
    var seed: Int
    var progress: Double
    var isEnabled = true
    var barCount = 96
    var onSeek: (Double) -> Void

    var body: some View {
        GeometryReader { geo in
            let bars = WaveformShape.bars(count: barCount, seed: seed)
            let gap: CGFloat = 2
            let barWidth = max(1, (geo.size.width - gap * CGFloat(barCount - 1)) / CGFloat(barCount))
            ZStack(alignment: .leading) {
                HStack(alignment: .center, spacing: gap) {
                    ForEach(bars.indices, id: \.self) { i in
                        RoundedRectangle(cornerRadius: 2)
                            .fill(Double(i) / Double(barCount) < progress ? Palette.accent : Palette.waveIdle)
                            .frame(width: barWidth, height: max(3, geo.size.height * bars[i]))
                    }
                }
                .frame(height: geo.size.height)
                if isEnabled {
                    RoundedRectangle(cornerRadius: 1)
                        .fill(Palette.accent)
                        .frame(width: 2, height: geo.size.height + 6)
                        .offset(x: max(0, min(1, progress)) * geo.size.width - 1)
                }
            }
            .contentShape(Rectangle())
            .gesture(DragGesture(minimumDistance: 0).onChanged { value in
                guard isEnabled, geo.size.width > 0 else { return }
                onSeek(max(0, min(1, value.location.x / geo.size.width)))
            })
        }
        .frame(height: 34)
        .opacity(isEnabled ? 1 : 0.5)
        .accessibilityElement()
        .accessibilityLabel("Playback position")
        .accessibilityValue("\(Int((progress * 100).rounded())) percent")
        .accessibilityAdjustableAction { direction in
            switch direction {
            case .increment: onSeek(min(1, progress + 0.05))
            case .decrement: onSeek(max(0, progress - 0.05))
            @unknown default: break
            }
        }
    }
}
