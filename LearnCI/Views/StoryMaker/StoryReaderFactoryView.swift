import SwiftUI

struct StoryReaderFactoryView: View {
    let story: Story

    @State private var resumeChoice: StoryReaderResumeChoice?
    @State private var showResumePrompt = false
    @State private var showLocationPicker = false

    private var readerKind: StoryReaderProgressStore.ReaderKind {
        switch story.preferences.storyType {
        case .storyBook, .standard:
            return .storyBook
        case .audioStory:
            return .audioBook
        case .dialogStory:
            return .dialogStory
        case .comicBook:
            return .comicBook
        case .pictureBook:
            return .pictureBook
        }
    }

    private var savedProgress: StoryReaderProgress? {
        StoryReaderProgressStore.progress(for: story.id, readerKind: readerKind)
    }

    private var initialIndex: Int {
        switch resumeChoice {
        case .resume(let progress):
            return progress.index
        case .startAt(let index):
            return index
        case .startOver, .none:
            return 0
        }
    }

    private var initialPlaybackPosition: Double? {
        if case .resume(let progress) = resumeChoice {
            return progress.position
        }
        return nil
    }

    private var startLocations: [StoryReaderStartLocation] {
        StoryReaderStartLocation.locations(for: story, readerKind: readerKind)
    }

    var body: some View {
        Group {
            if resumeChoice == nil, savedProgress?.isResumable == true {
                ProgressView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                readerView
            }
        }
        .storyWordLookupHost(story: story)
        .onAppear {
            guard resumeChoice == nil else { return }
            if savedProgress?.isResumable == true {
                showResumePrompt = true
            } else {
                resumeChoice = .startOver
            }
        }
        .confirmationDialog(
            "Continue where you left off?",
            isPresented: $showResumePrompt,
            titleVisibility: .visible
        ) {
            if let savedProgress {
                Button("Pick Up Where I Left Off") {
                    resumeChoice = .resume(savedProgress)
                }
            }

            Button("Choose Where to Start") {
                showLocationPicker = true
            }

            Button("Start From Beginning") {
                StoryReaderProgressStore.save(
                    .init(index: 0, total: startLocations.count),
                    for: story.id,
                    readerKind: readerKind
                )
                resumeChoice = .startOver
            }
        } message: {
            Text("You can resume \(StoryReaderProgressStore.resumeLabel(for: savedProgress, readerKind: readerKind)) or start over.")
        }
        .sheet(isPresented: $showLocationPicker) {
            StoryReaderStartLocationPicker(
                title: story.title,
                locations: startLocations,
                savedProgress: savedProgress,
                readerKind: readerKind
            ) { location in
                if location.id == "saved-progress", let savedProgress {
                    resumeChoice = .resume(savedProgress)
                    showLocationPicker = false
                    return
                }

                StoryReaderProgressStore.save(.init(
                    index: location.index,
                    total: startLocations.count,
                    chapterIndex: location.chapterIndex,
                    sceneIndex: location.sceneIndex,
                    position: nil
                ), for: story.id, readerKind: readerKind)
                resumeChoice = .startAt(location.index)
                showLocationPicker = false
            }
        }
    }

    @ViewBuilder
    private var readerView: some View {
        switch story.preferences.storyType {
        case .storyBook, .standard:
            StorySessionView(
                story: story,
                initialSpineIndex: initialIndex,
                initialPlaybackPosition: initialPlaybackPosition,
                onProgressChange: saveProgress
            )
        case .audioStory:
            AudioBookReaderView(
                story: story,
                initialNavIndex: initialIndex,
                initialPlaybackPosition: initialPlaybackPosition,
                onProgressChange: saveProgress
            )
        case .dialogStory:
            DialogStoryFlowView(
                story: story,
                initialSpineIndex: initialIndex,
                initialPlaybackPosition: initialPlaybackPosition,
                onProgressChange: saveProgress
            )
        case .comicBook:
            ComicBookReaderView(
                story: story,
                initialPageIndex: initialIndex,
                onProgressChange: saveProgress
            )
        case .pictureBook:
            PictureBookReaderView(
                story: story,
                initialSpreadIndex: initialIndex,
                initialPlaybackPosition: initialPlaybackPosition,
                onProgressChange: saveProgress
            )
        }
    }

    private func saveProgress(_ update: StoryReaderProgressUpdate) {
        StoryReaderProgressStore.save(update, for: story.id, readerKind: readerKind)
    }
}

private enum StoryReaderResumeChoice: Equatable {
    case startOver
    case startAt(Int)
    case resume(StoryReaderProgress)
}

struct StoryReaderProgressUpdate: Codable, Equatable {
    let index: Int
    var total: Int?
    var chapterIndex: Int?
    var sceneIndex: Int?
    var position: Double?

    init(
        index: Int,
        total: Int? = nil,
        chapterIndex: Int? = nil,
        sceneIndex: Int? = nil,
        position: Double? = nil
    ) {
        self.index = index
        self.total = total
        self.chapterIndex = chapterIndex
        self.sceneIndex = sceneIndex
        self.position = position
    }
}

struct StoryReaderProgress: Codable, Equatable {
    let index: Int
    let total: Int?
    let chapterIndex: Int?
    let sceneIndex: Int?
    let position: Double?
    let updatedAt: Date

    var isResumable: Bool {
        index > 0
            || (chapterIndex ?? 0) > 0
            || (sceneIndex ?? 0) > 0
            || (position ?? 0) > 1
    }
}

enum StoryReaderProgressStore {
    enum ReaderKind: String {
        case storyBook
        case audioBook
        case dialogStory
        case comicBook
        case pictureBook

        var displayName: String {
            switch self {
            case .storyBook: return "Story Book"
            case .audioBook: return "Audio Book"
            case .dialogStory: return "Dialog Story"
            case .comicBook: return "Comic Book"
            case .pictureBook: return "Picture Book"
            }
        }
    }

    private static func key(storyID: UUID, readerKind: ReaderKind) -> String {
        "storyReaderProgress.\(storyID.uuidString).\(readerKind.rawValue)"
    }

    static func progress(for storyID: UUID, readerKind: ReaderKind) -> StoryReaderProgress? {
        guard let data = UserDefaults.standard.data(forKey: key(storyID: storyID, readerKind: readerKind)) else {
            return nil
        }
        return try? JSONDecoder().decode(StoryReaderProgress.self, from: data)
    }

    static func save(_ update: StoryReaderProgressUpdate, for storyID: UUID, readerKind: ReaderKind) {
        let progress = StoryReaderProgress(
            index: max(0, update.index),
            total: update.total,
            chapterIndex: update.chapterIndex,
            sceneIndex: update.sceneIndex,
            position: update.position,
            updatedAt: Date()
        )
        guard let data = try? JSONEncoder().encode(progress) else { return }
        UserDefaults.standard.set(data, forKey: key(storyID: storyID, readerKind: readerKind))
    }

    static func resumeLabel(for progress: StoryReaderProgress?, readerKind: ReaderKind) -> String {
        guard let progress else { return "your \(readerKind.displayName)" }
        let chapter = progress.chapterIndex.map { "Chapter \($0 + 1)" }
        let scene = progress.sceneIndex.map { "Scene \($0 + 1)" }
        let position = progress.position.flatMap { $0 > 1 ? formatTime($0) : nil }
        let details = [chapter, scene, position].compactMap(\.self).joined(separator: " · ")
        if !details.isEmpty {
            return "\(readerKind.displayName) · \(details)"
        }
        if let total = progress.total, total > 0 {
            return "\(readerKind.displayName) page \(min(progress.index + 1, total)) of \(total)"
        }
        return "\(readerKind.displayName) page \(progress.index + 1)"
    }

    private static func formatTime(_ seconds: Double) -> String {
        let totalSeconds = max(0, Int(seconds.rounded()))
        let minutes = totalSeconds / 60
        let seconds = totalSeconds % 60
        return String(format: "%d:%02d", minutes, seconds)
    }
}

private struct StoryReaderStartLocation: Identifiable, Equatable {
    let id: String
    let index: Int
    let title: String
    let subtitle: String
    let icon: String
    let chapterIndex: Int?
    let sceneIndex: Int?

    static func locations(
        for story: Story,
        readerKind: StoryReaderProgressStore.ReaderKind
    ) -> [StoryReaderStartLocation] {
        let adapter = StoryReaderDataAdapter(story: story)
        switch readerKind {
        case .storyBook:
            return spineLocations(items: adapter.items(for: .storyBook), story: story, adapter: adapter)
        case .audioBook:
            return spineLocations(items: adapter.items(for: .audioBook), story: story, adapter: adapter)
                .filter { $0.icon != "photo" }
        case .dialogStory:
            return spineLocations(items: adapter.items(for: .dialogStory), story: story, adapter: adapter)
                .filter { $0.icon != "photo" }
        case .pictureBook:
            return PictureBookRenderer.makeSpreads(story: story, adapter: adapter).enumerated().map { index, spread in
                StoryReaderStartLocation(
                    id: spread.id,
                    index: index,
                    title: spread.spinePrimaryTitle,
                    subtitle: spread.spineContextLabel,
                    icon: icon(for: spread.spineItem),
                    chapterIndex: spread.chapterIndex,
                    sceneIndex: sceneIndex(for: spread.spineItem)
                )
            }
        case .comicBook:
            return ComicBookRenderer.makePages(story: story, adapter: adapter).enumerated().map { index, page in
                StoryReaderStartLocation(
                    id: page.id.uuidString,
                    index: index,
                    title: "Page \(index + 1)",
                    subtitle: comicSubtitle(for: page),
                    icon: "rectangle.grid.2x2",
                    chapterIndex: page.chapterIndex,
                    sceneIndex: page.sceneIndex
                )
            }
        }
    }

    private static func spineLocations(
        items: [StoryReadingSpineItem],
        story: Story,
        adapter: StoryReaderDataAdapter
    ) -> [StoryReaderStartLocation] {
        items.enumerated().map { index, item in
            StoryReaderStartLocation(
                id: item.id,
                index: index,
                title: StoryReadingSpineTitles.spinePrimaryTitle(for: item, story: story, adapter: adapter),
                subtitle: StoryReadingSpineTitles.spineContextLabel(for: item, story: story, adapter: adapter),
                icon: icon(for: item),
                chapterIndex: chapterIndex(for: item),
                sceneIndex: sceneIndex(for: item)
            )
        }
    }

    private static func icon(for item: StoryReadingSpineItem) -> String {
        switch item {
        case .cover:
            return "book.closed"
        case .readingMatterPage:
            return "doc.text"
        case .chapter:
            return "text.book.closed"
        case .chapterQuiz:
            return "checkmark.circle"
        case .chapterVocabulary:
            return "text.book.closed.fill"
        case .scene:
            return "photo"
        }
    }

    private static func chapterIndex(for item: StoryReadingSpineItem) -> Int? {
        switch item {
        case .chapter(let index), .scene(let index, _), .chapterQuiz(let index), .chapterVocabulary(let index):
            return index
        default:
            return nil
        }
    }

    private static func sceneIndex(for item: StoryReadingSpineItem) -> Int? {
        if case .scene(_, let sceneIndex) = item {
            return sceneIndex
        }
        return nil
    }

    private static func comicSubtitle(for page: ComicBookPageModel) -> String {
        var parts: [String] = []
        if let chapterIndex = page.chapterIndex {
            parts.append("Chapter \(chapterIndex + 1)")
        }
        if let sceneIndex = page.sceneIndex {
            parts.append("Scene \(sceneIndex + 1)")
        }
        return parts.isEmpty ? "Comic page" : parts.joined(separator: " · ")
    }
}

private struct StoryReaderStartLocationPicker: View {
    let title: String
    let locations: [StoryReaderStartLocation]
    let savedProgress: StoryReaderProgress?
    let readerKind: StoryReaderProgressStore.ReaderKind
    let onSelect: (StoryReaderStartLocation) -> Void

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                if let savedProgress, savedProgress.isResumable {
                    Section {
                        Button {
                            onSelect(StoryReaderStartLocation(
                                id: "saved-progress",
                                index: savedProgress.index,
                                title: "Where I Left Off",
                                subtitle: StoryReaderProgressStore.resumeLabel(for: savedProgress, readerKind: readerKind),
                                icon: "clock.arrow.circlepath",
                                chapterIndex: savedProgress.chapterIndex,
                                sceneIndex: savedProgress.sceneIndex
                            ))
                        } label: {
                            locationRow(
                                title: "Where I Left Off",
                                subtitle: StoryReaderProgressStore.resumeLabel(for: savedProgress, readerKind: readerKind),
                                icon: "clock.arrow.circlepath"
                            )
                        }
                    }
                }

                Section("Story Locations") {
                    ForEach(locations) { location in
                        Button {
                            onSelect(location)
                        } label: {
                            locationRow(title: location.title, subtitle: location.subtitle, icon: location.icon)
                        }
                    }
                }
            }
            .navigationTitle("Start Reading")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
    }

    private func locationRow(title: String, subtitle: String, icon: String) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .frame(width: 24)
                .foregroundStyle(Color.accentColor)
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
        }
    }
}

struct StoryReaderUnavailableView: View {
    let title: String
    let message: String

    var body: some View {
        ContentUnavailableView {
            Label(title, systemImage: "exclamationmark.triangle")
        } description: {
            Text(message)
        }
        .navigationTitle("Story Reader")
    }
}
