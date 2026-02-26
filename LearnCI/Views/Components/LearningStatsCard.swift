import SwiftUI

struct LearningStatsCard: View {
    let stats: StatsManager.LearningStats
    
    var body: some View {
        LayoutCardView(
            title: "Learning Stats",
            accentColor: .orange,
            icon: "chart.line.uptrend.xyaxis"
        ) {
            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                StatItemView(
                    title: "Total Hours",
                    value: String(format: "%.1f", stats.totalHours),
                    icon: "clock.fill",
                    color: .blue
                )
                
                StatItemView(
                    title: "Days Learning",
                    value: "\(stats.totalLearningDays)",
                    icon: "calendar",
                    color: .green
                )
                
                StatItemView(
                    title: "Active Streak",
                    value: "\(stats.currentActivityStreak)d",
                    subValue: "Best: \(stats.bestActivityStreak)d",
                    icon: "flame.fill",
                    color: .orange
                )
                
                StatItemView(
                    title: "Goal Streak",
                    value: "\(stats.currentGoalStreak)d",
                    subValue: "Best: \(stats.bestGoalStreak)d",
                    icon: "trophy.fill",
                    color: .yellow
                )
            }
            .padding(.top, 4)
        }
    }
}

struct StatItemView: View {
    let title: String
    let value: String
    var subValue: String? = nil
    let icon: String
    let color: Color
    
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 6) {
                Image(systemName: icon)
                    .foregroundColor(color)
                    .font(.caption)
                Text(title)
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .lineLimit(1)
            }
            
            Text(value)
                .font(.title3)
                .fontWeight(.bold)
                .foregroundColor(.primary)
            
            if let subValue = subValue {
                Text(subValue)
                    .font(.system(size: 10))
                    .foregroundColor(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(10)
        .background(Color(UIColor.secondarySystemGroupedBackground).opacity(0.6))
        .cornerRadius(12)
    }
}

#Preview {
    ZStack {
        Color.gray.ignoresSafeArea()
        LearningStatsCard(stats: StatsManager.LearningStats(
            totalHours: 125.5,
            totalLearningDays: 45,
            currentActivityStreak: 7,
            currentGoalStreak: 3,
            bestActivityStreak: 14,
            bestGoalStreak: 5
        ))
    }
}
