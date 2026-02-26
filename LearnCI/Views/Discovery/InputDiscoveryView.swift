import SwiftUI

struct InputDiscoveryView: View {
    var body: some View {
        NavigationStack {
            InputHubView()
                .navigationTitle("Explore Input")
                .navigationBarTitleDisplayMode(.large)
        }
    }
}

#Preview {
    InputDiscoveryView()
        .environment(AuthManager())
}
