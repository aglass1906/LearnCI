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
                VStack(spacing: 25) {
                    CommonHeroView()
                        .frame(width: 300)
                        .shadow(color: .black.opacity(0.3), radius: 10, x: 0, y: 5)
                    
                    Text("Language Learning\nwith\nComprehensible Input")
                        .font(.custom("AvenirNext-Bold", size: 32))
                        .multilineTextAlignment(.center)
                        .foregroundColor(.white)
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
