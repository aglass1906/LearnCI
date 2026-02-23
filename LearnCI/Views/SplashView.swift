import SwiftUI

struct SplashView: View {
    @State private var isActive = false
    @State private var size = 0.8
    @State private var opacity = 0.5
    
    var loadingText: String = "Loading..."
    
    var body: some View {
        if isActive {
            EmptyView()
        } else {
            VStack {
                VStack {
                    Image(systemName: "person.3.fill")
                        .font(.system(size: 80))
                        .foregroundStyle(.white)
                    
                    Text("Language Learning\nwith\nComprehensible Input")
                        .font(.system(size: 32, weight: .bold, design: .rounded))
                        .multilineTextAlignment(.center)
                        .foregroundColor(.white.opacity(0.80))
                }
                .scaleEffect(size)
                .opacity(opacity)
                .onAppear {
                    withAnimation(.easeIn(duration: 1.2)) {
                        self.size = 0.9
                        self.opacity = 1.00
                    }
                }
                
                VStack(spacing: 15) {
                    ProgressView()
                        .progressViewStyle(CircularProgressViewStyle(tint: .white))
                        .scaleEffect(1.5)
                    
                    Text(loadingText)
                        .font(.headline)
                        .foregroundColor(.white.opacity(0.9))
                        .transition(.opacity)
                        .id(loadingText) // Force redraw on text change for smooth transition
                }
                .padding(.top, 50)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(
                LinearGradient(colors: [.blue, .purple], startPoint: .topLeading, endPoint: .bottomTrailing)
            )
            .ignoresSafeArea()
        }
    }
}

#Preview {
    SplashView()
}
