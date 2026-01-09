import SwiftUI
import SwiftData

struct ProfileAccountSettingsView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @Environment(AuthManager.self) private var authManager
    @Environment(LocationManager.self) private var locationManager
    
    let profile: UserProfile
    
    @State private var name: String = ""
    @State private var location: String = ""
    @State private var isEditing: Bool = false
    @State private var showChangePassword = false
    
    var body: some View {
        Form {
            Section(header: Text("Public Profile")) {
                if isEditing {
                    TextField("Display Name", text: $name)
                    
                    VStack(alignment: .leading, spacing: 10) {
                        HStack {
                            TextField("Location", text: $location)
                                .textContentType(.location)
                            
                            Button(action: {
                                locationManager.requestLocationAndAddress()
                            }) {
                                Image(systemName: "location.fill")
                                    .foregroundColor(.blue)
                            }
                        }
                    }
                } else {
                    LabeledContent("Display Name", value: name)
                    LabeledContent("Location", value: location)
                }
            }
            
            // Google Account Info (Read Only)
            if let email = authManager.currentUserEmail {
                Section(header: Text("Google Account")) {
                    LabeledContent("Email", value: email)
                    if let fullName = authManager.currentUserFullName {
                        LabeledContent("Full Name", value: fullName)
                    }
                }
            }
            
            Section(header: Text("Security")) {
                Button("Change Password") {
                    showChangePassword = true
                }
                
                Button("Sign Out", role: .destructive) {
                    authManager.signOut()
                }
            }
        }
        .navigationTitle("Account")
        .navigationBarBackButtonHidden(isEditing)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                 if isEditing {
                     Button("Save") {
                         saveData()
                         withAnimation { isEditing = false }
                     }
                     .fontWeight(.bold)
                 } else {
                     Button("Edit") {
                         withAnimation { isEditing = true }
                     }
                 }
            }
            
            if isEditing {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") {
                        loadData()
                        withAnimation { isEditing = false }
                    }
                }
            }
        }
        .onChange(of: locationManager.locationString) { _, newLocation in
             if let loc = newLocation, isEditing {
                 location = loc
             }
         }
        .onAppear {
            loadData()
        }
        .sheet(isPresented: $showChangePassword) {
            ChangePasswordSheet()
        }
    }
    
    private func loadData() {
        name = profile.name
        location = profile.location ?? ""
    }
    
    private func saveData() {
        profile.name = name
        profile.location = location
        profile.updatedAt = Date()
    }
}
