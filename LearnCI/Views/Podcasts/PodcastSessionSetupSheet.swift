import SwiftUI
import SwiftData

struct PodcastSessionSetupSheet: View {
    let shows: [PodcastShow]
    let onStart: ([PodcastEpisode], Int) -> Void
    let onDismiss: () -> Void

    @State private var selectedShowIDs: Set<UUID> = []
    @State private var selectedMinutes: Int = 30
    @State private var customMinutes: String = ""
    @State private var useCustom = false

    private let presetMinutes = [15, 30, 45, 60]

    var body: some View {
        NavigationStack {
            List {
                // Duration Section
                Section("How long?") {
                    HStack(spacing: 10) {
                        ForEach(presetMinutes, id: \.self) { mins in
                            Button {
                                selectedMinutes = mins
                                useCustom = false
                            } label: {
                                Text("\(mins)m")
                                    .font(.subheadline.bold())
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 10)
                                    .background(!useCustom && selectedMinutes == mins ? Color.blue : Color(.systemGray5))
                                    .foregroundColor(!useCustom && selectedMinutes == mins ? .white : .primary)
                                    .clipShape(RoundedRectangle(cornerRadius: 10))
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16))

                    HStack {
                        Text("Custom:")
                            .font(.subheadline)
                        TextField("min", text: $customMinutes)
                            .keyboardType(.numberPad)
                            .frame(width: 60)
                            .textFieldStyle(.roundedBorder)
                            .onChange(of: customMinutes) { _, newValue in
                                if let mins = Int(newValue), mins > 0 {
                                    selectedMinutes = mins
                                    useCustom = true
                                }
                            }
                        Text("minutes")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                    }
                }

                // Queue preview
                Section {
                    let queue = buildQueue()
                    if queue.isEmpty {
                        Text("No unplayed episodes from selected shows")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    } else {
                        let totalDuration = queue.reduce(0) { $0 + $1.duration }
                        Text("\(queue.count) episodes (\(formatDuration(totalDuration)))")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                } header: {
                    Text("Queue Preview")
                }

                // Shows Section
                Section("Which shows?") {
                    Button {
                        if selectedShowIDs.count == shows.count {
                            selectedShowIDs.removeAll()
                        } else {
                            selectedShowIDs = Set(shows.map { $0.id })
                        }
                    } label: {
                        HStack {
                            Text(selectedShowIDs.count == shows.count ? "Deselect All" : "Select All")
                                .font(.subheadline.weight(.medium))
                                .foregroundColor(.blue)
                            Spacer()
                            Text("\(selectedShowIDs.count) of \(shows.count)")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }
                    .buttonStyle(.plain)

                    ForEach(shows) { show in
                        let isSelected = selectedShowIDs.contains(show.id)
                        let unplayedCount = show.episodes.filter { !$0.isPlayed }.count

                        Button {
                            if isSelected {
                                selectedShowIDs.remove(show.id)
                            } else {
                                selectedShowIDs.insert(show.id)
                            }
                        } label: {
                            HStack(spacing: 12) {
                                CachedAsyncImage(url: URL(string: show.artworkUrl ?? "")) { image in
                                    image.resizable().scaledToFill()
                                } placeholder: {
                                    RoundedRectangle(cornerRadius: 6)
                                        .fill(Color.secondary.opacity(0.2))
                                        .overlay(Image(systemName: "headphones").font(.caption).foregroundColor(.secondary))
                                }
                                .frame(width: 40, height: 40)
                                .clipShape(RoundedRectangle(cornerRadius: 6))

                                VStack(alignment: .leading, spacing: 2) {
                                    Text(show.title)
                                        .font(.subheadline)
                                        .foregroundColor(.primary)
                                        .lineLimit(1)
                                    Text("\(unplayedCount) unplayed")
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                }

                                Spacer()

                                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                                    .foregroundColor(isSelected ? .blue : .secondary)
                                    .font(.title3)
                            }
                        }
                        .buttonStyle(.plain)
                    }
                }

            }
            .navigationTitle("Listening Session")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") { onDismiss() }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Start") {
                        let queue = buildQueue()
                        if !queue.isEmpty {
                            onStart(queue, selectedMinutes)
                        }
                    }
                    .fontWeight(.semibold)
                    .disabled(buildQueue().isEmpty)
                }
            }
            .onAppear {
                // Select all shows by default
                selectedShowIDs = Set(shows.map { $0.id })
            }
        }
    }

    private func buildQueue() -> [PodcastEpisode] {
        let selectedShows = shows.filter { selectedShowIDs.contains($0.id) }
        let unplayed = selectedShows
            .flatMap { $0.episodes }
            .filter { !$0.isPlayed }
            .sorted { $0.publishedDate > $1.publishedDate }

        var queue: [PodcastEpisode] = []
        var totalSeconds: Double = 0
        let targetSeconds = Double(selectedMinutes) * 60

        for episode in unplayed {
            queue.append(episode)
            totalSeconds += episode.duration > 0 ? episode.duration : 1800 // default 30 min if unknown
            if totalSeconds >= targetSeconds {
                break
            }
        }

        return queue
    }

    private func formatDuration(_ seconds: Double) -> String {
        let h = Int(seconds) / 3600
        let m = (Int(seconds) % 3600) / 60
        if h > 0 {
            return "\(h)h \(m)m"
        }
        return "\(m) min"
    }
}
