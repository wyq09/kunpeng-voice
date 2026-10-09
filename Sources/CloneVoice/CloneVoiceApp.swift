import AppKit
import SwiftUI

@main
enum AppEntry {
    static func main() {
        let arguments = Array(CommandLine.arguments.dropFirst())
        if let command = arguments.first, CommandLineTool.commands.contains(command) {
            CommandLineTool.run(arguments)
        }
        CloneVoiceApp.main()
    }
}

struct CloneVoiceApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @State private var store = VoiceStore()
    @State private var engine = VoiceEngine()
    @State private var models = ModelManager()
    @State private var player = Player()
    @State private var agentSetup = AgentSetup()
    @State private var jobs = JobStore()
    @State private var phrasing = SmartPhrasing()
    @State private var generator = Generator()

    var body: some Scene {
        WindowGroup("鲲鹏有声") {
            RootView()
                .environment(store)
                .environment(engine)
                .environment(models)
                .environment(player)
                .environment(agentSetup)
                .environment(jobs)
                .environment(phrasing)
                .environment(generator)
                .frame(minWidth: 860, minHeight: 680)
        }
        .windowStyle(.hiddenTitleBar)
        .defaultSize(width: 1080, height: 760)
        .commands {
            CommandGroup(after: .appSettings) {
                Button("模型管理…") { models.isPresented = true }
                    .keyboardShortcut(",", modifiers: .command)
                Button("接入 Agent…") { agentSetup.isPresented = true }
                Button("智能断句…") { phrasing.isPresented = true }
            }
        }
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)
        AppBrandIcon.installIfNeeded()
        NSApp.activate()
        DebugSnapshot.scheduleIfRequested()
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }
}
