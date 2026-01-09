import SwiftUI

struct AuthView: View {
    @Environment(AuthManager.self) private var authManager
    
    @State private var mode: AuthMode = .signUp
    @State private var name: String = ""
    @State private var email: String = ""
    @State private var password: String = ""
    @State private var phone: String = ""
    @State private var isLoading = false
    @State private var errorMessage: String?
    @State private var showOTPView = false
    @State private var showEmailConfirmation = false
    @State private var showForgotPassword = false
    @State private var registeredEmail = ""
    @State private var isPasswordVisible = false
    
    enum AuthMode {
        case signUp
        case signIn
    }
    
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 30) {
                    Spacer()
                        .frame(height: 40)
                    
                    VStack(spacing: 12) {
                        Image(systemName: "person.3.fill")
                            .font(.system(size: 80))
                            .foregroundStyle(.linearGradient(colors: [.blue, .purple], startPoint: .topLeading, endPoint: .bottomTrailing))
                        
                        Text(mode == .signUp ? "Join the Community" : "Welcome Back")
                            .font(.largeTitle)
                            .fontWeight(.bold)
                        
                        Text(mode == .signUp ? "Sync your progress and learn with others." : "Sign in to continue your journey.")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                            .multilineTextAlignment(.center)
                    }
                    .padding(.horizontal)
                    
                    // Auth Mode Toggle
                    Picker("Mode", selection: $mode) {
                        Text("Sign Up").tag(AuthMode.signUp)
                        Text("Sign In").tag(AuthMode.signIn)
                    }
                    .pickerStyle(.segmented)
                    .padding(.horizontal)
                    
                    // Form Fields
                    VStack(spacing: 16) {
                        if mode == .signUp {
                            TextField("Full Name", text: $name)
                                .textFieldStyle(.roundedBorder)
                                .padding(.horizontal)
                                .autocorrectionDisabled()
                        }
                        
                        TextField("Email Address", text: $email)
                            .textFieldStyle(.roundedBorder)
                            .padding(.horizontal)
                            .keyboardType(.emailAddress)
                            .autocapitalization(.none)
                            .autocorrectionDisabled()
                        
                        HStack {
                            if isPasswordVisible {
                                TextField("Password", text: $password)
                                    .textFieldStyle(.roundedBorder)
                            } else {
                                SecureField("Password", text: $password)
                                    .textFieldStyle(.roundedBorder)
                            }
                        }
                        .overlay(alignment: .trailing) {
                            Button(action: { isPasswordVisible.toggle() }) {
                                Image(systemName: isPasswordVisible ? "eye.slash.fill" : "eye.fill")
                                    .foregroundColor(.secondary)
                                    .padding(.trailing, 8)
                            }
                        }
                        .padding(.horizontal)
                        
                        if mode == .signIn {
                            HStack {
                                Spacer()
                                Button("Forgot Password?") {
                                    showForgotPassword = true
                                }
                                .font(.caption)
                                .foregroundColor(.blue)
                                .padding(.trailing)
                            }
                        }
                        
                        if mode == .signUp {
                            TextField("Phone (Optional)", text: $phone)
                                .textFieldStyle(.roundedBorder)
                                .padding(.horizontal)
                                .keyboardType(.phonePad)
                                .onChange(of: phone) { _, newValue in
                                    // Auto-prepend +1 if user starts typing without it
                                    if !newValue.isEmpty && !newValue.hasPrefix("+") {
                                        phone = "+1" + newValue
                                    }
                                }
                            
                            Text("Just enter your 10-digit number (we'll add +1)")
                                .font(.caption2)
                                .foregroundColor(.secondary)
                                .padding(.horizontal)
                        }
                        
                        if let error = errorMessage {
                            Text(error)
                                .font(.caption)
                                .foregroundColor(.red)
                                .multilineTextAlignment(.center)
                                .padding(.horizontal)
                        }
                        
                        Button(action: handlePrimaryAction) {
                            if isLoading {
                                ProgressView()
                                    .tint(.white)
                            } else {
                                Text(mode == .signUp ? "Create Account" : "Sign In")
                                    .fontWeight(.semibold)
                            }
                        }
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(isFormValid ? Color.blue : Color.gray)
                        .foregroundColor(.white)
                        .cornerRadius(12)
                        .disabled(!isFormValid || isLoading)
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
            .navigationDestination(isPresented: $showOTPView) {
                OTPVerificationView(phone: phone)
            }
            .sheet(isPresented: $showEmailConfirmation) {
                EmailConfirmationView(email: registeredEmail)
            }
            .sheet(isPresented: $showForgotPassword) {
                ForgotPasswordSheet()
            }
        }
    }
    
    private var isFormValid: Bool {
        if mode == .signUp {
            return !name.isEmpty && 
                   !email.isEmpty && 
                   password.count >= 8
        } else {
            return !email.isEmpty && !password.isEmpty
        }
    }
    
    private func handlePrimaryAction() {
        isLoading = true
        errorMessage = nil
        
        Task {
            do {
                if mode == .signUp {
                    try await authManager.signUp(
                        email: email,
                        password: password,
                        phone: phone,
                        fullName: name
                    )
                    // Show email confirmation message
                    await MainActor.run {
                        registeredEmail = email
                        showEmailConfirmation = true
                        isLoading = false
                        
                        // Clear form
                        name = ""
                        email = ""
                        password = ""
                        phone = ""
                    }
                } else {
                    try await authManager.signInWithEmail(
                        email: email,
                        password: password
                    )
                    await MainActor.run {
                        isLoading = false
                    }
                }
            } catch {
                await MainActor.run {
                    isLoading = false
                    errorMessage = error.localizedDescription
                }
            }
        }
    }
}

// MARK: - Email Confirmation View
struct EmailConfirmationView: View {
    @Environment(\.dismiss) private var dismiss
    let email: String
    
    var body: some View {
        VStack(spacing: 30) {
            Spacer()
            
            VStack(spacing: 16) {
                Image(systemName: "envelope.circle.fill")
                    .font(.system(size: 80))
                    .foregroundStyle(.blue)
                
                Text("Check Your Email")
                    .font(.title2)
                    .fontWeight(.bold)
                
                VStack(spacing: 8) {
                    Text("We sent a verification link to:")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                    
                    Text(email)
                        .font(.headline)
                        .foregroundColor(.primary)
                        .multilineTextAlignment(.center)
                }
                
                Text("Click the link in the email to verify your account, then return here to sign in.")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal)
            }
            
            Spacer()
            
            Button(action: { dismiss() }) {
                Text("Got it")
                    .fontWeight(.semibold)
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(Color.blue)
                    .foregroundColor(.white)
                    .cornerRadius(12)
            }
            .padding(.horizontal)
            .padding(.bottom, 40)
        }
        .padding()
    }
}

#Preview {
    AuthView()
        .environment(AuthManager())
}
