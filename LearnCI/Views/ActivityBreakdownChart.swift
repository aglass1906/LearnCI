import SwiftUI
import Charts

struct ActivityBreakdownChart: View {
    let activityByType: [ActivityTypeData]
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Activity Breakdown")
                .font(.title2)
                .fontWeight(.semibold)
                .padding(.horizontal)
            
            if activityByType.isEmpty {
                Text("No data available")
                    .foregroundColor(.secondary)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding()
            } else {
                Chart(activityByType) { data in
                    BarMark(
                        x: .value("Minutes", data.minutes),
                        y: .value("Type", data.type.rawValue)
                    )
                    .foregroundStyle(data.type.color)
                    .annotation(position: .trailing) {
                        Text("\(data.minutes) min")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
                .frame(height: CGFloat(activityByType.count) * 44)
                .chartXAxis {
                    AxisMarks(position: .bottom)
                }
                .padding(.horizontal)
            }
        }
        .padding(.vertical)
        .background(Color(UIColor.secondarySystemGroupedBackground))
        .cornerRadius(12)
        .padding(.horizontal)
    }
}

#Preview {
    ActivityBreakdownChart(activityByType: [
        ActivityTypeData(type: .watchingVideos, minutes: 101),
        ActivityTypeData(type: .tutoring, minutes: 30),
        ActivityTypeData(type: .appLearning, minutes: 21)
    ])
}
