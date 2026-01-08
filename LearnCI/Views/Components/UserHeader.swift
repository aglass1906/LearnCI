import SwiftUI
import SwiftData

struct UserHeader: View {
    @Environment(AuthManager.self) private var authManager
    @Environment(\.modelContext) private var modelContext
    @Binding var showProfile: Bool
    @Binding var currentTab: AppTab
    
    @Query private var allProfiles: [UserProfile]
    @Query(sort: \UserActivity.date, order: .reverse) private var allActivities: [UserActivity]
    
    var userProfile: UserProfile? {
        allProfiles.first { $0.userID == authManager.currentUser }
    }
    
    var todayMinutes: Int {
        guard let userId = authManager.currentUser else { return 0 }
        let calendar = Calendar.current
        return allActivities
            .filter { $0.userID == userId && calendar.isDateInToday($0.date) }
            .reduce(0) { $0 + $1.minutes }
    }
    
    var body: some View {
        if let profile = userProfile {
            HStack(spacing: 16) {
                // User Name & Avatar Link
                Button {
                    showProfile = true
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: "person.circle.fill")
                            .font(.title2)
                            .foregroundStyle(.secondary)
                        Text(profile.name)
                            .font(.headline)
                            .fontWeight(.bold)
                            .foregroundStyle(.primary)
                    }
                }
                .buttonStyle(.plain)
                
                Spacer()
                
                // Language Flag
                // Language Switcher
                Menu {
                    ForEach(Language.allCases) { lang in
                        Button {
                            profile.currentLanguage = lang
                            try? modelContext.save()
                        } label: {
                            // Use simple text for system menu reliability
                            Text("\(lang.flag) \(lang.rawValue)")
                        }
                    }
                } label: {
                    HStack(spacing: 4) {
                        Text(profile.currentLanguage.flag)
                            .font(.title2)
                        
                        Image(systemName: "chevron.down")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                    .padding(6)
                    .background(Color.gray.opacity(0.1))
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                }
                
                // Today's Minutes (Click to view History)
                Button {
                    currentTab = .history
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "clock.fill")
                            .font(.subheadline)
                            .foregroundStyle(.blue)
                        Text("\(todayMinutes) / \(profile.dailyGoalMinutes)m")
                            .font(.headline)
                            .monospacedDigit()
                            .foregroundStyle(.primary)
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(Color.blue.opacity(0.1))
                    .clipShape(Capsule())
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal)
            .padding(.vertical, 12)
            .background(Color(UIColor.systemBackground))
            .overlay(
                Rectangle()
                    .frame(height: 1)
                    .foregroundStyle(Color.gray.opacity(0.2)),
                alignment: .bottom
            )
        }
    }
}

#Preview {
    UserHeader(showProfile: .constant(false), currentTab: .constant(.dashboard))
        .environment(AuthManager())
}
