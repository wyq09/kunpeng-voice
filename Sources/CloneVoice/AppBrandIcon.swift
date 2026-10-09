import AppKit

/// Loads the kunpeng mark from the app bundle. `applicationIconImage` is often empty
/// until the dock icon is resolved, and particle sampling must not cache that miss forever.
enum AppBrandIcon {
    static func installIfNeeded() {
        guard let image = loadFromBundle() else { return }
        NSApplication.shared.applicationIconImage = image
    }

    static func image() -> NSImage? {
        if let bundled = loadFromBundle() { return bundled }
        let app = NSApplication.shared.applicationIconImage
        guard let app, app.size.width >= 32, app.size.height >= 32 else { return nil }
        return app
    }

    private static func loadFromBundle() -> NSImage? {
        for (name, ext) in [("AppIcon", "icns"), ("AppIcon-1024", "png")] {
            guard let url = Bundle.main.url(forResource: name, withExtension: ext),
                  let image = NSImage(contentsOf: url) else { continue }
            return image
        }
        return nil
    }
}
