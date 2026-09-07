import AppKit

@MainActor
enum ProviderMark {
    static let codex = load("OpenAI")
    static let claude = load("Claude")

    private static func load(_ name: String) -> NSImage {
        guard let url = Bundle.main.url(forResource: name, withExtension: "pdf"),
            let image = NSImage(contentsOf: url)
        else {
            return NSImage(systemSymbolName: "questionmark.square", accessibilityDescription: name) ?? NSImage()
        }
        image.size = NSSize(width: 18, height: 18)
        image.isTemplate = true
        return image
    }
}
