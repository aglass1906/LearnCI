import SwiftUI

struct ProfileConnectionsView: View {
    @Environment(YouTubeManager.self) private var youtubeManager
    
    var body: some View {
        Form {
            Section(header: Text("YouTube Connection")) {
                if youtubeManager.isAuthenticated {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            VStack(alignment: .leading) {
                                Text("Connected")
                                    .font(.headline)
                                if let account = youtubeManager.youtubeAccount {
                                    Text(account)
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                }
                            }
                            Spacer()
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundColor(.green)
                        }
                        
                        Button("Disconnect", role: .destructive) {
                            youtubeManager.disconnect()
                        }
                        .font(.subheadline)
                    }
                } else {
                    VStack(alignment: .leading, spacing: 12) {
                        if youtubeManager.isLoading {
                            HStack {
                                ProgressView()
                                Text("Signing in...")
                                    .foregroundColor(.secondary)
                            }
                        } else {
                            Text("Connect your YouTube account to browse and track videos")
                                .font(.caption)
                                .foregroundColor(.secondary)
                            
                            Button(action: { 
                                youtubeManager.signInWithGoogle()
                            }) {
                                HStack {
                                    Image(systemName: "play.rectangle.fill")
                                    Text("Sign in with Google")
                                }
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 12)
                            }
                            .buttonStyle(.borderedProminent)
                            .tint(.red)
                            
                            if let error = youtubeManager.errorMessage {
                                Text(error)
                                    .font(.caption)
                                    .foregroundColor(.red)
                            }
                        }
                    }
                }
            }
        }
        .navigationTitle("App Connections")
    }
}
