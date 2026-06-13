import SwiftUI
import SwiftData

struct OnboardingSetupView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(AuthManager.self) private var authManager
    @Environment(SyncManager.self) private var syncManager

    let profile: UserProfile
    let onFinished: () -> Void

    @State private var step = 0
    @State private var name: String
    @State private var language: Language
    @State private var proficiencyLevel: Int
    @State private var dailyGoalMinutes: Int
    @State private var isSaving = false
    @State private var errorMessage: String?

    private let dailyGoals = [10, 20, 30, 45, 60]
    private let totalSteps = 4

    init(profile: UserProfile, onFinished: @escaping () -> Void) {
        self.profile = profile
        self.onFinished = onFinished
        _name = State(initialValue: profile.name == "Learner" ? "" : profile.name)
        _language = State(initialValue: profile.currentLanguage)
        _proficiencyLevel = State(initialValue: profile.proficiencyLevel)
        _dailyGoalMinutes = State(initialValue: profile.dailyGoalMinutes)
    }

    var body: some View {
        ZStack {
            LinearGradient(
                colors: [.indigo.opacity(0.14), .purple.opacity(0.08), Color(.systemBackground)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .ignoresSafeArea()

            VStack(spacing: 20) {
                header

                Group {
                    switch step {
                    case 0: nameStep
                    case 1: languageStep
                    case 2: levelStep
                    case 3: goalStep
                    default: welcomeStep
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .transition(.asymmetric(insertion: .move(edge: .trailing), removal: .move(edge: .leading)))

                if let errorMessage {
                    Text(errorMessage)
                        .font(.caption)
                        .foregroundStyle(.red)
                        .multilineTextAlignment(.center)
                }

                controls
            }
            .padding(24)
        }
        .animation(.snappy, value: step)
    }

    private var header: some View {
        HStack {
            if step > 0 && step < totalSteps {
                Button {
                    step -= 1
                } label: {
                    Image(systemName: "chevron.left")
                        .font(.headline)
                        .frame(width: 40, height: 40)
                        .background(.thinMaterial, in: Circle())
                }
            } else {
                Color.clear.frame(width: 40, height: 40)
            }

            Spacer()

            if step < totalSteps {
                HStack(spacing: 6) {
                    ForEach(0..<totalSteps, id: \.self) { index in
                        Capsule()
                            .fill(index <= step ? Color.indigo : Color.secondary.opacity(0.2))
                            .frame(width: index == step ? 28 : 8, height: 8)
                    }
                }
            }

            Spacer()

            Button("Sign Out") {
                authManager.signOut()
            }
            .font(.caption.weight(.semibold))
            .frame(width: 58)
        }
    }

    private var nameStep: some View {
        OnboardingCard(
            icon: "person.crop.circle.fill",
            title: "What should we call you?",
            subtitle: "This is how your learning space will greet you.",
            colors: [.indigo, .purple]
        ) {
            TextField("Your name", text: $name)
                .textContentType(.name)
                .font(.title2.bold())
                .padding()
                .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 16))
        }
    }

    private var languageStep: some View {
        OnboardingCard(
            icon: "globe.americas.fill",
            title: "Choose your language",
            subtitle: "Pick the language you want to understand and use.",
            colors: [.blue, .cyan]
        ) {
            LazyVGrid(columns: [.init(.flexible()), .init(.flexible())], spacing: 12) {
                ForEach(Language.allCases) { option in
                    SelectionCard(isSelected: language == option) {
                        language = option
                    } content: {
                        Text(option.flag).font(.system(size: 36))
                        Text(option.displayName).font(.headline)
                    }
                }
            }
        }
    }

    private var levelStep: some View {
        OnboardingCard(
            icon: "chart.bar.fill",
            title: "Where are you now?",
            subtitle: "Choose your closest level. You can change it anytime.",
            colors: [.purple, .pink]
        ) {
            VStack(spacing: 10) {
                ForEach(1...6, id: \.self) { level in
                    SelectionCard(isSelected: proficiencyLevel == level) {
                        proficiencyLevel = level
                    } content: {
                        HStack {
                            Text("\(level)")
                                .font(.headline)
                                .frame(width: 34, height: 34)
                                .background(Color.indigo.opacity(0.12), in: Circle())
                            Text(LevelManager.shared.displayString(
                                level: level,
                                language: language.code,
                                preferredScale: .simple
                            ))
                            .font(.headline)
                            Spacer()
                        }
                    }
                }
            }
        }
    }

    private var goalStep: some View {
        OnboardingCard(
            icon: "target",
            title: "Set your daily rhythm",
            subtitle: "A realistic goal makes consistency much easier.",
            colors: [.orange, .red]
        ) {
            VStack(spacing: 12) {
                ForEach(dailyGoals, id: \.self) { minutes in
                    SelectionCard(isSelected: dailyGoalMinutes == minutes) {
                        dailyGoalMinutes = minutes
                    } content: {
                        HStack {
                            Image(systemName: minutes <= 20 ? "leaf.fill" : minutes <= 30 ? "flame.fill" : "bolt.fill")
                                .foregroundStyle(.orange)
                            Text("\(minutes) minutes")
                                .font(.headline)
                            Spacer()
                            Text(goalDescription(minutes))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }
        }
    }

    private var welcomeStep: some View {
        VStack(spacing: 26) {
            Spacer()
            Text(language.flag)
                .font(.system(size: 88))
            Text("\(language.greetingPrefix) \(name.trimmingCharacters(in: .whitespacesAndNewlines))!")
                .font(.system(size: 38, weight: .heavy, design: .rounded))
                .multilineTextAlignment(.center)
            Text("Your \(LevelManager.shared.displayString(level: proficiencyLevel, language: language.code, preferredScale: .simple)) plan is ready, with a \(dailyGoalMinutes)-minute daily goal.")
                .font(.title3)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            Spacer()
        }
    }

    @ViewBuilder
    private var controls: some View {
        Button {
            if step < totalSteps - 1 {
                step += 1
            } else if step == totalSteps - 1 {
                saveProfile()
            } else {
                onFinished()
            }
        } label: {
            Group {
                if isSaving {
                    ProgressView().tint(.white)
                } else {
                    HStack {
                        Text(step < totalSteps - 1 ? "Continue" : step == totalSteps - 1 ? "Build My Plan" : "Enter LearnCI")
                        Image(systemName: "arrow.right")
                    }
                    .font(.headline)
                }
            }
            .frame(maxWidth: .infinity)
            .padding()
        }
        .buttonStyle(.plain)
        .foregroundStyle(.white)
        .background(.indigo, in: RoundedRectangle(cornerRadius: 18))
        .disabled(!canContinue || isSaving)
        .opacity(canContinue ? 1 : 0.55)
    }

    private var canContinue: Bool {
        step != 0 || !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private func saveProfile() {
        guard !isSaving else { return }
        isSaving = true
        errorMessage = nil

        profile.completeOnboarding(
            name: name,
            language: language,
            proficiencyLevel: proficiencyLevel,
            dailyGoalMinutes: dailyGoalMinutes
        )

        Task {
            do {
                try modelContext.save()
                try await syncManager.syncCurrentProfile(modelContext: modelContext)
                step = totalSteps
            } catch {
                profile.onboardingVersion = 0
                profile.onboardingCompletedAt = nil
                try? modelContext.save()
                errorMessage = "We couldn’t save your profile yet. Check your connection and try again."
            }
            isSaving = false
        }
    }

    private func goalDescription(_ minutes: Int) -> String {
        switch minutes {
        case ...10: return "Light"
        case ...20: return "Steady"
        case ...30: return "Focused"
        case ...45: return "Strong"
        default: return "Intensive"
        }
    }
}

private struct OnboardingCard<Content: View>: View {
    let icon: String
    let title: String
    let subtitle: String
    let colors: [Color]
    @ViewBuilder let content: Content

    init(
        icon: String,
        title: String,
        subtitle: String,
        colors: [Color],
        @ViewBuilder content: () -> Content
    ) {
        self.icon = icon
        self.title = title
        self.subtitle = subtitle
        self.colors = colors
        self.content = content()
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 22) {
                Image(systemName: icon)
                    .font(.system(size: 52))
                    .foregroundStyle(.white)
                    .frame(width: 110, height: 110)
                    .background(
                        LinearGradient(colors: colors, startPoint: .topLeading, endPoint: .bottomTrailing),
                        in: RoundedRectangle(cornerRadius: 30)
                    )
                    .shadow(color: colors[0].opacity(0.25), radius: 18, y: 10)

                VStack(spacing: 8) {
                    Text(title)
                        .font(.system(size: 30, weight: .heavy, design: .rounded))
                    Text(subtitle)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }

                content
            }
            .padding(.vertical, 12)
        }
        .scrollIndicators(.hidden)
    }
}

private struct SelectionCard<Content: View>: View {
    let isSelected: Bool
    let action: () -> Void
    @ViewBuilder let content: Content

    init(isSelected: Bool, action: @escaping () -> Void, @ViewBuilder content: () -> Content) {
        self.isSelected = isSelected
        self.action = action
        self.content = content()
    }

    var body: some View {
        Button(action: action) {
            VStack(spacing: 8) {
                content
            }
            .frame(maxWidth: .infinity)
            .padding()
            .background(
                isSelected ? Color.indigo.opacity(0.13) : Color(.secondarySystemBackground),
                in: RoundedRectangle(cornerRadius: 16)
            )
            .overlay {
                RoundedRectangle(cornerRadius: 16)
                    .stroke(isSelected ? Color.indigo : .clear, lineWidth: 2)
            }
        }
        .buttonStyle(.plain)
    }
}

#Preview {
    OnboardingSetupView(profile: UserProfile()) {}
        .environment(AuthManager())
        .environment(SyncManager(authManager: AuthManager()))
        .modelContainer(for: UserProfile.self, inMemory: true)
}
