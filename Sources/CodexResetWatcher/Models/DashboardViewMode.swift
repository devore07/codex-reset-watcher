import Foundation

enum DashboardViewMode: String, CaseIterable, Identifiable {
    case compact
    case detailed

    var id: String { rawValue }
    var title: String { self == .compact ? "Compact" : "Detailed" }
    var minimumSize: CGSize {
        self == .compact
            ? CGSize(width: CodexStyle.Size.compactWindowWidth, height: CodexStyle.Size.compactWindowHeight)
            : CGSize(width: CodexStyle.Size.mainWindowMinWidth, height: CodexStyle.Size.mainWindowMinHeight)
    }
    var defaultSize: CGSize {
        self == .compact
            ? minimumSize
            : CGSize(width: CodexStyle.Size.mainWindowDefaultWidth, height: CodexStyle.Size.mainWindowDefaultHeight)
    }
}
