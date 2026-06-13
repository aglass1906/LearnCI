import SwiftUI

struct AuthView: View {
    @Environment(AuthManager.self) private var authManager

    @State private var email = ""
    @State private var isSendingCode = false
    @State private var errorMessage: String?
    @State private var pendingEmail: String?
    @State private var showPasswordAuth = false

    var body: some View {
        NavigationStack {
            ZStack {
                LinearGradient(
                    colors: [.indigo.opacity(0.95), .purple.opacity(0.9), .pink.opacity(0.75)],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
                .ignoresSafeArea()

                ScrollView {
                    VStack(spacing: 28) {
                        Spacer(minLength: 36)

                        VStack(spacing: 14) {
                            Image(systemName: "sparkles.rectangle.stack.fill")
                                .font(.system(size: 70))
                                .foregroundStyle(.white, .yellow)

                            Text("Start Your Learning Journey")
                                .font(.largeTitle.bold())
                                .multilineTextAlignment(.center)
                                .foregroundStyle(.white)

                            Text("No password required. We’ll email you a secure code and sign-in link.")
                                .font(.subheadline)
                                .multilineTextAlignment(.center)
                                .foregroundStyle(.white.opacity(0.85))
                        }

                        VStack(spacing: 16) {
                            TextField("Email address", text: $email)
                                .textContentType(.emailAddress)
                                .keyboardType(.emailAddress)
                                .textInputAutocapitalization(.never)
                                .autocorrectionDisabled()
                                .padding()
                                .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16))
                                .submitLabel(.continue)
                                .onSubmit(sendCode)

                            if let errorMessage {
                                Text(errorMessage)
                                    .font(.caption)
                                    .foregroundStyle(.red)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                            }

                            Button(action: sendCode) {
                                Group {
                                    if isSendingCode {
                                        ProgressView().tint(.indigo)
                                    } else {
                                        Label("Continue with Email", systemImage: "envelope.fill")
                                            .fontWeight(.semibold)
                                    }
                                }
                                .frame(maxWidth: .infinity)
                                .padding()
                            }
                            .buttonStyle(.plain)
                            .foregroundStyle(.indigo)
                            .background(.white, in: RoundedRectangle(cornerRadius: 16))
                            .disabled(!isEmailValid || isSendingCode)
                            .opacity(isEmailValid ? 1 : 0.65)

                            HStack {
                                Rectangle().frame(height: 1).foregroundStyle(.white.opacity(0.3))
                                Text("or").font(.caption).foregroundStyle(.white.opacity(0.8))
                                Rectangle().frame(height: 1).foregroundStyle(.white.opacity(0.3))
                            }

                            Button {
                                authManager.signInWithGoogle()
                            } label: {
                                Label("Continue with Google", systemImage: "g.circle.fill")
                                    .fontWeight(.semibold)
                                    .frame(maxWidth: .infinity)
                                    .padding()
                            }
                            .buttonStyle(.plain)
                            .foregroundStyle(.primary)
                            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16))

                            Button("Use Password Instead") {
                                showPasswordAuth = true
                            }
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(.white)
                        }
                        .padding(22)
                        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 28))

                        Text("By continuing, you agree to our Terms of Service.")
                            .font(.caption2)
                            .foregroundStyle(.white.opacity(0.7))
                    }
                    .padding(.horizontal, 22)
                    .padding(.bottom, 32)
                }
            }
            .navigationDestination(item: $pendingEmail) { email in
                EmailCodeVerificationView(email: email)
            }
            .sheet(isPresented: $showPasswordAuth) {
                PasswordAuthView()
            }
        }
    }

    private var normalizedEmail: String {
        email.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }

    private var isEmailValid: Bool {
        normalizedEmail.contains("@") && normalizedEmail.contains(".")
    }

    private func sendCode() {
        guard isEmailValid, !isSendingCode else { return }
        isSendingCode = true
        errorMessage = nil

        Task {
            do {
                try await authManager.sendEmailSignIn(email: normalizedEmail)
                pendingEmail = normalizedEmail
            } catch {
#if DEBUG
                print("Email sign-in request failed: \(String(reflecting: error))")
#endif
                errorMessage = emailDeliveryMessage(for: error)
            }
            isSendingCode = false
        }
    }

    private func emailDeliveryMessage(for error: Error) -> String {
        let message = error.localizedDescription.lowercased()
        if message.contains("rate limit") {
            return "Too many email attempts. Please wait a minute and try again."
        }
        if message.contains("confirmation email") {
            return "The email provider could not deliver this message. Please try again. If it continues, check the Supabase Auth logs for the SMTP response."
        }
        return error.localizedDescription
    }
}

struct EmailCodeVerificationView: View {
    @Environment(AuthManager.self) private var authManager
    @Environment(\.dismiss) private var dismiss

    let email: String

    @State private var code = ""
    @State private var isVerifying = false
    @State private var isResending = false
    @State private var errorMessage: String?
    @State private var resendSeconds = 60

    var body: some View {
        VStack(spacing: 26) {
            Spacer()

            Image(systemName: "envelope.badge.shield.half.filled")
                .font(.system(size: 68))
                .foregroundStyle(.indigo, .purple)

            VStack(spacing: 8) {
                Text("Check Your Email")
                    .font(.largeTitle.bold())
                Text("Enter the eight-digit code sent to")
                    .foregroundStyle(.secondary)
                Text(email)
                    .font(.headline)
            }
            .multilineTextAlignment(.center)

            TextField("00000000", text: $code)
                .keyboardType(.numberPad)
                .textContentType(.oneTimeCode)
                .font(.system(size: 32, weight: .bold, design: .rounded))
                .tracking(10)
                .multilineTextAlignment(.center)
                .padding()
                .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 16))
                .padding(.horizontal)
                .onChange(of: code) { _, newValue in
                    code = String(newValue.filter(\.isNumber).prefix(8))
                    if code.count == 8 {
                        verifyCode()
                    }
                }

            if let errorMessage {
                Text(errorMessage)
                    .font(.caption)
                    .foregroundStyle(.red)
                    .multilineTextAlignment(.center)
            }

            Button(action: verifyCode) {
                Group {
                    if isVerifying {
                        ProgressView().tint(.white)
                    } else {
                        Text("Verify Code").fontWeight(.semibold)
                    }
                }
                .frame(maxWidth: .infinity)
                .padding()
            }
            .buttonStyle(.plain)
            .background(.indigo, in: RoundedRectangle(cornerRadius: 16))
            .foregroundStyle(.white)
            .disabled(code.count != 8 || isVerifying)
            .padding(.horizontal)

            Text("You can also tap the sign-in link in the same email.")
                .font(.footnote)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)

            Button(resendSeconds > 0 ? "Resend in \(resendSeconds)s" : "Resend Code") {
                resendCode()
            }
            .disabled(resendSeconds > 0 || isResending)

            Button("Use a Different Email") {
                dismiss()
            }
            .foregroundStyle(.secondary)

            Spacer()
        }
        .padding()
        .navigationBarBackButtonHidden()
        .task {
            while resendSeconds > 0 {
                try? await Task.sleep(for: .seconds(1))
                resendSeconds -= 1
            }
        }
    }

    private func verifyCode() {
        guard code.count == 8, !isVerifying else { return }
        isVerifying = true
        errorMessage = nil

        Task {
            do {
                try await authManager.verifyEmailCode(email: email, token: code)
            } catch {
                errorMessage = "That code is invalid or expired. Request a new one and try again."
                isVerifying = false
            }
        }
    }

    private func resendCode() {
        isResending = true
        errorMessage = nil
        Task {
            do {
                try await authManager.sendEmailSignIn(email: email)
                code = ""
                resendSeconds = 60
            } catch {
                errorMessage = error.localizedDescription
            }
            isResending = false
        }
    }
}

private struct PasswordAuthView: View {
    @Environment(AuthManager.self) private var authManager
    @Environment(\.dismiss) private var dismiss

    @State private var isSignUp = false
    @State private var name = ""
    @State private var email = ""
    @State private var password = ""
    @State private var confirmPassword = ""
    @State private var isLoading = false
    @State private var errorMessage: String?
    @State private var showForgotPassword = false
    @State private var showConfirmation = false

    var body: some View {
        NavigationStack {
            Form {
                Picker("Mode", selection: $isSignUp) {
                    Text("Sign In").tag(false)
                    Text("Sign Up").tag(true)
                }
                .pickerStyle(.segmented)

                if isSignUp {
                    TextField("Full name", text: $name)
                        .textContentType(.name)
                }

                TextField("Email address", text: $email)
                    .textContentType(.emailAddress)
                    .keyboardType(.emailAddress)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()

                SecureField("Password", text: $password)
                    .textContentType(isSignUp ? .newPassword : .password)

                if isSignUp {
                    SecureField("Confirm password", text: $confirmPassword)
                        .textContentType(.newPassword)
                }

                if let errorMessage {
                    Text(errorMessage).foregroundStyle(.red)
                }

                Button(isSignUp ? "Create Account" : "Sign In") {
                    submit()
                }
                .disabled(!isValid || isLoading)

                if !isSignUp {
                    Button("Forgot Password?") {
                        showForgotPassword = true
                    }
                }
            }
            .navigationTitle(isSignUp ? "Create Account" : "Password Sign In")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
            .sheet(isPresented: $showForgotPassword) {
                ForgotPasswordSheet()
            }
            .alert("Check Your Email", isPresented: $showConfirmation) {
                Button("Done") { dismiss() }
            } message: {
                Text("Use the verification message sent to \(email), then return to sign in.")
            }
        }
    }

    private var isValid: Bool {
        if isSignUp {
            return !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                && email.contains("@")
                && password.count >= 8
                && password == confirmPassword
        }
        return email.contains("@") && !password.isEmpty
    }

    private func submit() {
        guard isValid, !isLoading else { return }
        isLoading = true
        errorMessage = nil

        Task {
            do {
                if isSignUp {
                    try await authManager.signUp(
                        email: email,
                        password: password,
                        phone: "",
                        fullName: name
                    )
                    showConfirmation = true
                } else {
                    try await authManager.signInWithEmail(email: email, password: password)
                    dismiss()
                }
            } catch {
                errorMessage = error.localizedDescription
            }
            isLoading = false
        }
    }
}

#Preview {
    AuthView()
        .environment(AuthManager())
}
