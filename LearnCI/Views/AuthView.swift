import SwiftUI

struct AuthView: View {
    @Environment(AuthManager.self) private var authManager
    @State private var name: String = ""
    @State private var email: String = ""
    
    var body: some View {
        NavigationStack {
            VStack(spacing: 30) {
                Spacer()
                
                VStack(spacing: 12) {
                    Image(systemName: "person.3.fill")
                        .font(.system(size: 80))
                        .foregroundStyle(.linearGradient(colors: [.blue, .purple], startPoint: .topLeading, endPoint: .bottomTrailing))
                    
                    Text("Join the Community")
                        .font(.largeTitle)
                        .fontWeight(.bold)
                    
                    Text("Sync your progress and learn with others.")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                }
                .padding(.horizontal)
                
                VStack(spacing: 16) {
                    TextField("Display Name", text: $name)
                        .textFieldStyle(.roundedBorder)
                        .padding(.horizontal)
                    
                    TextField("Email Address", text: $email)
                        .textFieldStyle(.roundedBorder)
                        .padding(.horizontal)
                        .keyboardType(.emailAddress)
                        .autocapitalization(.none)
                    
                    Button(action: {
                        // In Phase 1, we just simulate a login
                        // Later this calls authManager.signUpWithEmail()
                        print("Email sign up not yet implemented with Supabase")
                    }) {
                        Text("Create Account")
                            .fontWeight(.semibold)
                            .frame(maxWidth: .infinity)
                            .padding()
                            .background(Color.blue)
                            .foregroundColor(.white)
                            .cornerRadius(12)
                    }
                    .padding(.horizontal)
                    
                    Text("Or")
                        .foregroundColor(.secondary)
                    
                    Button(action: {
                        authManager.signInWithGoogle()
                    }) {
                        HStack {
                            Image(systemName: "g.circle.fill")
                            Text("Continue with Google")
                        }
                        .fontWeight(.semibold)
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(Color(.systemGray6))
                        .foregroundColor(.primary)
                        .cornerRadius(12)
                    }
                    .padding(.horizontal)
                }
                
                Spacer()
                
                Text("By continuing, you agree to our Terms of Service.")
                    .font(.caption2)
                    .foregroundColor(.secondary)
                    .padding(.bottom)
            }
        }
    }
}

#Preview {
    AuthView()
        .environment(AuthManager())
}
