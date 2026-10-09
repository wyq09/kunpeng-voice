import AppKit

enum DebugSnapshot {
    static func scheduleIfRequested() {
        guard let dir = ProcessInfo.processInfo.environment["KP_SNAPSHOT"] else { return }
        for (i, delay) in [3.0, 6.0].enumerated() {
            DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
                guard let window = NSApp.windows.first(where: { $0.isVisible }) else { return }
                guard let view = window.contentView?.superview ?? window.contentView,
                      let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds) else { return }
                view.cacheDisplay(in: view.bounds, to: rep)
                try? rep.representation(using: .png, properties: [:])?.write(to: URL(fileURLWithPath: "\(dir)/shot\(i).png"))
            }
        }
    }
}
