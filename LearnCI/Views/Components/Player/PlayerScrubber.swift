import SwiftUI

/// Custom seek bar with elapsed/remaining labels, chapter ticks, and a chapter-name
/// callout while dragging.
struct PlayerScrubber: View {
    let position: TimeInterval
    let duration: TimeInterval
    var chapters: [PlaybackChapter] = []
    var isEnabled: Bool = true
    var showsRemaining: Bool = true
    var accessibilityStep: TimeInterval = 15
    let onSeek: (TimeInterval) -> Void

    @State private var isDragging = false
    @State private var dragFraction: Double = 0

    private var fraction: Double {
        guard duration > 0 else { return 0 }
        let raw = isDragging ? dragFraction : position / duration
        return min(max(raw, 0), 1)
    }

    private var displayedTime: TimeInterval { fraction * duration }

    private var draggedChapterIndex: Int? {
        isDragging ? chapters.chapterIndex(at: displayedTime) : nil
    }

    var body: some View {
        VStack(spacing: 6) {
            chapterCallout
            track
            HStack {
                Text(PlayerTimeFormat.clock(displayedTime))
                Spacer()
                Text(showsRemaining
                     ? "-" + PlayerTimeFormat.clock(max(0, duration - displayedTime))
                     : PlayerTimeFormat.clock(duration))
            }
            .font(PlayerTheme.timeFont)
            .foregroundStyle(PlayerTheme.secondaryText)
        }
        .sensoryFeedback(.selection, trigger: draggedChapterIndex)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Playback position")
        .accessibilityValue("\(PlayerTimeFormat.clock(position)) of \(PlayerTimeFormat.clock(duration))")
        .accessibilityAdjustableAction { direction in
            guard isEnabled, duration > 0 else { return }
            switch direction {
            case .increment: onSeek(min(duration, position + accessibilityStep))
            case .decrement: onSeek(max(0, position - accessibilityStep))
            @unknown default: break
            }
        }
    }

    @ViewBuilder
    private var chapterCallout: some View {
        if let i = draggedChapterIndex, chapters.indices.contains(i) {
            Text(chapters[i].title)
                .font(.system(.footnote, design: .rounded).weight(.semibold))
                .foregroundStyle(PlayerTheme.primaryText)
                .lineLimit(1)
                .padding(.horizontal, 10)
                .padding(.vertical, 4)
                .background(.ultraThinMaterial, in: Capsule())
                .transition(.opacity)
        } else {
            Color.clear.frame(height: 22)
        }
    }

    private var track: some View {
        GeometryReader { geo in
            let width = geo.size.width
            let thumb = isDragging ? PlayerTheme.thumbDiameter * 1.4 : PlayerTheme.thumbDiameter
            ZStack(alignment: .leading) {
                Capsule()
                    .fill(PlayerTheme.trackBackground)
                    .frame(height: PlayerTheme.trackHeight)
                Capsule()
                    .fill(Color.white)
                    .frame(width: max(0, width * fraction), height: PlayerTheme.trackHeight)

                if duration > 0 {
                    ForEach(chapters.dropFirst()) { chapter in
                        Rectangle()
                            .fill(Color.black.opacity(0.45))
                            .frame(width: 2, height: PlayerTheme.trackHeight)
                            .offset(x: width * min(max(chapter.startTime / duration, 0), 1) - 1)
                    }
                }

                Circle()
                    .fill(Color.white)
                    .frame(width: thumb, height: thumb)
                    .shadow(color: .black.opacity(0.3), radius: 4, y: 2)
                    .offset(x: width * fraction - thumb / 2)
                    .animation(.easeOut(duration: 0.12), value: isDragging)
            }
            .frame(height: geo.size.height)
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        guard isEnabled, duration > 0, width > 0 else { return }
                        isDragging = true
                        dragFraction = min(max(value.location.x / width, 0), 1)
                    }
                    .onEnded { value in
                        guard isEnabled, duration > 0, width > 0 else {
                            isDragging = false
                            return
                        }
                        let f = min(max(value.location.x / width, 0), 1)
                        onSeek(f * duration)
                        isDragging = false
                    }
            )
        }
        .frame(height: 28)
        .opacity(isEnabled ? 1 : 0.5)
    }
}
