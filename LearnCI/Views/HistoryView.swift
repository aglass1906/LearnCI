import SwiftUI
import SwiftData

struct HistoryView: View {
    enum TimeRange: String, CaseIterable, Identifiable {
        case today = "Today"
        case week = "Last 7 Days"
        case month = "Last 30 Days"
        case all = "All Time"
        case custom = "Custom"
        
        var id: String { rawValue }
    }
    
    var body: some View {
        NavigationStack {
            ActivityHistoryContent()
                .navigationTitle("Activity")
        }
    }
}

struct ActivityHistoryContent: View {
    @Environment(AuthManager.self) private var authManager
    @Environment(\.modelContext) private var modelContext
    @Environment(SyncManager.self) private var syncManager
    @Query(sort: \UserActivity.date, order: .reverse) private var allActivities: [UserActivity]
    
    var activities: [UserActivity] {
        allActivities.filter { $0.userID == authManager.currentUser }
    }
    
    @State private var selectedTimeRange: HistoryView.TimeRange = .today
    @State private var selectedActivityType: ActivityType? = nil
    @State private var editingActivity: UserActivity?
    @State private var isAddingActivity: Bool = false
    @State private var showDateRangePicker: Bool = false
    @State private var startDate: Date = Calendar.current.date(byAdding: .day, value: -7, to: Date()) ?? Date()
    @State private var endDate: Date = Date()
    
    // Move enum outside or keep in HistoryView if needed. Let's move it to HistoryView namespace.
    
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

    private var selectedTypeTitle: String {
        selectedActivityType?.rawValue ?? "All Types"
    }

    private var selectedDateTitle: String {
        guard selectedTimeRange == .custom else {
            return selectedTimeRange.rawValue
        }

        return "\(startDate.formatted(date: .abbreviated, time: .omitted)) - \(endDate.formatted(date: .abbreviated, time: .omitted))"
    }
    
    var body: some View {
        VStack(spacing: 0) {
            // Filters
            HStack(spacing: 12) {
                Menu {
                    Button {
                        selectedActivityType = nil
                    } label: {
                        if selectedActivityType == nil {
                            Label("All Types", systemImage: "checkmark")
                        } else {
                            Text("All Types")
                        }
                    }

                    Divider()

                    ForEach(ActivityType.allCases) { type in
                        Button {
                            selectedActivityType = type
                        } label: {
                            if selectedActivityType == type {
                                Label(type.rawValue, systemImage: "checkmark")
                            } else {
                                Label(type.rawValue, systemImage: type.icon)
                            }
                        }
                    }
                } label: {
                    filterControl(
                        title: selectedTypeTitle,
                        systemImage: selectedActivityType?.icon ?? "square.grid.2x2",
                        showsChevron: true
                    )
                }

                Button {
                    showDateRangePicker = true
                } label: {
                    filterControl(
                        title: selectedDateTitle,
                        systemImage: "calendar",
                        showsChevron: false
                    )
                }
            }
            .padding(.horizontal)
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
            DateRangePickerSheet(
                selectedTimeRange: $selectedTimeRange,
                startDate: $startDate,
                endDate: $endDate
            )
        }
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button(action: { isAddingActivity = true }) {
                    Image(systemName: "plus")
                }
            }
        }
    }

    private func filterControl(title: String, systemImage: String, showsChevron: Bool) -> some View {
        HStack(spacing: 8) {
            Image(systemName: systemImage)
                .foregroundStyle(.blue)

            Text(title)
                .font(.subheadline)
                .fontWeight(.semibold)
                .lineLimit(1)
                .minimumScaleFactor(0.8)

            Spacer(minLength: 4)

            if showsChevron {
                Image(systemName: "chevron.down")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
        .foregroundStyle(.primary)
        .padding(.horizontal, 12)
        .frame(maxWidth: .infinity, minHeight: 44)
        .background(Color(UIColor.secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .overlay {
            RoundedRectangle(cornerRadius: 12)
                .stroke(Color.secondary.opacity(0.15))
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
    @Binding var selectedTimeRange: HistoryView.TimeRange
    @Binding var startDate: Date
    @Binding var endDate: Date
    @Environment(\.dismiss) private var dismiss

    @State private var draftTimeRange: HistoryView.TimeRange
    @State private var draftStartDate: Date
    @State private var draftEndDate: Date

    init(
        selectedTimeRange: Binding<HistoryView.TimeRange>,
        startDate: Binding<Date>,
        endDate: Binding<Date>
    ) {
        _selectedTimeRange = selectedTimeRange
        _startDate = startDate
        _endDate = endDate
        _draftTimeRange = State(initialValue: selectedTimeRange.wrappedValue)
        _draftStartDate = State(initialValue: startDate.wrappedValue)
        _draftEndDate = State(initialValue: endDate.wrappedValue)
    }
    
    var body: some View {
        NavigationStack {
            Form {
                Section("Date Range") {
                    ForEach(HistoryView.TimeRange.allCases) { range in
                        Button {
                            draftTimeRange = range
                        } label: {
                            HStack {
                                Text(range.rawValue)
                                    .foregroundStyle(.primary)
                                Spacer()
                                if draftTimeRange == range {
                                    Image(systemName: "checkmark")
                                        .fontWeight(.semibold)
                                }
                            }
                        }
                    }
                }
                
                if draftTimeRange == .custom {
                    Section("Custom Range") {
                        DatePicker("Start Date", selection: $draftStartDate, in: ...draftEndDate, displayedComponents: .date)
                        DatePicker("End Date", selection: $draftEndDate, in: draftStartDate...Date(), displayedComponents: .date)
                    }
                }
            }
            .navigationTitle("Select Dates")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        selectedTimeRange = draftTimeRange
                        startDate = draftStartDate
                        endDate = draftEndDate
                        dismiss()
                    }
                    .fontWeight(.bold)
                }
            }
        }
        .presentationDetents([.medium, .large])
    }
}

#Preview {
    let auth = AuthManager()
    return HistoryView()
        .environment(DataManager())
        .environment(YouTubeManager())
        .environment(auth)
        .environment(SyncManager(authManager: auth))
}
