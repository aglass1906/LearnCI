import SwiftUI

struct DialogSessionView: View {
    let story: Story

    @Environment(\.dismiss) private var dismiss
    @State private var items: [DialogStoryItem] = []
    @State private var sceneHeaderIndices: [Int] = []
    @State private var visibleCount = 1
    @State private var showEnglish = false
    @State private var isDownloadingAudio = false
    @State private var playbackRate: Float = 1.0

    private var audioManager = AudioManager.shared

    init(story: Story) {
        self.story = story
    }

    private var adapter: StoryReaderDataAdapter {
        StoryReaderDataAdapter(story: story)
    }

    var body: some View {
        Group {
            if let issue = adapter.requirementIssue(for: .dialogStory) {
                StoryReaderUnavailableView(title: issue.title, message: issue.message)
            } else {
                dialogBody
            }
        }
        .navigationBarBackButtonHidden(true)
        .onAppear {
            buildItemsIfNeeded()
        }
        .onDisappear {
            audioManager.stopAudio()
        }
    }

    private var dialogBody: some View {
        VStack(spacing: 0) {
            header
            progressBar

            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(spacing: 18) {
                        ForEach(displayedItems, id: \.item.id) { displayedItem in
                            view(
                                for: displayedItem.item,
                                isNewest: displayedItem.index == visibleCount - 1
                            )
                                .id(displayedItem.item.id)
                        }
                        Color.clear.frame(height: 18).id("dialog-bottom")
                    }
                    .padding(.horizontal, 18)
                    .padding(.vertical, 16)
                }
                .contentShape(Rectangle())
                .onTapGesture {
                    advanceOne(scrollProxy: proxy)
                }
                .onChange(of: visibleCount) { _ in
                    scrollToBottom(proxy)
                }
            }

            bottomBar
        }
        .background(Color(.systemGroupedBackground))
    }

    private var header: some View {
        HStack(spacing: 12) {
            Button {
                audioManager.stopAudio()
                dismiss()
            } label: {
                Image(systemName: "chevron.left")
                    .font(.title3.weight(.semibold))
                    .frame(width: 42, height: 42)
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(story.title)
                    .font(.headline)
                    .lineLimit(1)
                Text("Dialog")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Menu {
                Button("0.75x") { setRate(0.75) }
                Button("1.0x") { setRate(1.0) }
                Button("1.25x") { setRate(1.25) }
                Button("1.5x") { setRate(1.5) }
            } label: {
                Text("\(String(format: "%.1f", playbackRate))x")
                    .font(.caption.bold())
                    .frame(width: 48, height: 36)
            }

            Button {
                showEnglish.toggle()
            } label: {
                Text(showEnglish ? "EN" : story.languageRaw.uppercased())
                    .font(.caption.bold())
                    .frame(width: 44, height: 36)
            }
            .buttonStyle(.bordered)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(.thinMaterial)
    }

    private var progressBar: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Rectangle().fill(Color.secondary.opacity(0.18))
                Rectangle()
                    .fill(Color.accentColor)
                    .frame(width: geo.size.width * progress)
            }
        }
        .frame(height: 4)
    }

    private var bottomBar: some View {
        VStack(spacing: 10) {
            if sceneHeaderIndices.count > 1 {
                HStack {
                    Button {
                        goToScene(currentSceneOrdinal - 1)
                    } label: {
                        Label("Prev", systemImage: "chevron.left")
                    }
                    .disabled(currentSceneOrdinal <= 0)

                    Spacer()

                    Text("Scene \(currentSceneOrdinal + 1) / \(sceneHeaderIndices.count)")
                        .font(.caption.monospacedDigit().weight(.semibold))
                        .foregroundStyle(.secondary)

                    Spacer()

                    Button {
                        goToScene(currentSceneOrdinal + 1)
                    } label: {
                        Label("Next", systemImage: "chevron.right")
                            .labelStyle(.titleAndIcon)
                    }
                    .disabled(currentSceneOrdinal >= sceneHeaderIndices.count - 1)
                }
                .font(.subheadline.weight(.semibold))
            }

            HStack {
                if isDownloadingAudio {
                    ProgressView()
                }

                Spacer()

                if canAdvance {
                    Label("Tap to continue", systemImage: "hand.tap")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                } else {
                    Button {
                        audioManager.stopAudio()
                        dismiss()
                    } label: {
                        Label("Done", systemImage: "checkmark.circle.fill")
                            .font(.headline)
                    }
                    .buttonStyle(.borderedProminent)
                }

                Spacer()
            }
        }
        .padding(16)
        .background(.thinMaterial)
    }

    @ViewBuilder
    private func view(for item: DialogStoryItem, isNewest: Bool) -> some View {
        let content = Group {
            switch item {
            case .cover:
                coverView
            case .readingMatter(let page):
                readingMatterView(page)
            case .sceneHeader(let header):
                sceneHeaderView(header)
            case .sceneImage(let image):
                sceneImageView(image)
            case .bubble(let bubble):
                DialogBubbleView(bubble: bubble, showEnglish: showEnglish)
            }
        }

        if isNewest {
            content
                .transition(.asymmetric(
                    insertion: .opacity.combined(with: .move(edge: .bottom)),
                    removal: .opacity
                ))
                .animation(.easeOut(duration: 0.22), value: visibleCount)
        } else {
            content
        }
    }

    private var coverView: some View {
        VStack(alignment: .leading, spacing: 12) {
            AsyncImage(url: coverURL) { phase in
                switch phase {
                case .success(let image):
                    image.resizable().scaledToFill()
                case .failure:
                    Color.accentColor.opacity(0.18)
                case .empty:
                    Color(.secondarySystemBackground).overlay { ProgressView() }
                @unknown default:
                    Color(.secondarySystemBackground)
                }
            }
            .frame(height: 220)
            .clipShape(RoundedRectangle(cornerRadius: 8))

            Text(story.title)
                .font(.system(size: 30, weight: .bold, design: .serif))
                .fixedSize(horizontal: false, vertical: true)

            Text("\(story.language.displayName) · Level \(story.level)")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(.secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    private func readingMatterView(_ page: ReadingMatterPage) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            if let title = (showEnglish ? page.titleNative : page.titleTarget)?.nilIfEmptyDialogReader {
                Text(title)
                    .font(.headline)
            }
            if let body = (showEnglish ? page.bodyNative : page.bodyTarget)?.nilIfEmptyDialogReader {
                Text(body)
                    .font(.body)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(.secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    private func sceneHeaderView(_ header: DialogSceneHeader) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("Scene \(header.ordinal + 1)")
                    .font(.headline.weight(.bold))
                Spacer()
                Text(header.chapterTitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(.secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    private func sceneImageView(_ image: DialogSceneImage) -> some View {
        AsyncImage(url: image.url) { phase in
            switch phase {
            case .success(let image):
                image.resizable().scaledToFill()
            case .failure:
                Color(.tertiarySystemGroupedBackground)
            case .empty:
                Color(.tertiarySystemGroupedBackground).overlay { ProgressView() }
            @unknown default:
                Color(.tertiarySystemGroupedBackground)
            }
        }
        .frame(maxWidth: .infinity)
        .frame(height: 220)
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    private var progress: Double {
        guard !items.isEmpty else { return 0 }
        return min(1, Double(visibleCount) / Double(items.count))
    }

    private var canAdvance: Bool {
        visibleCount < items.count
    }

    private var displayedItems: [(index: Int, item: DialogStoryItem)] {
        let revealedItems = Array(items.prefix(visibleCount).enumerated()).map {
            (index: $0.offset, item: $0.element)
        }
        guard let currentSceneStart = revealedItems.last(where: {
            if case .sceneHeader = $0.item {
                return true
            }
            return false
        })?.index else {
            return revealedItems
        }

        return Array(revealedItems[currentSceneStart...])
    }

    private var currentSceneOrdinal: Int {
        guard !sceneHeaderIndices.isEmpty else { return 0 }
        return sceneHeaderIndices.lastIndex { $0 < visibleCount } ?? 0
    }

    private var coverURL: URL? {
        if let remoteCoverPath = story.remoteCoverPath?.nilIfEmptyDialogReader {
            return AppConfig.chapterCoverURL(remoteCoverPath)
        }
        if let coverArt = story.coverArt?.nilIfEmptyDialogReader {
            return AppConfig.chapterCoverURL(coverArt)
        }
        return story.chapters.first.flatMap { chapter in
            chapter.coverUrl?.nilIfEmptyDialogReader.flatMap(AppConfig.chapterCoverURL)
        }
    }

    private func buildItemsIfNeeded() {
        guard items.isEmpty else { return }
        var builder = DialogStoryBuilder(story: story, adapter: adapter)
        let result = builder.makeItems()
        items = result.items
        sceneHeaderIndices = result.sceneHeaderIndices
        visibleCount = result.items.isEmpty ? 0 : 1
    }

    private func advanceOne(scrollProxy: ScrollViewProxy) {
        guard canAdvance else { return }
        let nextVisibleCount = visibleCountAfterAdvancing(from: visibleCount)
        withAnimation(.easeOut(duration: 0.22)) {
            visibleCount = nextVisibleCount
        }
        playAudioIfNeeded(for: nextVisibleCount - 1)
        scrollToBottom(scrollProxy)
    }

    private func scrollToBottom(_ proxy: ScrollViewProxy) {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
            withAnimation(.easeOut(duration: 0.28)) {
                proxy.scrollTo("dialog-bottom", anchor: .bottom)
            }
        }
    }

    private func goToScene(_ ordinal: Int) {
        guard sceneHeaderIndices.indices.contains(ordinal) else { return }
        audioManager.stopAudio()
        let sceneStart = sceneHeaderIndices[ordinal]
        withAnimation(.easeOut(duration: 0.18)) {
            visibleCount = visibleCountAfterEnteringScene(at: sceneStart)
        }
        playAudioIfNeeded(for: visibleCount - 1)
    }

    private func visibleCountAfterAdvancing(from currentCount: Int) -> Int {
        guard items.indices.contains(currentCount) else { return items.count }

        switch items[currentCount] {
        case .sceneHeader:
            return visibleCountAfterEnteringScene(at: currentCount)
        case .sceneImage:
            return visibleCountThroughFirstBubble(startingAt: currentCount)
        default:
            return min(items.count, currentCount + 1)
        }
    }

    private func visibleCountAfterEnteringScene(at sceneStart: Int) -> Int {
        visibleCountThroughFirstBubble(startingAt: sceneStart + 1)
    }

    private func visibleCountThroughFirstBubble(startingAt startIndex: Int) -> Int {
        var index = startIndex
        while items.indices.contains(index) {
            switch items[index] {
            case .bubble:
                return index + 1
            case .sceneHeader:
                return index
            default:
                index += 1
            }
        }
        return items.count
    }

    private func playAudioIfNeeded(for itemIndex: Int) {
        guard items.indices.contains(itemIndex),
              case .bubble(let bubble) = items[itemIndex],
              let clip = bubble.audioClip else { return }

        let localURL = adapter.localAudioURL(for: clip)
        if let cachedURL = adapter.cachedAudioURL(for: clip) {
            playLocal(url: cachedURL, clip: clip)
            return
        }

        isDownloadingAudio = true
        Task {
            await downloadAndPlay(clip: clip, localURL: localURL)
        }
    }

    private func playLocal(url: URL, clip: StorySceneAudioClip) {
        do {
            try audioManager.playOneShot(url: url, rate: playbackRate)
            audioManager.updateNowPlayingInfo(title: clip.title, artist: story.title, artworkImage: nil)
        } catch {
            print("[DialogSession] Failed to play dialog audio: \(error)")
        }
    }

    private func downloadAndPlay(clip: StorySceneAudioClip, localURL: URL) async {
        guard let url = StoryReaderDataAdapter.remoteAudioURL(for: clip.urlString) else {
            await MainActor.run { isDownloadingAudio = false }
            return
        }

        do {
            let (data, response) = try await URLSession.shared.data(from: url)
            guard let http = response as? HTTPURLResponse, http.statusCode == 200, data.count > 1000 else {
                await MainActor.run { isDownloadingAudio = false }
                return
            }

            let isWAV = data.prefix(4) == Data([0x52, 0x49, 0x46, 0x46])
            let isM4A = data.prefix(4).count == 4 && data.dropFirst(4).prefix(4) == Data([0x66, 0x74, 0x79, 0x70])
            let ext = isWAV ? "wav" : (isM4A ? "m4a" : "mp3")
            let correctURL = localURL.deletingPathExtension().appendingPathExtension(ext)
            try data.write(to: correctURL)

            await MainActor.run {
                isDownloadingAudio = false
                playLocal(url: correctURL, clip: clip)
            }
        } catch {
            await MainActor.run { isDownloadingAudio = false }
        }
    }

    private func setRate(_ rate: Float) {
        playbackRate = rate
        audioManager.setOneShotRate(rate)
    }
}

private enum DialogStoryItem: Identifiable {
    case cover
    case readingMatter(ReadingMatterPage)
    case sceneHeader(DialogSceneHeader)
    case sceneImage(DialogSceneImage)
    case bubble(DialogBubble)

    var id: String {
        switch self {
        case .cover:
            return "cover"
        case .readingMatter(let page):
            return "matter-\(page.id)"
        case .sceneHeader(let header):
            return header.id
        case .sceneImage(let image):
            return image.id
        case .bubble(let bubble):
            return bubble.id
        }
    }
}

private struct DialogSceneHeader {
    let id: String
    let ordinal: Int
    let chapterTitle: String
}

private struct DialogSceneImage {
    let id: String
    let url: URL
}

private struct DialogBubble {
    let id: String
    let character: String
    let text: String
    let textEnglish: String?
    let color: Color
    let isRightAligned: Bool
    let portraitURL: URL?
    let audioClip: StorySceneAudioClip?
}

private struct DialogStoryBuildResult {
    let items: [DialogStoryItem]
    let sceneHeaderIndices: [Int]
}

private struct DialogStoryBuilder {
    let story: Story
    let adapter: StoryReaderDataAdapter

    private var characterStyles: [String: (color: Color, rightAligned: Bool)] = [:]
    private var characterOrder = 0
    private var sceneOrdinal = 0

    private let palette: [Color] = [
        .cyan, .orange, .purple, .green, .deepOrangeDialogReader, .pink, .red
    ]

    init(story: Story, adapter: StoryReaderDataAdapter) {
        self.story = story
        self.adapter = adapter
    }

    mutating func makeItems() -> DialogStoryBuildResult {
        var builtItems: [DialogStoryItem] = []
        var headerIndices: [Int] = []

        for spineItem in adapter.items(for: .dialogStory) {
            switch spineItem {
            case .cover:
                builtItems.append(.cover)
            case .readingMatterPage:
                if let page = adapter.readingMatterPage(for: spineItem) {
                    builtItems.append(.readingMatter(page))
                }
            case .chapter:
                continue
            case .scene(let chapterIndex, let sceneIndex):
                guard let scene = adapter.scene(for: spineItem),
                      let chapter = story.chapters[safeDialogReader: chapterIndex] else { continue }

                headerIndices.append(builtItems.count)
                builtItems.append(.sceneHeader(DialogSceneHeader(
                    id: "scene-header-\(chapterIndex)-\(sceneIndex)",
                    ordinal: sceneOrdinal,
                    chapterTitle: chapter.titleTargetLanguage.nilIfEmptyDialogReader ?? "Chapter \(chapterIndex + 1)"
                )))

                if let imageURL = adapter.sceneImageURL(scene: scene, chapterIndex: chapterIndex) {
                    builtItems.append(.sceneImage(DialogSceneImage(
                        id: "scene-image-\(chapterIndex)-\(sceneIndex)",
                        url: imageURL
                    )))
                }

                appendDialogueItems(
                    scene: scene,
                    chapter: chapter,
                    chapterIndex: chapterIndex,
                    sceneIndex: sceneIndex,
                    builtItems: &builtItems
                )
                sceneOrdinal += 1
            }
        }

        return DialogStoryBuildResult(items: builtItems, sceneHeaderIndices: headerIndices)
    }

    private mutating func appendDialogueItems(
        scene: StoryScene,
        chapter: StoryChapter,
        chapterIndex: Int,
        sceneIndex: Int,
        builtItems: inout [DialogStoryItem]
    ) {
        let dialogues = resolvedDialogues(for: scene)
        let hasLineAudio = dialogues.contains { $0.audioUrl?.nilIfEmptyDialogReader != nil }
        let sceneFallbackClip = hasLineAudio ? nil : makeClip(
            urlString: scene.audioUrl,
            chapter: chapter,
            chapterIndex: chapterIndex,
            sceneIndex: sceneIndex,
            lineIndex: 0,
            title: "Scene \(sceneOrdinal + 1)"
        )

        for (lineIndex, dialogue) in dialogues.enumerated() {
            let style = style(for: dialogue.character)
            let lineClip = makeClip(
                urlString: dialogue.audioUrl,
                chapter: chapter,
                chapterIndex: chapterIndex,
                sceneIndex: sceneIndex,
                lineIndex: lineIndex,
                title: dialogue.character
            )
            let clip = lineClip ?? (lineIndex == 0 ? sceneFallbackClip : nil)

            builtItems.append(.bubble(DialogBubble(
                id: "bubble-\(chapterIndex)-\(sceneIndex)-\(lineIndex)",
                character: dialogue.character,
                text: dialogue.text,
                textEnglish: dialogue.textEnglish,
                color: style.color,
                isRightAligned: style.rightAligned,
                portraitURL: portraitURL(for: dialogue.character, scene: scene, chapterIndex: chapterIndex),
                audioClip: clip
            )))
        }
    }

    private mutating func style(for character: String) -> (color: Color, rightAligned: Bool) {
        let key = character.normalizedDialogReaderKey
        if let existing = characterStyles[key] {
            return existing
        }

        let style = (
            color: palette[characterOrder % palette.count],
            rightAligned: characterOrder % 2 == 1
        )
        characterStyles[key] = style
        characterOrder += 1
        return style
    }

    private func makeClip(
        urlString: String?,
        chapter: StoryChapter,
        chapterIndex: Int,
        sceneIndex: Int,
        lineIndex: Int,
        title: String
    ) -> StorySceneAudioClip? {
        guard let urlString = urlString?.nilIfEmptyDialogReader else { return nil }
        return StorySceneAudioClip(
            id: "\(chapterIndex)-\(sceneIndex)-line-\(lineIndex)-\(urlString.hashValue)",
            chapterIndex: chapterIndex,
            sceneIndex: sceneIndex,
            sceneOrdinal: lineIndex,
            urlString: urlString,
            duration: nil,
            startOffset: 0,
            title: title.nilIfEmptyDialogReader ?? chapter.titleTargetLanguage,
            caption: "",
            imageURL: nil
        )
    }

    private func portraitURL(for character: String, scene: StoryScene, chapterIndex: Int) -> URL? {
        if character.normalizedDialogReaderKey == "NARRATOR" {
            return adapter.sceneImageURL(scene: scene, chapterIndex: chapterIndex)
        }

        guard let assetForgeJSON = story.assetForgeJSON,
              let data = assetForgeJSON.data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: data) else { return nil }

        return findPortraitURL(in: object, characterKey: character.normalizedDialogReaderKey)
    }

    private func findPortraitURL(in value: Any, characterKey: String) -> URL? {
        if let dictionary = value as? [String: Any] {
            let nameCandidates = [
                dictionary["name"],
                dictionary["character"],
                dictionary["speaker"],
                dictionary["id"],
                dictionary["character_id"],
                dictionary["display_name"],
                dictionary["displayName"]
            ].compactMap { $0 as? String }

            let matchesCharacter = nameCandidates.contains {
                $0.normalizedDialogReaderKey == characterKey
            }

            if matchesCharacter {
                if let url = imageURL(in: dictionary) {
                    return url
                }
            }

            for (key, child) in dictionary {
                if key.normalizedDialogReaderKey == characterKey,
                   let url = imageURL(in: child) {
                    return url
                }
                if let found = findPortraitURL(in: child, characterKey: characterKey) {
                    return found
                }
            }
        } else if let array = value as? [Any] {
            for child in array {
                if let found = findPortraitURL(in: child, characterKey: characterKey) {
                    return found
                }
            }
        }
        return nil
    }

    private func imageURL(in value: Any) -> URL? {
        if let path = value as? String {
            return AppConfig.chapterCoverURL(path)
        }

        if let dictionary = value as? [String: Any] {
            for key in [
                "portraitUrl", "portrait_url",
                "imageUrl", "image_url",
                "imagePath", "image_path",
                "masterPath", "master_path",
                "masterUrl", "master_url",
                "url", "path"
            ] {
                if let path = dictionary[key] as? String,
                   let url = AppConfig.chapterCoverURL(path) {
                    return url
                }
            }

            for key in ["images", "master_images", "masterImages", "variations"] {
                if let child = dictionary[key],
                   let url = imageURL(in: child) {
                    return url
                }
            }
        }

        if let array = value as? [Any] {
            for child in array {
                if let url = imageURL(in: child) {
                    return url
                }
            }
        }

        return nil
    }

    private func resolvedDialogues(for scene: StoryScene) -> [SceneDialogue] {
        let structured = scene.dialogues.filter {
            !$0.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }
        if !structured.isEmpty {
            return structured
        }

        let parsed = parseTaggedScript(
            target: scene.scriptTargetLanguage,
            english: scene.scriptEnglish
        )
        if !parsed.isEmpty {
            return parsed
        }

        return []
    }

    private func parseTaggedScript(target: String?, english: String?) -> [SceneDialogue] {
        let targetLines = target?.components(separatedBy: .newlines) ?? []
        let englishLines = english?.components(separatedBy: .newlines) ?? []

        return targetLines.enumerated().compactMap { index, line in
            guard let parsed = parseTaggedLine(line) else { return nil }
            let englishText = englishLines[safeDialogReader: index].flatMap { parseTaggedLine($0)?.text ?? $0.nilIfEmptyDialogReader }
            return SceneDialogue(character: parsed.speaker, text: parsed.text, textEnglish: englishText)
        }
    }

    private func parseTaggedLine(_ line: String) -> (speaker: String, text: String)? {
        let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.hasPrefix("["),
              let closeBracket = trimmed.firstIndex(of: "]") else { return nil }

        let speaker = String(trimmed[trimmed.index(after: trimmed.startIndex)..<closeBracket])
            .trimmingCharacters(in: .whitespacesAndNewlines)
        var remainder = String(trimmed[trimmed.index(after: closeBracket)...])
            .trimmingCharacters(in: .whitespacesAndNewlines)

        if remainder.hasPrefix("("),
           let closeTone = remainder.firstIndex(of: ")") {
            remainder = String(remainder[remainder.index(after: closeTone)...])
                .trimmingCharacters(in: .whitespacesAndNewlines)
        }

        guard !speaker.isEmpty, !remainder.isEmpty else { return nil }
        return (speaker, remainder)
    }
}

private struct DialogBubbleView: View {
    let bubble: DialogBubble
    let showEnglish: Bool

    var body: some View {
        HStack(alignment: .bottom, spacing: 10) {
            if bubble.isRightAligned {
                Spacer(minLength: 34)
                bubbleBody
                avatar
            } else {
                avatar
                bubbleBody
                Spacer(minLength: 34)
            }
        }
        .frame(maxWidth: .infinity, alignment: bubble.isRightAligned ? .trailing : .leading)
    }

    private var bubbleBody: some View {
        VStack(alignment: bubble.isRightAligned ? .trailing : .leading, spacing: 6) {
            Text(bubble.character)
                .font(.caption.bold())
                .foregroundStyle(bubble.color)
                .textCase(.uppercase)

            Text(displayText)
                .font(.body)
                .foregroundStyle(.primary)
                .fixedSize(horizontal: false, vertical: true)
                .padding(12)
                .background(bubble.color.opacity(0.16))
                .clipShape(RoundedRectangle(cornerRadius: 8))
        }
        .frame(maxWidth: UIScreen.main.bounds.width * 0.65, alignment: bubble.isRightAligned ? .trailing : .leading)
    }

    private var avatar: some View {
        ZStack {
            Circle().fill(bubble.color.opacity(0.22))
            if let portraitURL = bubble.portraitURL {
                AsyncImage(url: portraitURL) { phase in
                    switch phase {
                    case .success(let image):
                        image.resizable().scaledToFill()
                    default:
                        Text(initial)
                            .font(.headline.bold())
                            .foregroundStyle(bubble.color)
                    }
                }
            } else {
                Text(initial)
                    .font(.headline.bold())
                    .foregroundStyle(bubble.color)
            }
        }
        .frame(width: 58, height: 58)
        .clipShape(Circle())
    }

    private var displayText: String {
        if showEnglish, let english = bubble.textEnglish?.nilIfEmptyDialogReader {
            return english
        }
        return bubble.text
    }

    private var initial: String {
        String(bubble.character.trimmingCharacters(in: .whitespacesAndNewlines).prefix(1)).uppercased()
    }
}

private extension Collection {
    subscript(safeDialogReader index: Index) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}

private extension String {
    var nilIfEmptyDialogReader: String? {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    var normalizedDialogReaderKey: String {
        trimmingCharacters(in: .whitespacesAndNewlines)
            .uppercased()
            .replacingOccurrences(of: " ", with: "_")
    }
}

private extension Color {
    static let deepOrangeDialogReader = Color(red: 0.9, green: 0.32, blue: 0.12)
}
