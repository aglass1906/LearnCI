import SwiftUI
import SwiftData

struct HistoryView: View {
    @Environment(AuthManager.self) private var authManager
    @Query(sort: \UserActivity.date, order: .reverse) private var allActivities: [UserActivity]
    
    var activities: [UserActivity] {
        allActivities.filter { $0.userID == authManager.currentUser }
    }
    
    @State private var selectedTimeRange: TimeRange = .week
    @State private var selectedActivityType: ActivityType? = nil
    @State private var editingActivity: UserActivity?
    @State private var isAddingActivity: Bool = false
    
    enum TimeRange: String, CaseIterable, Identifiable {
        case today = "Today"
        case week = "Week"
        case month = "Month"
        case all = "All"
        
        var id: String { rawValue }
    }
    
    var filteredActivities: [UserActivity] {
        let now = Date()
        let calendar = Calendar.current
        
        return activities.filter { activity in
            // Filter by Type
            if let type = selectedActivityType, activity.activityType != type {
                return false
            }
            
            // Filter by Time
            switch selectedTimeRange {
            case .today:
                return calendar.isDateInToday(activity.date)
            case .week:
                // last 7 days including today
                guard let weekAgo = calendar.date(byAdding: .day, value: -7, to: now) else { return true }
                return activity.date >= weekAgo
            case .month:
                // last 30 days
                guard let monthAgo = calendar.date(byAdding: .day, value: -30, to: now) else { return true }
                return activity.date >= monthAgo
            case .all:
                return true
            }
        }
    }
    
    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // Filters
                VStack(spacing: 12) {
                    Picker("Time Range", selection: $selectedTimeRange) {
                        ForEach(TimeRange.allCases) { range in
                            Text(range.rawValue).tag(range)
                        }
                    }
                    .pickerStyle(.segmented)
                    
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack {
                            FilterChip(title: "All Types", isSelected: selectedActivityType == nil) {
                                selectedActivityType = nil
                            }
                            
                            ForEach(ActivityType.allCases) { type in
                                FilterChip(title: type.rawValue, isSelected: selectedActivityType == type) {
                                    selectedActivityType = type
                                }
                            }
                        }
                        .padding(.horizontal)
                    }
                }
                .padding(.vertical)
                .background(Color(UIColor.systemGroupedBackground))
                
                // Details
                if filteredActivities.isEmpty {
                   ContentUnavailableView("No History", systemImage: "clock.arrow.circlepath", description: Text("No activities found for this period."))
                } else {
                    List {
                        ForEach(filteredActivities) { activity in
                            HStack(alignment: .top, spacing: 12) {
                                Image(systemName: activity.activityType.icon)
                                    .font(.title2)
                                    .foregroundStyle(activity.activityType.isInput ? .green : .blue)
                                    .frame(width: 32)
                                
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(activity.activityTypeRaw)
                                        .font(.headline)
                                    Text(activity.date.formatted(date: .abbreviated, time: .shortened))
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                    
                                    if let comment = activity.comment, !comment.isEmpty {
                                        Text(comment)
                                            .font(.caption)
                                            .foregroundStyle(.primary.opacity(0.7))
                                            .italic()
                                            .lineLimit(2)
                                    }
                                }
                                
                                Spacer()
                                
                                Text("\(activity.minutes) min")
                                    .fontWeight(.bold)
                                    .padding(8)
                                    .background(activity.activityType.isInput ? Color.green.opacity(0.1) : Color.blue.opacity(0.1))
                                    .cornerRadius(8)
                            }
                            .contentShape(Rectangle())
                            .onTapGesture {
                                editingActivity = activity
                            }
                        }
                    }
                    .listStyle(.plain)
                    .sheet(item: $editingActivity) { activity in
                        EditActivityView(activity: activity)
                    }
                    .sheet(isPresented: $isAddingActivity) {
                        AddActivityView()
                    }
                }
            }
            .navigationTitle("Activity")
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button(action: { isAddingActivity = true }) {
                        Image(systemName: "plus")
                    }
                }
            }
        }
    }
}

struct FilterChip: View {
    let title: String
    let isSelected: Bool
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.subheadline)
                .fontWeight(isSelected ? .semibold : .regular)
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(isSelected ? Color.blue : Color.gray.opacity(0.2))
                .foregroundColor(isSelected ? .white : .primary)
                .cornerRadius(20)
        }
    }
}

#Preview {
    HistoryView()
        .environment(DataManager())
        .environment(YouTubeManager())
        .environment(AuthManager())
}
