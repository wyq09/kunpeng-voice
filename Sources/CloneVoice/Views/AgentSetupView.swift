import AppKit
import Observation
import SwiftUI

@MainActor
@Observable
final class AgentSetup {
    var isPresented = false
}

/// Step-by-step instructions for connecting the MCP server / CLI to other agents.
struct AgentSetupView: View {
    @Environment(\.dismiss) private var dismiss
    @AppStorage("agentSetupClient") private var client: Client = .claudeCode
    @State private var cliPath = CLIInstaller.installedPath

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            Divider()
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    Picker("Agent", selection: $client) {
                        ForEach(Client.allCases) { Text($0.title).tag($0) }
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()

                    steps
                    if !Integration.isInApplicationsFolder { locationNotice }
                    Divider()
                    tryIt
                }
                .padding(20)
            }
        }
        .frame(width: 620, height: 560)
    }

    private var header: some View {
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: 4) {
                Text("接入 Agent").font(.title3.weight(.semibold))
                Text("让 Claude Code、Cursor、Codex 等用你的声音说话。全程在这台 Mac 上运行，不上传任何数据。")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Button("完成") { dismiss() }.keyboardShortcut(.defaultAction)
        }
        .padding(20)
    }

    @ViewBuilder
    private var steps: some View {
        switch client {
        case .claudeCode:
            Step(number: 1, title: "在终端运行这条命令") {
                CodeBlock(Integration.claudeCommand)
            }
            Step(number: 2, title: "重启 Claude Code，输入 /mcp 能看到 clonevoice 就成功了") {}
        case .cursor:
            Step(number: 1, title: "一键添加到 Cursor，在弹出的窗口里点 Install") {
                Button {
                    NSWorkspace.shared.open(Integration.cursorDeeplink)
                } label: {
                    Label("添加到 Cursor", systemImage: "plus.circle.fill")
                }
                .buttonStyle(.borderedProminent)
            }
            Step(number: 2, title: "没反应？手动把下面的内容合并进 ~/.cursor/mcp.json") {
                CodeBlock(Integration.mcpJSON)
            }
        case .codex:
            Step(number: 1, title: "在终端运行这条命令") {
                CodeBlock(Integration.codexCommand)
            }
            Step(number: 2, title: "或者手动加到 ~/.codex/config.toml") {
                CodeBlock(Integration.codexTOML)
            }
        case .other:
            Step(number: 1, title: "在 Agent 的 MCP 设置里新增一个 stdio 服务器，粘贴这段配置") {
                CodeBlock(Integration.mcpJSON)
            }
            Step(number: 2, title: "适用于 Claude Desktop、Cherry Studio、Windsurf、Cline 等支持 MCP 的应用") {}
        case .cli:
            Step(number: 1, title: "安装 clonevoice 命令（脚本、Agent 的终端都能直接调用）") {
                HStack(spacing: 10) {
                    Button(cliPath == nil ? "安装命令" : "重新安装") {
                        cliPath = CLIInstaller.install()
                    }
                    if let cliPath {
                        Label("已安装到 \(cliPath)", systemImage: "checkmark.circle.fill")
                            .font(.caption)
                            .foregroundStyle(.green)
                    }
                }
                if let cliPath, !CLIInstaller.isOnPath(cliPath) {
                    Text("这个目录不在 PATH 里，在终端运行下面一行后重开终端：")
                        .font(.caption)
                        .foregroundStyle(.orange)
                    CodeBlock(CLIInstaller.pathFix(for: cliPath))
                }
            }
            Step(number: 2, title: "使用") {
                CodeBlock(Integration.cliExamples(command: cliPath == nil ? Integration.quotedExecutable : "clonevoice"))
            }
        }
    }

    private var locationNotice: some View {
        Label {
            Text("应用现在放在「\(Integration.appLocation)」。配置里记录的是这个位置，之后挪到「应用程序」文件夹的话需要重新复制一次。")
        } icon: {
            Image(systemName: "info.circle")
        }
        .font(.caption)
        .foregroundStyle(.secondary)
    }

    private var tryIt: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("接好后，试着对 Agent 说").font(.headline)
            CodeBlock("用我的声音读出来并播放：[开心]今天的任务都完成啦！[平静]明天见。")
            Text("Agent 会调用 speak 工具，音频默认保存在 ~/Music/我的声音/。文字里的 [情绪] 标签同样有效。")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    enum Client: String, CaseIterable, Identifiable {
        case claudeCode, cursor, codex, other, cli

        var id: Self { self }

        var title: String {
            switch self {
            case .claudeCode: "Claude Code"
            case .cursor: "Cursor"
            case .codex: "Codex"
            case .other: "其他 MCP"
            case .cli: "命令行"
            }
        }
    }
}

private struct Step<Content: View>: View {
    let number: Int
    let title: String
    @ViewBuilder var content: Content

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Text("\(number)")
                .font(.caption.weight(.bold))
                .foregroundStyle(.white)
                .frame(width: 20, height: 20)
                .background(Color.accentColor, in: Circle())
            VStack(alignment: .leading, spacing: 8) {
                Text(title).fixedSize(horizontal: false, vertical: true)
                content
            }
        }
    }
}

/// Monospaced snippet with a one-click copy button.
private struct CodeBlock: View {
    let code: String
    @State private var didCopy = false

    init(_ code: String) { self.code = code }

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Text(code)
                .font(.system(.callout, design: .monospaced))
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
                .fixedSize(horizontal: false, vertical: true)
            Button {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(code, forType: .string)
                didCopy = true
                Task {
                    try? await Task.sleep(for: .seconds(1.5))
                    didCopy = false
                }
            } label: {
                Label(didCopy ? "已复制" : "复制", systemImage: didCopy ? "checkmark" : "doc.on.doc")
                    .labelStyle(.titleAndIcon)
                    .font(.caption)
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
        }
        .padding(10)
        .background(.quaternary.opacity(0.6), in: RoundedRectangle(cornerRadius: 8))
    }
}

// MARK: - Snippets

enum Integration {
    static let serverName = "clonevoice"

    static var executablePath: String { Bundle.main.executableURL?.path ?? "/Applications/我的声音.app/Contents/MacOS/CloneVoice" }
    static var quotedExecutable: String { shellQuoted(executablePath) }

    static var appLocation: String { Bundle.main.bundleURL.deletingLastPathComponent().path }
    static var isInApplicationsFolder: Bool { Bundle.main.bundleURL.path.hasPrefix("/Applications/") }

    static var claudeCommand: String { "claude mcp add \(serverName) --scope user -- \(quotedExecutable) mcp" }
    static var codexCommand: String { "codex mcp add \(serverName) -- \(quotedExecutable) mcp" }

    static var codexTOML: String {
        """
        [mcp_servers.\(serverName)]
        command = "\(executablePath)"
        args = ["mcp"]
        """
    }

    static var serverConfig: [String: Any] { ["command": executablePath, "args": ["mcp"]] }

    static var mcpJSON: String { json(["mcpServers": [serverName: serverConfig]]) }

    static var cursorDeeplink: URL {
        let config = Data(json(serverConfig).utf8).base64EncodedString()
        var components = URLComponents(string: "cursor://anysphere.cursor-deeplink/mcp/install")!
        components.queryItems = [URLQueryItem(name: "name", value: serverName), URLQueryItem(name: "config", value: config)]
        return components.url!
    }

    static func cliExamples(command: String) -> String {
        """
        \(command) voices
        \(command) speak "[开心]你好呀！[平静]今天过得怎么样？" --play
        \(command) speak "欢迎收听" --voice 我的声音 --style 播音 --out ~/Desktop/intro.wav
        """
    }

    static func shellQuoted(_ value: String) -> String {
        "'" + value.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }

    private static func json(_ object: Any) -> String {
        guard let data = try? JSONSerialization.data(
            withJSONObject: object, options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        ) else { return "{}" }
        return String(decoding: data, as: UTF8.self)
    }
}

/// Installs a tiny `clonevoice` wrapper script that forwards to the app's executable.
enum CLIInstaller {
    private static let candidates = ["/usr/local/bin", "/opt/homebrew/bin", NSHomeDirectory() + "/.local/bin"]

    static var installedPath: String? {
        candidates.map { $0 + "/clonevoice" }.first { FileManager.default.fileExists(atPath: $0) }
    }

    static func install() -> String? {
        let script = "#!/bin/sh\nexec \(Integration.quotedExecutable) \"$@\"\n"
        let fm = FileManager.default
        for directory in candidates {
            try? fm.createDirectory(atPath: directory, withIntermediateDirectories: true)
            let path = directory + "/clonevoice"
            guard fm.isWritableFile(atPath: directory) else { continue }
            try? fm.removeItem(atPath: path)
            guard fm.createFile(atPath: path, contents: Data(script.utf8), attributes: [.posixPermissions: 0o755]) else { continue }
            return path
        }
        return nil
    }

    static func isOnPath(_ path: String) -> Bool {
        let directory = (path as NSString).deletingLastPathComponent
        let shellPath = ProcessInfo.processInfo.environment["PATH"] ?? ""
        return directory.hasPrefix("/usr/local") || directory.hasPrefix("/opt/homebrew") || shellPath.split(separator: ":").contains { $0 == directory }
    }

    static func pathFix(for path: String) -> String {
        let directory = (path as NSString).deletingLastPathComponent.replacingOccurrences(of: NSHomeDirectory(), with: "$HOME")
        return "echo 'export PATH=\"\(directory):$PATH\"' >> ~/.zshrc"
    }
}
