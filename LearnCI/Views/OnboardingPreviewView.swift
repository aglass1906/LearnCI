import SwiftUI

struct OnboardingPreviewView: View {
    let onFinished: () -> Void

    @State private var page = 0

    private let pages = [
        PreviewPage(
            title: "Understand More",
            subtitle: "Learn through stories, videos, and podcasts made understandable at your level.",
            icon: "brain.head.profile.fill",
            colors: [.indigo, .blue]
        ),
        PreviewPage(
            title: "Hear Every Moment",
            subtitle: "Follow dramatized audio, synchronized words, and cinematic visuals.",
            icon: "waveform.and.person.filled",
            colors: [.purple, .pink]
        ),
        PreviewPage(
            title: "Make It Stick",
            subtitle: "Turn useful language into playful practice and visible daily progress.",
            icon: "gamecontroller.fill",
            colors: [.orange, .red]
        )
    ]

    var body: some View {
        ZStack {
            LinearGradient(
                colors: pages[page].colors.map { $0.opacity(0.95) },
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .ignoresSafeArea()
            .animation(.easeInOut, value: page)

            VStack(spacing: 24) {
                HStack {
                    Spacer()
                    Button("Skip") {
                        onFinished()
                    }
                    .foregroundStyle(.white.opacity(0.9))
                }

                TabView(selection: $page) {
                    ForEach(Array(pages.enumerated()), id: \.offset) { index, item in
                        VStack(spacing: 32) {
                            Spacer()

                            ZStack {
                                RoundedRectangle(cornerRadius: 44)
                                    .fill(.ultraThinMaterial)
                                    .frame(width: 260, height: 260)
                                    .rotationEffect(.degrees(index == 1 ? 4 : -4))

                                Image(systemName: item.icon)
                                    .font(.system(size: 105))
                                    .foregroundStyle(.white, .yellow)
                                    .symbolEffect(.bounce, value: page)
                            }
                            .shadow(color: .black.opacity(0.2), radius: 24, y: 14)

                            VStack(spacing: 14) {
                                Text(item.title)
                                    .font(.system(size: 38, weight: .heavy, design: .rounded))
                                    .foregroundStyle(.white)

                                Text(item.subtitle)
                                    .font(.title3)
                                    .foregroundStyle(.white.opacity(0.86))
                                    .multilineTextAlignment(.center)
                                    .lineSpacing(4)
                            }

                            Spacer()
                        }
                        .padding(.horizontal, 8)
                        .tag(index)
                    }
                }
                .tabViewStyle(.page(indexDisplayMode: .never))

                HStack(spacing: 8) {
                    ForEach(pages.indices, id: \.self) { index in
                        Capsule()
                            .fill(.white.opacity(index == page ? 1 : 0.35))
                            .frame(width: index == page ? 30 : 8, height: 8)
                            .animation(.spring, value: page)
                    }
                }

                Button {
                    if page == pages.count - 1 {
                        onFinished()
                    } else {
                        withAnimation { page += 1 }
                    }
                } label: {
                    HStack {
                        Text(page == pages.count - 1 ? "Get Started" : "Continue")
                        Image(systemName: "arrow.right")
                    }
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .padding()
                }
                .buttonStyle(.plain)
                .foregroundStyle(pages[page].colors[0])
                .background(.white, in: RoundedRectangle(cornerRadius: 18))
            }
            .padding(24)
        }
    }
}

private struct PreviewPage {
    let title: String
    let subtitle: String
    let icon: String
    let colors: [Color]
}

#Preview {
    OnboardingPreviewView {}
}
