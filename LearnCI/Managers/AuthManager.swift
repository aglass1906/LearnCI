import Foundation
import Observation
import Supabase
import GoogleSignIn
import UIKit
import CryptoKit

@Observable
class AuthManager {
    enum AuthState {
        case checking
        case authenticated(userID: String, email: String?, fullName: String?, avatarURL: String?)
        case unauthenticated
    }
    
    var isAuthenticated: Bool {
        if case .authenticated = state { return true }
        return false
    }
    
    var state: AuthState = .checking
    
    var currentUser: String? {
        if case .authenticated(let id, _, _, _) = state { return id }
        return nil
    }
    
    var currentUserEmail: String? {
        if case .authenticated(_, let email, _, _) = state { return email }
        return nil
    }
    
    var currentUserFullName: String? {
        if case .authenticated(_, _, let name, _) = state { return name }
        return nil
    }
    
    var currentUserAvatar: String? {
        if case .authenticated(_, _, _, let avatar) = state { return avatar }
        return nil
    }
    
    // MARK: - Supabase Client
    private let supabaseUrl = URL(string: "https://vuygqrbludhuywupcbma.supabase.co")!
    private let supabaseKey = "sb_publishable_xoxgBdG_hlMfn3SxbTJesA_gKfFkq70"
    
    let supabase: SupabaseClient
    var isPasswordResetRequired = false
    private let emailAuthRedirectURL = URL(string: "learnci://auth/callback")!

    init() {
        self.supabase = SupabaseClient(
            supabaseURL: supabaseUrl,
            supabaseKey: supabaseKey,
            options: SupabaseClientOptions(
                auth: SupabaseClientOptions.AuthOptions(emitLocalSessionAsInitialSession: true)
            )
        )
        checkSession()
        listenForAuthChanges()
    }
    
    private func listenForAuthChanges() {
        Task {
            for await (event, session) in supabase.auth.authStateChanges {
                print("DEBUG: Auth State Change Event: \(event)")
                if let session = session {
                    print("DEBUG: Session Present. User: \(session.user.email ?? "No Email")")
                } else {
                    print("DEBUG: Session is NIL")
                }
                
                await MainActor.run {
                        if event == .passwordRecovery {
                        print("DEBUG: Password Recovery Event Detected!")
                        self.isPasswordResetRequired = true
                        // Do not set unauthenticated here; wait for session to be established
                        // by the subsequent token exchange.
                        // Force a session check just in case.
                        self.checkSession()
                        return 
                    }
                    
                    if let session = session {
                        // Update state to authenticated
                        let metadata = session.user.userMetadata
                        let fullName = metadata["full_name"]?.value as? String
                        let avatarUrl = metadata["avatar_url"]?.value as? String
                        
                        print("DEBUG: Updating state to .authenticated")
                        self.state = .authenticated(
                            userID: session.user.id.uuidString,
                            email: session.user.email,
                            fullName: fullName,
                            avatarURL: avatarUrl
                        )
                    } else if event == .signedOut {
                         print("DEBUG: Event explains sign out. Setting state to .unauthenticated")
                         self.state = .unauthenticated
                    } else {
                        // For other events where session is nil, check session again to be sure
                        // before declaring unauthenticated, or just leave as is if we trust the event stream.
                        // Ideally we only go to unauthenticated on specific failure or sign out.
                         print("DEBUG: Defaulting to .unauthenticated due to nil session")
                         self.state = .unauthenticated
                    }
                }
            }
        }
    }
    
    func checkSession() {
        Task {
            do {
                let session = try await supabase.auth.session
                await MainActor.run {
                    // Extract metadata if available (providers like Google store it here)
                    let metadata = session.user.userMetadata
                    let fullName = metadata["full_name"]?.value as? String
                    let avatarUrl = metadata["avatar_url"]?.value as? String
                    let email = session.user.email
                    
                    self.state = .authenticated(
                        userID: session.user.id.uuidString,
                        email: email,
                        fullName: fullName,
                        avatarURL: avatarUrl
                    )
                }
            } catch {
                await MainActor.run {
                    self.state = .unauthenticated
                }
            }
        }
    }
    
    @MainActor
    func signInWithGoogle() {
        guard let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
              let rootViewController = windowScene.windows.first?.rootViewController else {
            print("Unable to find root view controller")
            return
        }
        
        guard let clientID = Bundle.main.object(forInfoDictionaryKey: "GIDClientID") as? String else {
            print("Error: GIDClientID not found in Info.plist")
            return
        }
        
        // 1. Generate nonce
        let nonce = randomNonceString()
        
        // 2. Configure Google Sign-In (Standard config, no nonce here for this SDK version)
        let config = GIDConfiguration(clientID: clientID)
        GIDSignIn.sharedInstance.configuration = config
        
        // Note: Ideally we pass the hashed nonce to Google here. 
        // If the SDK doesn't support it in config, we might need a different signIn method or it's not supported.
        // For now, we fix the build error.
        
        // Attempting to pass nonce directly to signIn based on SDK v9 capabilities
        GIDSignIn.sharedInstance.signIn(withPresenting: rootViewController, hint: nil, additionalScopes: nil, nonce: sha256(nonce)) { [weak self] result, error in
            guard let self = self else { return }
            
            if let error = error {
                print("Google Sign-In Error: \(error.localizedDescription)")
                return
            }
            
            guard let user = result?.user,
                  let idToken = user.idToken?.tokenString else {
                print("Error: No ID token found")
                return
            }
            
            Task {
                do {
                    // 3. Pass raw nonce to Supabase credentials
                    let session = try await self.supabase.auth.signInWithIdToken(credentials: .init(provider: .google, idToken: idToken, nonce: nonce))
                    
                    await MainActor.run {
                        // Extract profile from Google User object directly for freshness
                        let email = user.profile?.email
                        let fullName = user.profile?.name
                        let avatar = user.profile?.imageURL(withDimension: 200)?.absoluteString
                        
                        self.state = .authenticated(
                            userID: session.user.id.uuidString, 
                            email: email, 
                            fullName: fullName, 
                            avatarURL: avatar
                        )
                    }
                } catch {
                    print("Supabase Auth Error: \(error)")
                }
            }
        }
    }
    
    // MARK: - Email/Password & Phone Authentication
    
    @MainActor
    func signUp(email: String, password: String, phone: String, fullName: String) async throws {
        // Construct redirect URL
        let redirectURL = AppConfig.webPortalBaseURL
            .appendingPathComponent("auth")
            .appendingPathComponent("callback")
        
        var components = URLComponents(url: redirectURL, resolvingAgainstBaseURL: true)!
        components.queryItems = [URLQueryItem(name: "next", value: "/auth/verified")]
        
        // Sign up with email and password
        let _ = try await supabase.auth.signUp(
            email: email,
            password: password,
            data: [
                "full_name": .string(fullName),
                "phone": .string(phone)
            ],
            redirectTo: components.url
        )
        
        // Do NOT update state to .authenticated here.
        // The user must verify their email first.
    }
    
    @MainActor
    func resendVerificationEmail(email: String) async throws {
        // Note: Supabase Swift SDK v2.39.0 resend() does not support 'redirectTo'.
        // This will us redirect to the Site URL configured in Supabase Dashboard.
        try await supabase.auth.resend(email: email, type: .signup)
    }
    
    @MainActor
    func signInWithEmail(email: String, password: String) async throws {
        let session = try await supabase.auth.signIn(email: email, password: password)
        
        let metadata = session.user.userMetadata
        let fullName = metadata["full_name"]?.value as? String
        let avatarUrl = metadata["avatar_url"]?.value as? String
        
        self.state = .authenticated(
            userID: session.user.id.uuidString,
            email: session.user.email,
            fullName: fullName,
            avatarURL: avatarUrl
        )
    }

    @MainActor
    func sendEmailSignIn(email: String) async throws {
        try await supabase.auth.signInWithOTP(
            email: email.trimmingCharacters(in: .whitespacesAndNewlines).lowercased(),
            redirectTo: emailAuthRedirectURL,
            shouldCreateUser: true
        )
    }

    @MainActor
    func verifyEmailCode(email: String, token: String) async throws {
        let response = try await supabase.auth.verifyOTP(
            email: email.trimmingCharacters(in: .whitespacesAndNewlines).lowercased(),
            token: token,
            type: .email,
            redirectTo: emailAuthRedirectURL
        )

        if case .session(let session) = response {
            updateAuthenticatedState(from: session)
        }
    }
    
    @MainActor
    func updatePassword(password: String) async throws {
        try await supabase.auth.update(user: UserAttributes(password: password))
    }

    @MainActor
    func sendPasswordReset(email: String) async throws {
        // Must match a URL allowed in Supabase Dashboard -> Auth -> URL Configuration
        // And 'learnci://' must be added to Info.plist
        let redirectURL = URL(string: "learnci://reset-password")
        try await supabase.auth.resetPasswordForEmail(email, redirectTo: redirectURL)
    }
    
    func signOut() {
        Task {
            try? await supabase.auth.signOut()
            GIDSignIn.sharedInstance.signOut()
            await MainActor.run {
                self.state = .unauthenticated
            }
        }
    }
    
    @MainActor
    func handleIncomingURL(_ url: URL) async throws {
        print("DEBUG: AuthManager handling incoming URL: \(url.absoluteString)")
        
        // Explicitly check for password reset intent from the URL
        if url.absoluteString.contains("reset-password") {
            print("DEBUG: Detected reset-password URL scheme. Setting isPasswordResetRequired = true")
            self.isPasswordResetRequired = true
        }
        
        supabase.handle(url)
    }

    @MainActor
    private func updateAuthenticatedState(from session: Session) {
        let metadata = session.user.userMetadata
        state = .authenticated(
            userID: session.user.id.uuidString,
            email: session.user.email,
            fullName: metadata["full_name"]?.value as? String,
            avatarURL: metadata["avatar_url"]?.value as? String
        )
    }

    // MARK: - Crypto Helpers for Nonce
    
    private func randomNonceString(length: Int = 32) -> String {
        precondition(length > 0)
        var randomBytes = [UInt8](repeating: 0, count: length)
        let errorCode = SecRandomCopyBytes(kSecRandomDefault, randomBytes.count, &randomBytes)
        if errorCode != errSecSuccess {
            fatalError("Unable to generate nonce. SecRandomCopyBytes failed with OSStatus \(errorCode)")
        }
        
        let charset: [Character] =
            Array("0123456789ABCDEFGHIJKLMNOPQRSTUVXYZabcdefghijklmnopqrstuvwxyz-._")
        
        let nonce = randomBytes.map { byte in
            // Pick a random character from the set, wrapping around if needed.
            charset[Int(byte) % charset.count]
        }
        
        return String(nonce)
    }

    private func sha256(_ input: String) -> String {
        let inputData = Data(input.utf8)
        let hashedData = SHA256.hash(data: inputData)
        let hashString = hashedData.compactMap {
            return String(format: "%02x", $0)
        }.joined()
        return hashString
    }
}
