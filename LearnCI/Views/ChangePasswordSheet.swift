import SwiftUI

struct ChangePasswordSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(AuthManager.self) private var authManager
    
    @State private var password = ""
    @State private var confirmPassword = ""
    @State private var isLoading = false
    @State private var errorMessage: String?
    @State private var successMessage: String?
    @State private var isPasswordVisible = false
    @State private var isConfirmVisible = false
    
    var body: some View {
        NavigationStack {
            Form {
                Section {
                    HStack {
                        if isPasswordVisible {
                            TextField("New Password", text: $password)
                        } else {
                            SecureField("New Password", text: $password)
                        }
                    }
                    .overlay(alignment: .trailing) {
                        Button(action: { isPasswordVisible.toggle() }) {
                            Image(systemName: isPasswordVisible ? "eye.slash.fill" : "eye.fill")
                                .foregroundColor(.secondary)
                        }
                    }
                    
                    HStack {
                        if isConfirmVisible {
                            TextField("Confirm Password", text: $confirmPassword)
                        } else {
                            SecureField("Confirm Password", text: $confirmPassword)
                        }
                    }
                    .overlay(alignment: .trailing) {
                        Button(action: { isConfirmVisible.toggle() }) {
                            Image(systemName: isConfirmVisible ? "eye.slash.fill" : "eye.fill")
                                .foregroundColor(.secondary)
                        }
                    }
                } footer: {
                    Text("Password must be at least 8 characters.")
                }
                
                if let error = errorMessage {
                    Section {
                        Text(error)
                            .foregroundColor(.red)
                    }
                }
                
                if let success = successMessage {
                    Section {
                        Text(success)
                            .foregroundColor(.green)
                    }
                }
                
                Section {
                    Button(action: changePassword) {
                        if isLoading {
                            HStack {
                                Spacer()
                                ProgressView()
                                Spacer()
                            }
                        } else {
                            Text("Update Password")
                                .fontWeight(.medium)
                                .frame(maxWidth: .infinity)
                        }
                    }
                    .disabled(password.isEmpty || confirmPassword.isEmpty || password.count < 8 || isLoading)
                }
            }
            .navigationTitle("Change Password")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
            }
        }
    }
    
    private func changePassword() {
        guard password == confirmPassword else {
            errorMessage = "Passwords do not match."
            return
        }
        
        isLoading = true
        errorMessage = nil
        successMessage = nil
        
        Task {
            do {
                try await authManager.updatePassword(password: password)
                await MainActor.run {
                    isLoading = false
                    successMessage = "Password updated successfully!"
                    // Delay dismissal to show success message
                    DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                        dismiss()
                    }
                }
            } catch {
                await MainActor.run {
                    isLoading = false
                    errorMessage = "Failed to update password: \(error.localizedDescription)"
                }
            }
        }
    }
}

#Preview {
    ChangePasswordSheet()
        .environment(AuthManager())
}
