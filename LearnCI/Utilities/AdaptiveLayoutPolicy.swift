import SwiftUI

enum AdaptiveLayoutPolicy {
    static let dashboardMaxContentWidth: CGFloat = 980
    static let dashboardTwoColumnMinimumWidth: CGFloat = 700
    static let learningSplitMinimumWidth: CGFloat = 700

    static func usesDashboardTwoColumns(for size: CGSize) -> Bool {
        size.width >= dashboardTwoColumnMinimumWidth || size.width > size.height
    }

    static func usesLearningSplit(for size: CGSize) -> Bool {
        size.width >= learningSplitMinimumWidth || size.width > size.height
    }

    static func usesLibraryMasterDetail(horizontalSizeClass: UserInterfaceSizeClass?) -> Bool {
        horizontalSizeClass == .regular
    }

    static func usesStoryReaderSidePane(horizontalSizeClass: UserInterfaceSizeClass?) -> Bool {
        horizontalSizeClass == .regular
    }

    static func usesPodcastPlayerSplit(horizontalSizeClass: UserInterfaceSizeClass?) -> Bool {
        horizontalSizeClass == .regular
    }
}
