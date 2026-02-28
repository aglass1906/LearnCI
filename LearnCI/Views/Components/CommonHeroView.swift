import SwiftUI

struct CommonHeroView: View {
    var body: some View {
        ZStack {
            // Background Gradient
            LinearGradient(
                colors: [Color.blue.opacity(0.8), Color.orange.opacity(0.6)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            
            // Icon Rows
            VStack(spacing: 16) {
                HStack(spacing: 28) {
                    VStack(spacing: 8) {
                        Image(systemName: "play.rectangle.fill")
                            .font(.system(size: 38))
                            .foregroundColor(.white)
                            .shadow(color: .black.opacity(0.2), radius: 4, x: 0, y: 2)
                        Text("Watch")
                            .font(.caption2)
                            .fontWeight(.semibold)
                            .foregroundColor(.white.opacity(0.9))
                    }
                    
                    VStack(spacing: 8) {
                        Image(systemName: "headphones")
                            .font(.system(size: 38))
                            .foregroundColor(.white)
                            .shadow(color: .black.opacity(0.2), radius: 4, x: 0, y: 2)
                        Text("Listen")
                            .font(.caption2)
                            .fontWeight(.semibold)
                            .foregroundColor(.white.opacity(0.9))
                    }

                    VStack(spacing: 8) {
                        Image(systemName: "gamecontroller.fill")
                            .font(.system(size: 38))
                            .foregroundColor(.white)
                            .shadow(color: .black.opacity(0.2), radius: 4, x: 0, y: 2)
                        Text("Play")
                            .font(.caption2)
                            .fontWeight(.semibold)
                            .foregroundColor(.white.opacity(0.9))
                    }
                    
                    VStack(spacing: 8) {
                        Image(systemName: "book.fill")
                            .font(.system(size: 38))
                            .foregroundColor(.white)
                            .shadow(color: .black.opacity(0.2), radius: 4, x: 0, y: 2)
                        Text("Read")
                            .font(.caption2)
                            .fontWeight(.semibold)
                            .foregroundColor(.white.opacity(0.9))
                    }
                }
                
                VStack(spacing: 8) {
                    Image(systemName: "brain.head.profile")
                        .font(.system(size: 36))
                        .foregroundColor(.yellow)
                        .shadow(color: .yellow.opacity(0.6), radius: 6, x: 0, y: 0)
                    Text("Remember")
                        .font(.caption)
                        .fontWeight(.semibold)
                        .foregroundColor(.white.opacity(0.9))
                }
            }
            .padding(.horizontal, 24)
        }
        .frame(height: 200)
        .frame(maxWidth: .infinity)
        .cornerRadius(12)
    }
}

#Preview {
    CommonHeroView()
        .padding()
}
