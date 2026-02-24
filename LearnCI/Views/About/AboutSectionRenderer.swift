import SwiftUI

struct AboutSectionRenderer: View {
    let section: PageSection
    let assets: [String: AssetDefinition]
    
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            // Render section header if present
            if let headerTitle = section.header?.title {
                Text(headerTitle)
                    .font(.custom("AvenirNext-Bold", size: 22))
                    .padding(.top, 10)
                    .padding(.horizontal)
            }
            
            // Render blocks using the Layout hint
            let gap = spacing(for: section.layout.gap)
            
            switch section.layout.type {
            case "stack":
                VStack(spacing: gap) {
                    blocksForEach
                }
                .padding(padding(for: section.layout.padding))
                
            case "cards":
                let cols = section.layout.columns ?? 1
                if cols > 1 {
                    LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: gap), count: cols), spacing: gap) {
                        blocksForEach
                    }
                    .padding(padding(for: section.layout.padding))
                } else {
                    VStack(spacing: gap) {
                        blocksForEach
                    }
                    .padding(padding(for: section.layout.padding))
                }
                
            case "steps":
                // Render steps in a vertical stack
                VStack(spacing: gap) {
                    blocksForEach
                }
                .padding(padding(for: section.layout.padding))
                
            case "accordion":
                // Standard VStack holding the DisclosureGroups
                VStack(spacing: gap) {
                    blocksForEach
                }
                .padding(padding(for: section.layout.padding))
                
            default:
                // Fallback layout
                VStack(spacing: gap) {
                    blocksForEach
                }
                .padding(.horizontal)
            }
        }
    }
    
    private var blocksForEach: some View {
        ForEach(section.blocks) { block in
            AboutBlockRenderer(block: block, assets: assets)
        }
    }
    
    // Helper to map JSON margin/padding string to CGFloat
    private func spacing(for value: String?) -> CGFloat {
        switch value {
        case "sm": return 8
        case "md": return 16
        case "lg": return 24
        default: return 16
        }
    }
    
    private func padding(for value: String?) -> EdgeInsets {
        switch value {
        case "sm": return EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16)
        case "md": return EdgeInsets(top: 16, leading: 16, bottom: 16, trailing: 16)
        case "lg": return EdgeInsets(top: 24, leading: 16, bottom: 24, trailing: 16)
        default: return EdgeInsets(top: 0, leading: 16, bottom: 0, trailing: 16)
        }
    }
}
