import SwiftUI

enum PodcastTranscriptTimelineZoom: TimeInterval, CaseIterable, Identifiable {
    case oneMinute = 60
    case threeMinutes = 180
    case fiveMinutes = 300
    case tenMinutes = 600

    var id: TimeInterval { rawValue }

    var label: String {
        switch self {
        case .oneMinute: return "1m"
        case .threeMinutes: return "3m"
        case .fiveMinutes: return "5m"
        case .tenMinutes: return "10m"
        }
    }
}

struct PodcastTranscriptSyncTimelineView: View {
    let audioURL: URL
    let duration: TimeInterval
    let currentTime: TimeInterval
    let blocks: [StudyBlock]
    let transcriptOffset: TimeInterval
    let contentStart: TimeInterval
    let onSeek: (TimeInterval) -> Void
    let onOffsetChange: (TimeInterval) -> Void

    @State private var waveform: [Float] = []
    @State private var isLoadingWaveform = false
    @State private var dragStartOffset: TimeInterval = 0
    @State private var dragTranslationSeconds: TimeInterval = 0
    @State private var isDraggingTranscript = false
    @State private var zoomSpan: PodcastTranscriptTimelineZoom = .threeMinutes
    @State private var followsPlayhead = true
    @State private var manualCenterTime: TimeInterval?

    private var effectiveOffset: TimeInterval {
        transcriptOffset + (isDraggingTranscript ? dragTranslationSeconds : 0)
    }

    private var windowCenter: TimeInterval {
        if followsPlayhead {
            return currentTime
        }
        return manualCenterTime ?? currentTime
    }

    private var window: (start: TimeInterval, end: TimeInterval) {
        PodcastTranscriptSyncTimelineLayout.fixedSpanWindow(
            duration: duration,
            centerTime: windowCenter,
            span: zoomSpan.rawValue
        )
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            legend

            GeometryReader { geometry in
                let width = max(geometry.size.width, 1)
                let height = geometry.size.height
                let windowStart = window.start
                let windowDuration = max(1, window.end - windowStart)

                ZStack(alignment: .topLeading) {
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(Color(UIColor.tertiarySystemGroupedBackground))

                    timelineCanvas(
                        width: width,
                        height: height,
                        windowStart: windowStart,
                        windowDuration: windowDuration
                    )

                    playheadLine(
                        width: width,
                        height: height,
                        windowStart: windowStart,
                        windowDuration: windowDuration,
                        time: currentTime
                    )

                    if contentStart > 0 {
                        markerLine(
                            width: width,
                            height: height,
                            windowStart: windowStart,
                            windowDuration: windowDuration,
                            time: contentStart,
                            color: .orange,
                            label: "AI start"
                        )
                    }
                }
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                .contentShape(Rectangle())
                .gesture(scrubGesture(width: width, windowStart: windowStart, windowDuration: windowDuration))
            }
            .frame(height: 132)

            timeAxisLabels

            timelineControls

            if isLoadingWaveform {
                HStack(spacing: 8) {
                    ProgressView().controlSize(.small)
                    Text("Loading audio waveform…")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .task(id: waveformTaskKey) {
            await loadWaveform()
        }
        .onAppear {
            centerOnTranscriptIfNeeded()
        }
        .onChange(of: blocks.count) { _, _ in
            centerOnTranscriptIfNeeded()
        }
    }

    private var timelineControls: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 6) {
                Text("Zoom")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .frame(width: 44, alignment: .leading)

                ForEach(PodcastTranscriptTimelineZoom.allCases) { span in
                    Button {
                        zoomSpan = span
                    } label: {
                        Text(span.label)
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(zoomSpan == span ? .white : .primary)
                            .frame(minWidth: 36)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 8)
                            .background(zoomSpan == span ? Color.blue : Color(UIColor.tertiarySystemFill))
                            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                    }
                    .buttonStyle(.plain)
                }
            }

            HStack(spacing: 8) {
                Text("Pan")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .frame(width: 44, alignment: .leading)

                Button {
                    panWindow(by: -panStepSeconds)
                } label: {
                    Label("Earlier", systemImage: "chevron.left")
                        .font(.caption.weight(.semibold))
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .controlSize(.regular)

                Button {
                    panWindow(by: panStepSeconds)
                } label: {
                    Label("Later", systemImage: "chevron.right")
                        .font(.caption.weight(.semibold))
                        .labelStyle(.titleAndIcon)
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .controlSize(.regular)
            }

            HStack(spacing: 8) {
                Text("Center")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .frame(width: 44, alignment: .leading)

                Button {
                    centerOnTranscript()
                } label: {
                    Label("Transcript", systemImage: "text.alignleft")
                        .font(.caption.weight(.semibold))
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)

                Button {
                    followsPlayhead = true
                    manualCenterTime = nil
                } label: {
                    Label("Playhead", systemImage: followsPlayhead
                        ? "dot.circle.and.hand.point.up.left.fill"
                        : "dot.circle.and.hand.point.up.left")
                        .font(.caption.weight(.semibold))
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .tint(followsPlayhead ? .blue : nil)
            }

            Text("Pan moves the \(zoomSpan.label) window by \(Int(panStepSeconds))s per tap.")
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .padding(10)
        .background(Color(UIColor.systemBackground).opacity(0.5))
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
    }

    private var panStepSeconds: TimeInterval {
        zoomSpan.rawValue / 4
    }

    private func centerOnTranscriptIfNeeded() {
        guard !blocks.isEmpty else { return }
        let anchor = transcriptAnchorTime
        if abs(currentTime - anchor) > zoomSpan.rawValue * 0.4 {
            centerOnTranscript()
        }
    }

    private var transcriptAnchorTime: TimeInterval {
        (blocks.first?.mediaStart ?? 0) + effectiveOffset
    }

    private func centerOnTranscript() {
        followsPlayhead = false
        manualCenterTime = transcriptAnchorTime
    }

    private func panWindow(by delta: TimeInterval) {
        followsPlayhead = false
        let center = manualCenterTime ?? currentTime
        manualCenterTime = PodcastTranscriptSyncTimelineLayout.clampedCenter(
            center + delta,
            span: zoomSpan.rawValue,
            duration: duration
        )
    }

    private var waveformTaskKey: String {
        let windowStart = window.start
        let windowEnd = window.end
        return "\(audioURL.absoluteString)-\(Int(windowStart))-\(Int(windowEnd))"
    }

    private var legend: some View {
        HStack(spacing: 12) {
            legendItem(color: .white.opacity(0.85), label: "Audio")
            legendItem(color: Color.cyan.opacity(0.85), label: "Transcript")
            legendItem(color: .red, label: "Playhead", symbol: "line.diagonal")
            if contentStart > 0 {
                legendItem(color: .orange, label: "AI start", symbol: "line.diagonal")
            }
        }
        .font(.caption2)
        .foregroundStyle(.secondary)
    }

    private func legendItem(color: Color, label: String, symbol: String = "square.fill") -> some View {
        HStack(spacing: 4) {
            Image(systemName: symbol)
                .font(.caption2)
                .foregroundStyle(color)
            Text(label)
        }
    }

    private func timelineCanvas(
        width: CGFloat,
        height: CGFloat,
        windowStart: TimeInterval,
        windowDuration: TimeInterval
    ) -> some View {
        Canvas { context, size in
            drawWaveform(
                context: &context,
                size: size,
                windowStart: windowStart,
                windowDuration: windowDuration
            )
            drawTranscriptBlocks(
                context: &context,
                size: size,
                windowStart: windowStart,
                windowDuration: windowDuration,
                offset: effectiveOffset
            )
        }
        .overlay {
            transcriptDragOverlay(
                width: width,
                height: height,
                windowStart: windowStart,
                windowDuration: windowDuration
            )
        }
    }

    private func drawWaveform(
        context: inout GraphicsContext,
        size: CGSize,
        windowStart: TimeInterval,
        windowDuration: TimeInterval
    ) {
        guard !waveform.isEmpty else { return }

        let laneHeight = size.height * 0.48
        let baseline = laneHeight * 0.92
        let barWidth = size.width / CGFloat(waveform.count)

        for (index, peak) in waveform.enumerated() {
            let x = CGFloat(index) * barWidth
            let barHeight = max(2, CGFloat(peak) * laneHeight * 0.85)
            let rect = CGRect(
                x: x,
                y: baseline - barHeight,
                width: max(1, barWidth * 0.85),
                height: barHeight
            )
            context.fill(
                Path(roundedRect: rect, cornerRadius: 1),
                with: .color(.white.opacity(0.55 + Double(peak) * 0.35))
            )
        }
    }

    private func drawTranscriptBlocks(
        context: inout GraphicsContext,
        size: CGSize,
        windowStart: TimeInterval,
        windowDuration: TimeInterval,
        offset: TimeInterval
    ) {
        let laneTop = size.height * 0.56
        let laneHeight = size.height * 0.38

        for block in blocks {
            let start = block.mediaStart + offset
            let end = block.mediaEnd + offset
            guard end >= windowStart, start <= windowStart + windowDuration else { continue }

            let xStart = PodcastTranscriptSyncTimelineLayout.xPosition(
                for: start,
                windowStart: windowStart,
                windowDuration: windowDuration,
                width: size.width
            )
            let xEnd = PodcastTranscriptSyncTimelineLayout.xPosition(
                for: end,
                windowStart: windowStart,
                windowDuration: windowDuration,
                width: size.width
            )
            let rect = CGRect(
                x: min(xStart, xEnd),
                y: laneTop,
                width: max(3, abs(xEnd - xStart)),
                height: laneHeight
            )
            context.fill(
                Path(roundedRect: rect, cornerRadius: 3),
                with: .color(Color.cyan.opacity(isDraggingTranscript ? 0.95 : 0.72))
            )
        }
    }

    private func playheadLine(
        width: CGFloat,
        height: CGFloat,
        windowStart: TimeInterval,
        windowDuration: TimeInterval,
        time: TimeInterval
    ) -> some View {
        let x = PodcastTranscriptSyncTimelineLayout.xPosition(
            for: time,
            windowStart: windowStart,
            windowDuration: windowDuration,
            width: width
        )

        return Group {
            if x >= 0, x <= width {
                Rectangle()
                    .fill(Color.red)
                    .frame(width: 2, height: height)
                    .position(x: x, y: height / 2)
            }
        }
    }

    private func markerLine(
        width: CGFloat,
        height: CGFloat,
        windowStart: TimeInterval,
        windowDuration: TimeInterval,
        time: TimeInterval,
        color: Color,
        label: String
    ) -> some View {
        let x = PodcastTranscriptSyncTimelineLayout.xPosition(
            for: time,
            windowStart: windowStart,
            windowDuration: windowDuration,
            width: width
        )

        return Group {
            if x >= 0, x <= width {
                VStack(spacing: 2) {
                    Text(label)
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundStyle(color)
                    Rectangle()
                        .fill(color.opacity(0.85))
                        .frame(width: 1.5, height: height - 14)
                }
                .position(x: x, y: height / 2 + 4)
            }
        }
    }

    private func transcriptDragOverlay(
        width: CGFloat,
        height: CGFloat,
        windowStart: TimeInterval,
        windowDuration: TimeInterval
    ) -> some View {
        let laneTop = height * 0.56
        let laneHeight = height * 0.38

        return Color.clear
            .frame(width: width, height: laneHeight)
            .position(x: width / 2, y: laneTop + laneHeight / 2)
            .contentShape(Rectangle())
            .gesture(transcriptDragGesture(width: width, windowDuration: windowDuration))
            .overlay(alignment: .leading) {
                transcriptDragHandle(
                    width: width,
                    height: height,
                    windowStart: windowStart,
                    windowDuration: windowDuration
                )
            }
    }

    private func transcriptDragHandle(
        width: CGFloat,
        height: CGFloat,
        windowStart: TimeInterval,
        windowDuration: TimeInterval
    ) -> some View {
        let anchorTime = (blocks.first?.mediaStart ?? windowStart) + effectiveOffset
        let x = PodcastTranscriptSyncTimelineLayout.xPosition(
            for: anchorTime,
            windowStart: windowStart,
            windowDuration: windowDuration,
            width: width
        )

        return RoundedRectangle(cornerRadius: 4, style: .continuous)
            .fill(Color.cyan.opacity(0.95))
            .frame(width: 14, height: height * 0.38)
            .overlay {
                Image(systemName: "line.3.horizontal")
                    .font(.system(size: 8, weight: .bold))
                    .foregroundStyle(.black.opacity(0.65))
            }
            .position(x: min(max(10, x), width - 10), y: height * 0.75)
            .shadow(color: .black.opacity(0.25), radius: 2, y: 1)
            .allowsHitTesting(false)
            .accessibilityHidden(true)
    }

    private func transcriptDragGesture(width: CGFloat, windowDuration: TimeInterval) -> some Gesture {
        DragGesture(minimumDistance: 2)
            .onChanged { value in
                if !isDraggingTranscript {
                    isDraggingTranscript = true
                    dragStartOffset = transcriptOffset
                }
                dragTranslationSeconds = TimeInterval(value.translation.width / width) * windowDuration
                let preview = min(600, max(-600, dragStartOffset + dragTranslationSeconds))
                onOffsetChange(preview)
            }
            .onEnded { value in
                let delta = TimeInterval(value.translation.width / width) * windowDuration
                let finalOffset = min(600, max(-600, dragStartOffset + delta))
                isDraggingTranscript = false
                dragTranslationSeconds = 0
                onOffsetChange(finalOffset)
            }
    }

    private func scrubGesture(
        width: CGFloat,
        windowStart: TimeInterval,
        windowDuration: TimeInterval
    ) -> some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { value in
                guard !isDraggingTranscript else { return }
                let fraction = min(max(0, value.location.x / width), 1)
                let time = windowStart + TimeInterval(fraction) * windowDuration
                onSeek(time)
            }
    }

    private var timeAxisLabels: some View {
        HStack {
            Text(PodcastStudyContentStart.formattedTimestamp(window.start))
            Spacer()
            VStack(spacing: 2) {
                Text(PodcastStudyContentStart.formattedTimestamp(currentTime))
                    .foregroundStyle(.red)
                Text("\(zoomSpan.label) window")
                    .font(.system(size: 9))
                    .foregroundStyle(.tertiary)
            }
            Spacer()
            Text(PodcastStudyContentStart.formattedTimestamp(window.end))
        }
        .font(.caption2.monospacedDigit())
        .foregroundStyle(.secondary)
    }

    private func loadWaveform() async {
        isLoadingWaveform = true
        defer { isLoadingWaveform = false }

        let windowStart = window.start
        let windowEnd = window.end
        let envelope = await AudioWaveformEnvelopeLoader.load(
            url: audioURL,
            startSeconds: windowStart,
            endSeconds: windowEnd
        )

        await MainActor.run {
            waveform = envelope
        }
    }
}

enum PodcastTranscriptSyncTimelineLayout {
    static func fixedSpanWindow(
        duration: TimeInterval,
        centerTime: TimeInterval,
        span: TimeInterval
    ) -> (start: TimeInterval, end: TimeInterval) {
        let safeSpan = max(30, span)
        let halfSpan = safeSpan / 2
        let clampedCenter = clampedCenter(centerTime, span: safeSpan, duration: duration)

        var start = clampedCenter - halfSpan
        var end = clampedCenter + halfSpan

        if duration > safeSpan {
            start = max(0, start)
            end = min(duration, end)
            if end - start < safeSpan {
                if start == 0 {
                    end = min(duration, safeSpan)
                } else {
                    start = max(0, duration - safeSpan)
                    end = duration
                }
            }
        } else if duration > 1 {
            start = 0
            end = duration
        }

        return (start, max(start + 1, end))
    }

    static func clampedCenter(
        _ centerTime: TimeInterval,
        span: TimeInterval,
        duration: TimeInterval
    ) -> TimeInterval {
        let safeSpan = max(30, span)
        let halfSpan = safeSpan / 2

        if duration <= safeSpan {
            return max(0, duration / 2)
        }

        return min(max(halfSpan, centerTime), duration - halfSpan)
    }

    static func xPosition(
        for time: TimeInterval,
        windowStart: TimeInterval,
        windowDuration: TimeInterval,
        width: CGFloat
    ) -> CGFloat {
        let fraction = (time - windowStart) / windowDuration
        return CGFloat(fraction) * width
    }
}
