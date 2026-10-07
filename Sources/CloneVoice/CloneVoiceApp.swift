import AppKit
import SwiftUI

@main
struct CloneVoiceApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @State private var store = VoiceStore()
    @State private var engine = VoiceEngine()
    @State private var models = ModelManager()
    @State private var player = Player()

    var body: some Scene {
        WindowGroup("我的声音") {
            RootView()
                .environment(store)
                .environment(engine)
                .environment(models)
                .environment(player)
                .frame(minWidth: 820, minHeight: 560)
        }
        .windowStyle(.hiddenTitleBar)
        .defaultSize(width: 960, height: 620)
        .commands {
            CommandGroup(after: .appSettings) {
                Button("模型管理…") { models.isPresented = true }
                    .keyboardShortcut(",", modifiers: .command)
            }
        }
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)
        NSApp.activate()
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }
}
