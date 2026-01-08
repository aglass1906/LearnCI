import SwiftUI

struct LayoutCardView<Content: View, Destination: View>: View {
    let title: String
    let subTitle: String?
    let accentColor: Color
    let icon: String?
    let destination: Destination? // Optional navigation destination
    let content: Content
    
    // Initializer for navigation-enabled card
    init(
        title: String,
        subTitle: String? = nil,
        accentColor: Color = .blue,
        icon: String? = nil,
        destination: Destination,
        @ViewBuilder content: () -> Content
    ) {
        self.title = title
        self.subTitle = subTitle
        self.accentColor = accentColor
        self.icon = icon
        self.destination = destination
        self.content = content()
    }
    
    // Initializer for static card (no navigation)
    init(
        title: String,
        subTitle: String? = nil,
        accentColor: Color = .blue,
        icon: String? = nil,
        @ViewBuilder content: () -> Content
    ) where Destination == EmptyView {
        self.title = title
        self.subTitle = subTitle
        self.accentColor = accentColor
        self.icon = icon
        self.destination = nil
        self.content = content()
    }
    
    var body: some View {
        if let destination = destination {
            NavigationLink(destination: destination) {
                cardBody
            }
            .buttonStyle(PlainButtonStyle()) // Ensure it doesn't look like a standard button
        } else {
            cardBody
        }
    }
    
    var cardBody: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Header Row
            HStack {
                if let icon = icon {
                    Image(systemName: icon)
                        .font(.title2)
                        .foregroundColor(accentColor)
                }
                
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.headline)
                        .fontWeight(.bold)
                        .foregroundColor(.primary)
                    
                    if let subTitle = subTitle {
                        Text(subTitle)
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
                
                Spacer()
                
                // If it's a link, show a chevron prompt
                if destination != nil {
                    Image(systemName: "chevron.right")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
            
            // Main Content
            content
        }
        .padding()
        .background(accentColor.opacity(0.1))
        .cornerRadius(16)
        .shadow(color: accentColor.opacity(0.1), radius: 2, x: 0, y: 1)
        .padding(.horizontal)
    }
}

#Preview {
    VStack {
        LayoutCardView(
            title: "Activity Breakdown",
            subTitle: "Today's Progress",
            accentColor: .blue,
            icon: "chart.bar.fill"
        ) {
            Text("Chart Goes Here")
                .frame(height: 100)
                .frame(maxWidth: .infinity)
                .background(Color.blue.opacity(0.2))
        }
        
        LayoutCardView(
            title: "Navigation Card",
            accentColor: .orange,
            icon: "star.fill",
            destination: Text("New View")
        ) {
            Text("Tap to go to detail view")
        }
    }
}
