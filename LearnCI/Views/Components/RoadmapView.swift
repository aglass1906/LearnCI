import SwiftUI

struct RoadmapView: View {
    let totalMinutes: Int
    
    var body: some View {
        let currentHoursDouble = Double(totalMinutes) / 60.0
        let levels: [(id: Int, range: ClosedRange<Double>, color: Color)] = [
            (1, 0...50, .teal),
            (2, 50...150, .green),
            (3, 150...300, .blue),
            (4, 300...600, .orange),
            (5, 600...1000, .purple),
            (6, 1000...1500, .pink)
        ]
        
        let maxHours: Double = 1500
        let maxLevelDuration: Double = 500 // Level 6 is 500h (longest)
        let graphHeight: CGFloat = 80
        
        VStack(spacing: 4) {
            GeometryReader { geo in
                let rWidth = geo.size.width
                
                ZStack(alignment: .leading) {
                    // Background Track
                    HStack(alignment: .bottom, spacing: 1) {
                        ForEach(levels, id: \.id) { level in
                            let levelDuration = level.range.upperBound - level.range.lowerBound
                            let widthRatio = levelDuration / maxHours
                            let heightRatio = 0.2 + (0.8 * (levelDuration / maxLevelDuration))
                            
                            Rectangle()
                                .fill(level.color.opacity(0.3))
                                .frame(width: rWidth * widthRatio, height: graphHeight * heightRatio)
                                .overlay(
                                    Text("L\(level.id)")
                                        .font(.system(size: 8, weight: .bold))
                                        .foregroundStyle(level.color)
                                        .opacity(0.8)
                                        .padding(.bottom, 2),
                                    alignment: .bottom
                                )
                        }
                    }
                    .frame(height: graphHeight, alignment: .bottom)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                    
                    // User Progress Fill
                    HStack(alignment: .bottom, spacing: 1) {
                        ForEach(levels, id: \.id) { level in
                            let levelDuration = level.range.upperBound - level.range.lowerBound
                            let widthRatio = levelDuration / maxHours
                            let segmentWidth = rWidth * widthRatio
                            let heightRatio = 0.2 + (0.8 * (levelDuration / maxLevelDuration))
                            let segmentHeight = graphHeight * heightRatio
                            let hoursInLevel = max(0, min(currentHoursDouble - level.range.lowerBound, levelDuration))
                            let fillRatio = hoursInLevel / levelDuration
                            
                            ZStack(alignment: .leading) {
                                Rectangle()
                                    .fill(Color.clear)
                                    .frame(width: segmentWidth, height: segmentHeight)
                                
                                if fillRatio > 0 {
                                    Rectangle()
                                        .fill(level.color)
                                        .frame(width: segmentWidth * fillRatio, height: segmentHeight)
                                }
                            }
                        }
                    }
                    .frame(height: graphHeight, alignment: .bottom)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                    
                    // Current Position Line
                    if currentHoursDouble > 0 && currentHoursDouble < maxHours {
                        Rectangle()
                            .fill(Color.primary)
                            .frame(width: 2, height: graphHeight)
                            .offset(x: min(rWidth, rWidth * (currentHoursDouble / maxHours)))
                            .shadow(radius: 1)
                    }
                }
            }
            .frame(height: graphHeight)
            
            // Legend
            GeometryReader { geo in
                let rWidth = geo.size.width
                ZStack(alignment: .leading) {
                    ForEach(levels, id: \.id) { level in
                        Text("\(Int(level.range.upperBound))h")
                            .font(.system(size: 9))
                            .foregroundStyle(.secondary)
                            .position(x: rWidth * (level.range.upperBound / maxHours), y: 10)
                            .offset(x: -10)
                    }
                }
            }
            .frame(height: 20)
        }
    }
}
