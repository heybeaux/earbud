import SwiftUI

/// The main window (mockups 12–16, 22): sidebar, then the selected pane.
struct MainWindow: View {
    @Environment(AppModel.self) private var model
    @State private var columns: NavigationSplitViewVisibility = .all

    var body: some View {
        @Bindable var model = model
        NavigationSplitView(columnVisibility: $columns) {
            Sidebar()
                .navigationSplitViewColumnWidth(min: 200, ideal: Metrics.sidebarWidth, max: 280)
        } detail: {
            pane
                .navigationTitle(title)
                .navigationSubtitle(subtitle)
                .toolbar {
                    ToolbarItem(placement: .primaryAction) { SyncToolbarButton() }
                }
                .searchable(text: $model.searchText, placement: .toolbar, prompt: "Search transcripts")
        }
        .frame(minWidth: Metrics.windowMinWidth, minHeight: Metrics.windowMinHeight)
        .task { await model.start() }
    }

    @ViewBuilder private var pane: some View {
        switch model.sidebar {
        case .recordings: RecordingsPane()
        case .syncHistory: SyncHistoryPane()
        case .recentlyDeleted: RecentlyDeletedPane()
        case .device: DevicePanel()
        }
    }

    private var title: String {
        switch model.sidebar {
        case .recordings: "Recordings"
        case .syncHistory: "Sync History"
        case .recentlyDeleted: "Recently Deleted"
        case .device: "My Fieldy"
        }
    }

    private var subtitle: String {
        let f = model.formatting
        switch model.sidebar {
        case .recordings:
            if let results = model.searchResults {
                return "\(results.count) of \(f.recordings(model.recordings.count)) match"
            }
            return model.recordings.isEmpty ? "No recordings yet" : f.recordings(model.recordings.count)
        case .syncHistory:
            return model.history.count == 1 ? "1 sync" : "\(model.history.count) syncs"
        case .recentlyDeleted:
            return "Removed for good after 30 days"
        case .device:
            return "\(model.deviceState?.name ?? "Fieldy") · works with Fieldy 3"
        }
    }
}

/// "Sync" in the toolbar; "Syncing…" with a spinner while it runs.
struct SyncToolbarButton: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        if model.sync.isRunning {
            HStack(spacing: 6) {
                Spinner(size: 13)
                Text("Syncing…")
            }
            .font(.system(size: 13))
            .foregroundStyle(Palette.label2)
            .padding(.horizontal, 8)
            .accessibilityElement(children: .combine)
        } else {
            Button {
                model.syncNow()
            } label: {
                Label("Sync", systemImage: "arrow.triangle.2.circlepath")
                    .labelStyle(.titleAndIcon)
            }
            .help("Copy new recordings from your Fieldy")
        }
    }
}
