import SwiftUI

/// Stage 3: Memory Match Mode Selection
struct MemoryMatchModeSelector: View {
    let deck: DeckMetadata
    @Binding var selectedMode: MemoryMatchMode
    
    let onNext: () -> Void
    let onBack: () -> Void
    let onSkipToSummary: () -> Void
    
    var body: some View {
        VStack(spacing: 24) {
            // Title
            VStack(spacing: 8) {
                Text("Memory Match")
                    .font(.largeTitle)
                    .fontWeight(.bold)
                Text("Choose your matching mode")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            }
            .padding(.top)
            
            // Mode Selection
            ScrollView {
                VStack(spacing: 16) {
                    ForEach(MemoryMatchMode.allCases, id: \.self) { mode in
                        ModeOptionCard(
                            mode: mode,
                            isSelected: selectedMode == mode
                        )
                        .onTapGesture {
                            withAnimation(.spring(response: 0.3)) {
                                selectedMode = mode
                            }
                        }
                    }
                }
                .padding(.horizontal)
            }
            
            Spacer()
            
            // Next Button
            Button(action: onNext) {
                HStack {
                    Text("Next")
                    Image(systemName: "chevron.right")
                }
                .font(.headline)
                .foregroundColor(.white)
                .frame(maxWidth: .infinity)
                .padding()
                .background(Color.blue)
                .cornerRadius(12)
            }
            .padding()
        }
}
}
