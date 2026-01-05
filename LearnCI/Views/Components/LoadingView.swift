import SwiftUI

struct LoadingView: View {
    @State private var isAnimating = false
    
    var message: String = "Getting things ready..."
    
    var body: some View {
        ZStack {
            Color(.systemBackground)
                .ignoresSafeArea()
            
            VStack(spacing: 25) {
                // Animated Icon
                ZStack {
                    // App Graphic Placeholder
                    Image(systemName: "globe.americas.fill")
                        .font(.system(size: 40))
                        .foregroundStyle(.linearGradient(colors: [.blue, .green], startPoint: .topLeading, endPoint: .bottomTrailing))
                    
                    Circle()
                        .stroke(Color.blue.opacity(0.3), lineWidth: 8)
                        .frame(width: 80, height: 80)
                    
                    Circle()
                        .trim(from: 0, to: 0.7)
                        .stroke(Color.blue, style: StrokeStyle(lineWidth: 8, lineCap: .round))
                        .frame(width: 80, height: 80)
                        .rotationEffect(Angle(degrees: isAnimating ? 360 : 0))
                        .animation(Animation.linear(duration: 1.5).repeatForever(autoreverses: false), value: isAnimating)
                }
                
                // Message
                Text(message)
                    .font(.headline)
                    .foregroundColor(.secondary)
                    .transition(.opacity)
            }
        }
        .onAppear {
            isAnimating = true
        }
    }
}

#Preview {
    LoadingView()
}
