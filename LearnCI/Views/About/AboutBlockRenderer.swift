import SwiftUI

struct AboutBlockRenderer: View {
    let block: ContentBlock
    let assets: [String: AssetDefinition]
    
    // No router environment needed for simple NavigationLink routing
    var body: some View {
        switch block.type {
        case .hero:
            heroBlock
        case .callout:
            calloutBlock
        case .card:
            cardBlock
        case .step:
            stepBlock
        case .faq:
            faqBlock
        case .buttonRow:
            buttonRowBlock
        case .link:
            linkBlock
        case .unknown, .none:
            // Safe fallback: render nothing for unknown types
            EmptyView()
        }
    }
    
    // MARK: - Hero
    @ViewBuilder
    private var heroBlock: some View {
        VStack(spacing: 16) {
            if let mediaId = block.media?.assetId,
               let asset = assets[mediaId],
               asset.type == "image",
               let src = asset.src {
                let imageName = src.replacingOccurrences(of: ".png", with: "").replacingOccurrences(of: "about/", with: "")
                if imageName == "ci_hero" {
                    CommonHeroView()
                } else {
                    Group {
                        if let path = Bundle.main.path(forResource: imageName, ofType: "png", inDirectory: "Images"),
                           let uiImage = UIImage(contentsOfFile: path) {
                            Image(uiImage: uiImage)
                                .resizable()
                        } else if let path = Bundle.main.path(forResource: imageName, ofType: "png"),
                                  let uiImage = UIImage(contentsOfFile: path) {
                            Image(uiImage: uiImage)
                                .resizable()
                        } else if let uiImage = UIImage(named: imageName) {
                            Image(uiImage: uiImage)
                                .resizable()
                        } else {
                            Image(systemName: "photo")
                                .resizable()
                        }
                    }
                    .scaledToFit()
                    .frame(height: 200)
                    .cornerRadius(12)
                }
            }
            
            if let title = block.title {
                Text(title)
                    .font(.custom("AvenirNext-Bold", size: 28))
                    .multilineTextAlignment(.center)
            }
            
            if let subtitle = block.subtitle {
                Text(subtitle)
                    .font(.body)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
            }
            
            if let badges = block.badges, !badges.isEmpty {
                HStack(spacing: 8) {
                    ForEach(badges, id: \.self) { badge in
                        Text(badge)
                            .font(.caption)
                            .fontWeight(.semibold)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 4)
                            .background(Color.blue.opacity(0.1))
                            .foregroundColor(.blue)
                            .cornerRadius(8)
                    }
                }
                .padding(.top, 4)
            }
        }
        .padding(.vertical)
    }
    
    // MARK: - Callout
    @ViewBuilder
    private var calloutBlock: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: block.style == "info" ? "info.circle.fill" : "lightbulb.fill")
                .foregroundColor(block.style == "info" ? .blue : .blue)
                .font(.title2)
            
            if let text = block.text {
                Text(text)
                    .font(.subheadline)
                    .foregroundColor(.primary)
            }
            Spacer(minLength: 0)
        }
        .padding()
        .background(Color.blue.opacity(0.1))
        .cornerRadius(12)
    }
    
    // MARK: - Card
    @ViewBuilder
    private var cardBlock: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let title = block.title {
                Text(title)
                    .font(.custom("AvenirNext-DemiBold", size: 18))
            }
            if let body = block.body {
                Text(body)
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            }
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(UIColor.secondarySystemGroupedBackground))
        .cornerRadius(12)
        .shadow(color: Color.black.opacity(0.05), radius: 5, x: 0, y: 2)
    }
    
    // MARK: - Step
    @ViewBuilder
    private var stepBlock: some View {
        let content = HStack(alignment: .top, spacing: 16) {
            // Index Circle or Icon
            ZStack {
                Circle()
                    .fill(Color.blue.opacity(0.2))
                    .frame(width: 40, height: 40)
                
                if let iconId = block.icon?.assetId,
                   let asset = assets[iconId],
                   asset.type == "icon",
                   let iconName = asset.name {
                    Image(systemName: iconName)
                        .foregroundColor(.blue)
                        .font(.headline)
                } else if let index = block.index {
                    Text("\(index)")
                        .font(.headline)
                        .fontWeight(.bold)
                        .foregroundColor(.blue)
                }
            }
            
            VStack(alignment: .leading, spacing: 4) {
                if let title = block.title {
                    HStack {
                        Text(title)
                            .font(.custom("AvenirNext-DemiBold", size: 18))
                        if block.url != nil {
                            Image(systemName: "arrow.up.right.square")
                                .font(.subheadline)
                                .foregroundColor(.blue)
                        }
                    }
                }
                if let body = block.body {
                    Text(body)
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }
            }
            .padding(.top, 4)
            
            Spacer(minLength: 0)
        }
        
        if let urlString = block.url, let url = URL(string: urlString) {
            Link(destination: url) {
                content
            }
            .buttonStyle(PlainButtonStyle())
        } else {
            content
        }
    }
    
    // MARK: - Link
    @ViewBuilder
    private var linkBlock: some View {
        if let urlString = block.url, let url = URL(string: urlString) {
            Link(destination: url) {
                HStack(spacing: 12) {
                    if let iconId = block.icon?.assetId,
                       let asset = assets[iconId],
                       asset.type == "icon",
                       let iconName = asset.name {
                        Image(systemName: iconName)
                            .foregroundColor(.blue)
                    } else {
                        Image(systemName: "link")
                            .foregroundColor(.blue)
                    }
                    
                    VStack(alignment: .leading, spacing: 2) {
                        if let title = block.title {
                            Text(title)
                                .font(.headline)
                                .foregroundColor(.primary)
                        }
                        if let body = block.body {
                            Text(body)
                                .font(.subheadline)
                                .foregroundColor(.secondary)
                        }
                    }
                    Spacer()
                    Image(systemName: "chevron.right")
                        .foregroundColor(.secondary)
                }
                .padding()
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color(UIColor.secondarySystemGroupedBackground))
                .cornerRadius(12)
                .shadow(color: Color.black.opacity(0.05), radius: 5, x: 0, y: 2)
            }
            .buttonStyle(PlainButtonStyle())
        }
    }
    
    // MARK: - FAQ
    @ViewBuilder
    private var faqBlock: some View {
        if let question = block.q, let answer = block.a {
            DisclosureGroup {
                Text(answer)
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.vertical, 8)
            } label: {
                Text(question)
                    .font(.custom("AvenirNext-DemiBold", size: 16))
                    .foregroundColor(.primary)
            }
            .padding()
            .background(Color(UIColor.secondarySystemGroupedBackground))
            .cornerRadius(12)
        }
    }
    
    // MARK: - Button Row
    @ViewBuilder
    private var buttonRowBlock: some View {
        if let buttons = block.buttons {
            HStack(spacing: 12) {
                ForEach(buttons) { button in
                    if button.action.type == "navigate" {
                        NavigationLink(destination: destination(for: button)) {
                            buttonStyle(for: button)
                        }
                    } else {
                        Button(action: { }) {
                            buttonStyle(for: button)
                        }
                    }
                }
            }
        }
    }
    
    @ViewBuilder
    private func destination(for button: ButtonDefinition) -> some View {
        if button.action.route == "/stories" {
            InputDiscoveryView()
        } else {
            // Default destination for unrecognized routes
            VStack(spacing: 16) {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundColor(.green)
                    .font(.system(size: 60))
                Text("Ready to Learn!")
                    .font(.title2)
                    .fontWeight(.bold)
                Text("Head back to the dashboard to select a level.")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            }
            .padding()
        }
    }
    
    private func buttonStyle(for button: ButtonDefinition) -> some View {
        Text(button.label)
            .font(.headline)
            .frame(maxWidth: .infinity)
            .padding()
            .background(button.style == "secondary" ? Color.blue.opacity(0.1) : Color.blue)
            .foregroundColor(button.style == "secondary" ? .white : .white)
            .cornerRadius(12)
    }
}
