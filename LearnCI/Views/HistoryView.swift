import SwiftUI
import SwiftData

struct HistoryView: View {
    @Environment(AuthManager.self) private var authManager
    @Environment(\.modelContext) private var modelContext
    @Environment(SyncManager.self) private var syncManager
    @Query(sort: \UserActivity.date, order: .reverse) private var allActivities: [UserActivity]
    
    var activities: [UserActivity] {
        allActivities.filter { $0.userID == authManager.currentUser }
    }
    
    @State private var selectedTimeRange: TimeRange = .today
    @State private var selectedActivityType: ActivityType? = nil
    @State private var editingActivity: UserActivity?
    @State private var isAddingActivity: Bool = false
    @State private var showDateRangePicker: Bool = false
    @State private var startDate: Date = Calendar.current.date(byAdding: .day, value: -7, to: Date()) ?? Date()
    @State private var endDate: Date = Date()
    
    enum TimeRange: String, CaseIterable, Identifiable {
        case today = "Today"
        case week = "Week"
        case month = "Month"
        case all = "All"
        case custom = "Custom"
        
        var id: String { rawValue }
    }
    
    struct ActivityGroup: Identifiable {
        let date: Date
        let activities: [UserActivity]
        var id: Date { date }
    }
    
    var filteredActivities: [UserActivity] {
        let now = Date()
        let calendar = Calendar.current
        
        return activities.filter { activity in
            if let type = selectedActivityType, activity.activityType != type {
                return false
            }
            
            switch selectedTimeRange {
            case .today:
                return calendar.isDateInToday(activity.date)
            case .week:
                guard let weekAgo = calendar.date(byAdding: .day, value: -7, to: now) else { return true }
                return activity.date >= weekAgo
            case .month:
                guard let monthAgo = calendar.date(byAdding: .day, value: -30, to: now) else { return true }
                return activity.date >= monthAgo
            case .all:
                return true
            case .custom:
                let start = calendar.startOfDay(for: startDate)
                let end = calendar.date(bySettingHour: 23, minute: 59, second: 59, of: endDate) ?? endDate
                return activity.date >= start && activity.date <= end
            }
        }
    }
    
    var groupedActivities: [ActivityGroup] {
        let calendar = Calendar.current
        let grouped = Dictionary(grouping: filteredActivities) { activity in
            calendar.startOfDay(for: activity.date)
        }
        
        return grouped.map { ActivityGroup(date: $0.key, activities: $0.value) }
            .sorted { $0.date > $1.date }
    }
    
    var totalMinutes: Int {
        filteredActivities.reduce(0) { $0 + $1.minutes }
    }
    
    var topActivityType: ActivityType? {
        let counts = Dictionary(grouping: filteredActivities, by: { $0.activityType })
        return counts.max(by: { a, b in 
            a.value.reduce(0, { $0 + $1.minutes }) < b.value.reduce(0, { $0 + $1.minutes }) 
        })?.key
    }
    
    var inputRatio: Double {
        guard !filteredActivities.isEmpty else { return 0 }
        let inputMins = filteredActivities.filter { $0.activityType.isInput }.reduce(0) { $0 + $1.minutes }
        return Double(inputMins) / Double(totalMinutes)
    }
    
    var activityByType: [ActivityTypeData] {
        let grouped = Dictionary(grouping: filteredActivities, by: { $0.activityType })
        return grouped.map { type, activities in
            ActivityTypeData(
                type: type,
                minutes: activities.reduce(0) { $0 + $1.minutes }
            )
        }.sorted { $0.minutes > $1.minutes }
    }
    
    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // Filters
                VStack(spacing: 12) {
                    HStack {
                        Picker("Time Range", selection: $selectedTimeRange) {
                            ForEach(TimeRange.allCases) { range in
                                Text(range.rawValue).tag(range)
                            }
                        }
                        .pickerStyle(.segmented)
                        
                        Button(action: { showDateRangePicker = true }) {
                            Image(systemName: "calendar")
                                .font(.title3)
                                .padding(8)
                                .background(Color.blue.opacity(0.1))
                                .clipShape(Circle())
                        }
                    }
                    .padding(.horizontal)
                    
                    if selectedTimeRange == .custom {
                        HStack {
                            Text(startDate.formatted(date: .abbreviated, time: .omitted))
                            Image(systemName: "arrow.right")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            Text(endDate.formatted(date: .abbreviated, time: .omitted))
                        }
                        .font(.subheadline)
                        .fontWeight(.semibold)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(Color.blue.opacity(0.1))
                        .cornerRadius(8)
                        .transition(.move(edge: .top).combined(with: .opacity))
                    }
                    
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
                        // Summary Section
                        Section {
                            VStack(spacing: 16) {
                                HStack {
                                    VStack(alignment: .leading) {
                                        Text("Total Time")
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                        Text("\(totalMinutes) min")
                                            .font(.title2)
                                            .fontWeight(.bold)
                                    }
                                    Spacer()
                                    VStack(alignment: .trailing) {
                                        Text("Favored Activity")
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                        Text(topActivityType?.rawValue ?? "None")
                                            .font(.title3)
                                            .fontWeight(.semibold)
                                    }
                                }
                                
                                // Simple Input/Output Gauge
                                VStack(alignment: .leading, spacing: 4) {
                                    HStack {
                                        Text("Input vs Output")
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                        Spacer()
                                        Text("\(Int(inputRatio * 100))% Input")
                                            .font(.caption)
                                            .fontWeight(.bold)
                                            .foregroundStyle(.green)
                                    }
                                    
                                    GeometryReader { geometry in
                                        ZStack(alignment: .leading) {
                                            RoundedRectangle(cornerRadius: 4)
                                                .fill(Color.blue.opacity(0.3))
                                            RoundedRectangle(cornerRadius: 4)
                                                .fill(Color.green)
                                                .frame(width: geometry.size.width * CGFloat(inputRatio))
                                        }
                                    }
                                    .frame(height: 8)
                                }
                            }
                            .padding(.vertical, 8)
                        }
                        .listRowBackground(Color.blue.opacity(0.05))
                        
                        // Activity Breakdown Chart
                        if !filteredActivities.isEmpty {
                            Section {
                                ActivityBreakdownChart(activityByType: activityByType)
                                    .padding(.horizontal, -16) // Offset list padding for chart
                            }
                            .listRowBackground(Color.clear)
                            .listRowInsets(EdgeInsets())
                        }
                        
                        // Grouped Activities
                        ForEach(groupedActivities) { group in
                            Section(header: Text(group.date.formatted(date: .complete, time: .omitted))) {
                                ForEach(group.activities) { activity in
                                    HStack(alignment: .top, spacing: 12) {
                                        Image(systemName: activity.activityType.icon)
                                            .font(.title2)
                                            .foregroundStyle(activity.activityType.isInput ? .green : .blue)
                                            .frame(width: 32)
                                        
                                        VStack(alignment: .leading, spacing: 4) {
                                            Text(activity.activityTypeRaw)
                                                .font(.headline)
                                            Text(activity.date.formatted(date: .omitted, time: .shortened))
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
                                .onDelete { indexSet in
                                    deleteActivities(at: indexSet, from: group.activities)
                                }
                            }
                        }
                    }
                    .listStyle(.insetGrouped)
                    }
                }
                .sheet(item: $editingActivity) { activity in
                    EditActivityView(activity: activity)
                }
                .sheet(isPresented: $isAddingActivity) {
                    AddActivityView()
                }
                .sheet(isPresented: $showDateRangePicker) {
                    DateRangePickerSheet(startDate: $startDate, endDate: $endDate) {
                        selectedTimeRange = .custom
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
            .task {
                await syncManager.syncNow(modelContext: modelContext)
            }
        }
    }
    
    private func deleteActivities(at offsets: IndexSet, from groupActivities: [UserActivity]) {
        for index in offsets {
            let activityToDelete = groupActivities[index]
            modelContext.delete(activityToDelete)
        }
    }
}

struct DateRangePickerSheet: View {
    @Binding var startDate: Date
    @Binding var endDate: Date
    @Environment(\.dismiss) private var dismiss
    let onApply: () -> Void
    
    var body: some View {
        NavigationStack {
            Form {
                Section("Quick Select") {
                    HStack {
                        Button("Last 30 Days") {
                            startDate = Calendar.current.date(byAdding: .day, value: -30, to: Date()) ?? Date()
                            endDate = Date()
                        }
                        .buttonStyle(.bordered)
                        
                        Button("This Month") {
                            let components = Calendar.current.dateComponents([.year, .month], from: Date())
                            startDate = Calendar.current.date(from: components) ?? Date()
                            endDate = Date()
                        }
                        .buttonStyle(.bordered)
                    }
                    
                    Button("Last Month") {
                        let calendar = Calendar.current
                        var components = calendar.dateComponents([.year, .month], from: Date())
                        components.month! -= 1
                        startDate = calendar.date(from: components) ?? Date()
                        
                        if let range = calendar.range(of: .day, in: .month, for: startDate) {
                            components.day = range.count
                            endDate = calendar.date(from: components) ?? Date()
                        }
                    }
                    .buttonStyle(.bordered)
                }
                
                Section("Custom Start Date") {
                    DatePicker("Start Date", selection: $startDate, in: ...endDate, displayedComponents: .date)
                        .datePickerStyle(.graphical)
                }
                
                Section("Custom End Date") {
                    DatePicker("End Date", selection: $endDate, in: startDate...Date(), displayedComponents: .date)
                        .datePickerStyle(.graphical)
                }
            }
            .navigationTitle("Select Range")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Apply") {
                        onApply()
                        dismiss()
                    }
                    .fontWeight(.bold)
                }
            }
        }
        .presentationDetents([.large])
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
