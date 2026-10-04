enum MenuViewMode: String, CaseIterable, Identifiable {
    case compact
    case detailed

    var id: String { rawValue }
    var title: String { self == .compact ? "Compact" : "Detailed" }
}
