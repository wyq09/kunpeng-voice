import AppKit
import SwiftUI

@main
struct CloneVoiceApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @State private var store = VoiceStore()
    @State private var engine = VoiceEngine()
    @State private var player = Player()

    var body: some Scene {
        WindowGroup("我的声音") {
            RootView()
                .environment(store)
                .environment(engine)
                .environment(player)
                .frame(minWidth: 820, minHeight: 560)
                .task { engine.prepare() }
        }
        .windowStyle(.hiddenTitleBar)
        .defaultSize(width: 960, height: 620)
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)
        NSApp.activate()
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }
}
