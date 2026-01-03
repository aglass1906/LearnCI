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
        case authenticated(userID: String)
        case unauthenticated
    }
    
    var state: AuthState = .checking
    var currentUser: String? {
        if case .authenticated(let id) = state {
            return id
        }
        return nil
    }
    
    // MARK: - Supabase Client
    private let supabaseUrl = URL(string: "https://vuygqrbludhuywupcbma.supabase.co")!
    private let supabaseKey = "sb_publishable_xoxgBdG_hlMfn3SxbTJesA_gKfFkq70"
    
    let supabase: SupabaseClient

    init() {
        self.supabase = SupabaseClient(
            supabaseURL: supabaseUrl,
            supabaseKey: supabaseKey,
            options: SupabaseClientOptions(
                auth: SupabaseClientOptions.AuthOptions(emitLocalSessionAsInitialSession: true)
            )
        )
        checkSession()
    }
    
    func checkSession() {
        Task {
            do {
                let session = try await supabase.auth.session
                await MainActor.run {
                    self.state = .authenticated(userID: session.user.id.uuidString)
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
                    _ = try await self.supabase.auth.signInWithIdToken(credentials: .init(provider: .google, idToken: idToken, nonce: nonce))
                    await MainActor.run {
                        self.state = .authenticated(userID: user.userID ?? UUID().uuidString)
                    }
                } catch {
                    print("Supabase Auth Error: \(error)")
                }
            }
        }
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
