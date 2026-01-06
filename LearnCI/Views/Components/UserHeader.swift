import SwiftUI
import SwiftData

struct UserHeader: View {
    @Environment(AuthManager.self) private var authManager
    @Environment(\.modelContext) private var modelContext
    
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
                // User Name
                HStack(spacing: 8) {
                    Image(systemName: "person.circle.fill")
                        .font(.title2)
                        .foregroundStyle(.secondary)
                    Text(profile.name)
                        .font(.headline)
                        .fontWeight(.bold)
                }
                
                Spacer()
                
                // Language Flag
                Text(profile.currentLanguage.flag)
                    .font(.title2)
                
                // Today's Minutes
                HStack(spacing: 4) {
                    Image(systemName: "clock.fill")
                        .font(.subheadline)
                        .foregroundStyle(.blue)
                    Text("\(todayMinutes)m")
                        .font(.headline)
                        .monospacedDigit()
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(Color.blue.opacity(0.1))
                .clipShape(Capsule())
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
    UserHeader()
        .environment(AuthManager())
}
