import SwiftUI

// MARK: - History View
struct HistoryView: View {
    @StateObject private var historyStore = HistoryStore.shared
    @State private var selectedItems = Set<UUID>()
    @State private var searchText = ""
    @State private var showingClearConfirm = false

    var body: some View {
        VStack(spacing: 0) {
            // Toolbar
            HStack {
                Text("History")
                    .font(.title2)
                    .fontWeight(.semibold)

                Spacer()

                // Search
                HStack {
                    Image(systemName: "magnifyingglass")
                        .foregroundColor(.secondary)
                    TextField("Search...", text: $searchText)
                        .textFieldStyle(.plain)
                        .frame(width: 180)
                    if !searchText.isEmpty {
                        Button {
                            searchText = ""
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .foregroundColor(.secondary)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(6)
                .background(.ultraThinMaterial)
                .clipShape(RoundedRectangle(cornerRadius: 8))

                if !selectedItems.isEmpty {
                    Button("Delete (\(selectedItems.count))", role: .destructive) {
                        historyStore.delete(selectedItems)
                        selectedItems.removeAll()
                    }
                }

                if !historyStore.items.isEmpty {
                    Button("Clear All", role: .destructive) {
                        showingClearConfirm = true
                    }
                }
            }
            .padding()
            .background(.ultraThinMaterial)

            // List
            if filteredItems.isEmpty {
                VStack(spacing: 12) {
                    Spacer()
                    Image(systemName: "clock")
                        .font(.system(size: 48))
                        .foregroundColor(.secondary.opacity(0.5))
                    Text("No transcriptions yet")
                        .font(.headline)
                        .foregroundColor(.secondary)
                    Text("Transcribe a file or use the microphone hotkey")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Spacer()
                }
            } else {
                List(filteredItems, selection: $selectedItems) { item in
                    HistoryRow(item: item)
                        .tag(item.id)
                        .contextMenu {
                            Button("Copy Text") {
                                NSPasteboard.general.clearContents()
                                NSPasteboard.general.setString(item.text, forType: .string)
                            }
                            Button("Copy as Quote") {
                                let quote = "> \(item.text)"
                                NSPasteboard.general.clearContents()
                                NSPasteboard.general.setString(quote, forType: .string)
                            }
                            Divider()
                            Button("Delete", role: .destructive) {
                                historyStore.delete([item.id])
                            }
                        }
                }
                .listStyle(.inset(alternatesRowBackgrounds: true))
                .alternatingRowBackgrounds()
            }
        }
        .alert("Clear All History?", isPresented: $showingClearConfirm) {
            Button("Clear All", role: .destructive) { historyStore.clear() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This action cannot be undone.")
        }
    }

    private var filteredItems: [TranscriptionItem] {
        if searchText.isEmpty { return historyStore.items }
        return historyStore.items.filter { item in
            item.text.localizedCaseInsensitiveContains(searchText) ||
            (item.fileName?.localizedCaseInsensitiveContains(searchText) ?? false)
        }
    }
}

// MARK: - History Row
struct HistoryRow: View {
    let item: TranscriptionItem

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            // Header
            HStack(spacing: 8) {
                Text(item.sourceIcon)
                    .font(.caption)

                Text(item.source == .file ? item.fileName ?? "File" : "Microphone")
                    .font(.caption)
                    .fontWeight(.medium)
                    .foregroundColor(.secondary)

                Spacer()

                Text(item.formattedDuration)
                    .font(.caption)
                    .foregroundColor(.secondary)

                Text(item.formattedTimestamp)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            // Preview
            Text(item.text)
                .lineLimit(3)
                .font(.body)
        }
        .padding(.vertical, 4)
    }
}
