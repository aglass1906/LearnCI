import SwiftUI

struct OTPVerificationView: View {
    @Environment(AuthManager.self) private var authManager
    @Environment(\.dismiss) private var dismiss
    
    let phone: String
    @State private var otpCode: String = ""
    @State private var isVerifying = false
    @State private var errorMessage: String?
    
    var body: some View {
        VStack(spacing: 30) {
            Spacer()
            
            VStack(spacing: 12) {
                Image(systemName: "message.badge.filled.fill")
                    .font(.system(size: 60))
                    .foregroundStyle(.blue)
                
                Text("Verify Your Phone")
                    .font(.title2)
                    .fontWeight(.bold)
                
                Text("We sent a 6-digit code to")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                
                Text(phone)
                    .font(.headline)
                    .foregroundColor(.primary)
            }
            
            VStack(spacing: 16) {
                TextField("Enter 6-digit code", text: $otpCode)
                    .textFieldStyle(.roundedBorder)
                    .keyboardType(.numberPad)
                    .font(.title3)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal)
                    .onChange(of: otpCode) { _, newValue in
                        // Limit to 6 digits
                        if newValue.count > 6 {
                            otpCode = String(newValue.prefix(6))
                        }
                    }
                
                if let error = errorMessage {
                    Text(error)
                        .font(.caption)
                        .foregroundColor(.red)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal)
                }
                
                Button(action: verifyCode) {
                    if isVerifying {
                        ProgressView()
                            .tint(.white)
                    } else {
                        Text("Verify Code")
                            .fontWeight(.semibold)
                    }
                }
                .frame(maxWidth: .infinity)
                .padding()
                .background(otpCode.count == 6 ? Color.blue : Color.gray)
                .foregroundColor(.white)
                .cornerRadius(12)
                .disabled(otpCode.count != 6 || isVerifying)
                .padding(.horizontal)
                
                Button(action: { dismiss() }) {
                    Text("Use a different method")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }
            }
            
            Spacer()
        }
        .navigationTitle("Verification")
        .navigationBarTitleDisplayMode(.inline)
    }
    
    private func verifyCode() {
        isVerifying = true
        errorMessage = nil
        
        Task {
            do {
                try await authManager.verifyOTP(phone: phone, token: otpCode)
                await MainActor.run {
                    dismiss()
                }
            } catch {
                await MainActor.run {
                    isVerifying = false
                    errorMessage = "Invalid code. Please try again."
                }
            }
        }
    }
}

#Preview {
    NavigationStack {
        OTPVerificationView(phone: "+1 555-123-4567")
            .environment(AuthManager())
    }
}
