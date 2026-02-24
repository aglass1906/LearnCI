import SwiftUI

struct AboutCIView: View {
    @State private var document: AboutPageDocument?
    @State private var isLoading = true
    @State private var errorMessage: String?
    
    var body: some View {
        Group {
            if isLoading {
                ProgressView()
                    .progressViewStyle(CircularProgressViewStyle())
            } else if let error = errorMessage {
                VStack(spacing: 12) {
                    Image(systemName: "exclamationmark.triangle")
                        .font(.largeTitle)
                        .foregroundColor(.red)
                    Text("Error loading content")
                        .font(.headline)
                    Text(error)
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal)
                }
            } else if let document = document {
                ScrollView {
                    VStack(alignment: .leading, spacing: 32) {
                        ForEach(document.sections) { section in
                            AboutSectionRenderer(section: section, assets: document.assets)
                        }
                    }
                    .padding(.bottom, 60)
                }
                .navigationTitle(document.page.title)
                .navigationBarTitleDisplayMode(.inline)
            }
        }
        .onAppear {
            loadContent()
        }
    }
    
    private func loadContent() {
        guard let url = Bundle.main.url(forResource: "about_learning_en", withExtension: "json") else {
            self.errorMessage = "Could not find 'about_learning_en.json' in the app bundle."
            self.isLoading = false
            return
        }
        
        do {
            let data = try Data(contentsOf: url)
            let decoder = JSONDecoder()
            self.document = try decoder.decode(AboutPageDocument.self, from: data)
            self.isLoading = false
        } catch {
            print("Failed to decode about JSON: \(error)")
            self.errorMessage = error.localizedDescription
            self.isLoading = false
        }
    }
}
