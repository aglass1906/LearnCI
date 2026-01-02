import SwiftUI
import SwiftData

struct DashboardView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \UserActivity.date, order: .reverse) private var activities: [UserActivity]
    @Query private var profiles: [UserProfile]
    
    var userProfile: UserProfile? {
        profiles.first
    }
    
    var totalMinutes: Int {
        activities.reduce(0) { $0 + $1.minutes }
    }
    
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {
                    // Header
                    if let profile = userProfile {
                        HStack {
                            Text("Hola, \(profile.name)!")
                                .font(.largeTitle)
                                .fontWeight(.bold)
                            Spacer()
                            Text(profile.currentLanguage.flag)
                                .font(.largeTitle)
                        }
                        .padding()
                    }
                    
                    // Stats Card
                    VStack {
                        Text("Total Learning Time")
                            .font(.headline)
                            .foregroundColor(.secondary)
                        Text("\(totalMinutes) min")
                            .font(.system(size: 48, weight: .bold, design: .rounded))
                            .foregroundColor(.blue)
                    }
                    .padding()
                    .frame(maxWidth: .infinity)
                    .background(Color.blue.opacity(0.1))
                    .cornerRadius(12)
                    .padding(.horizontal)
                    
                    // Interactive placeholder for charts
                    HStack {
                        Text("Recent Activity")
                            .font(.title2)
                        Spacer()
                    }
                    .padding(.horizontal)
                    .padding(.top)
                    
                    if activities.isEmpty {
                        Text("No activities recorded yet.")
                            .foregroundColor(.secondary)
                            .padding()
                    } else {
                        VStack(spacing: 0) {
                            ForEach(activities.prefix(5)) { activity in
                                HStack {
                                    VStack(alignment: .leading) {
                                        Text(activity.activityType.rawValue)
                                            .font(.headline)
                                        Text(activity.date.formatted(date: .abbreviated, time: .shortened))
                                            .font(.caption)
                                            .foregroundColor(.secondary)
                                    }
                                    Spacer()
                                    Text("\(activity.minutes) min")
                                        .fontWeight(.bold)
                                        .foregroundColor(.green)
                                }
                                .padding()
                                .background(Color(UIColor.secondarySystemGroupedBackground))
                                .cornerRadius(10)
                                .padding(.horizontal)
                                .padding(.vertical, 4)
                            }
                        }
                    }
                }
            }
            .navigationTitle("Dashboard")
        }
    }
}
