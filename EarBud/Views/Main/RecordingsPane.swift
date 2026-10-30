import SwiftUI

/// The day-grouped list beside the selected recording, or the empty state (mockup 13).
struct RecordingsPane: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        Group {
            if model.isLoaded && model.recordings.isEmpty && !model.isSearching && !model.sync.isRunning {
                EmptyLibraryView()
            } else {
                HStack(spacing: 0) {
                    RecordingList()
                        .frame(width: Metrics.listWidth)
                    Rectangle().fill(Palette.separatorStrong).frame(width: Metrics.hairline)
                    detail
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
        }
        .background(Palette.content)
    }

    @ViewBuilder private var detail: some View {
        if let recording = model.selectedRecording {
            RecordingDetail(recording: recording)
                .id(recording.id)
        } else if model.isSearching {
            ContentUnavailableMessage(symbol: "magnifyingglass", title: "No recording selected",
                                      message: "Choose a result to read and listen to it.")
        } else {
            ContentUnavailableMessage(symbol: "waveform", title: "No recording selected",
                                      message: "Choose a recording to read and listen to it.")
        }
    }
}

/// A quiet centred message for empty panes.
struct ContentUnavailableMessage: View {
    var symbol: String
    var title: String
    var message: String

    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: symbol)
                .font(.system(size: 28, weight: .light))
                .foregroundStyle(Palette.label3)
            Text(title).font(.system(size: 15, weight: .semibold)).foregroundStyle(Palette.label)
            Text(message).font(Typography.callout).foregroundStyle(Palette.label2)
                .multilineTextAlignment(.center)
        }
        .padding(40)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
