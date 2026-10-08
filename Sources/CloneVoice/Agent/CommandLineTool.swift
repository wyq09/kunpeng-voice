import Foundation

/// `CloneVoice mcp | voices | speak …`. Any other launch opens the app.
enum CommandLineTool {
    static let commands: Set<String> = ["mcp", "voices", "speak", "help", "--help", "-h"]

    static func run(_ arguments: [String]) -> Never {
        // Model libraries print to stdout; keep it clean for results and the MCP protocol.
        let output = FileHandle(fileDescriptor: dup(STDOUT_FILENO), closeOnDealloc: true)
        dup2(STDERR_FILENO, STDOUT_FILENO)

        Task { @MainActor in
            let code = await execute(arguments, output: output)
            exit(code)
        }
        dispatchMain()
    }

    @MainActor
    private static func execute(_ arguments: [String], output: FileHandle) async -> Int32 {
        func say(_ text: String) { output.write(Data((text + "\n").utf8)) }
        func fail(_ text: String) -> Int32 {
            FileHandle.standardError.write(Data(("✗ " + text + "\n").utf8))
            return 1
        }

        switch arguments.first {
        case "mcp":
            await MCPServer(output: output).run()
            return 0

        case "voices":
            let speaker = HeadlessSpeaker()
            guard !speaker.voices.isEmpty else { return fail(HeadlessSpeaker.Failure.noVoices.localizedDescription) }
            speaker.voices.forEach { say("\($0.name)\t\($0.primaryLanguage.title)") }
            return 0

        case "speak":
            var options = Options(Array(arguments.dropFirst()))
            let voiceName = options.value("--voice", "-v")
            let styleName = options.value("--style", "-s")
            let speedName = options.value("--speed")
            let outputPath = options.value("--out", "-o")
            let shouldPlay = options.flag("--play")
            guard let text = options.text else { return fail("缺少要读的文字。\n\(usage)") }
            do {
                let speaker = HeadlessSpeaker()
                FileHandle.standardError.write(Data("正在生成…\n".utf8))
                let result = try await speaker.speak(
                    text: text,
                    voiceName: voiceName,
                    style: HeadlessSpeaker.style(named: styleName),
                    speed: HeadlessSpeaker.speed(named: speedName),
                    output: outputPath.map { URL(fileURLWithPath: ($0 as NSString).expandingTildeInPath) }
                )
                if shouldPlay {
                    let player = Process()
                    player.executableURL = URL(fileURLWithPath: "/usr/bin/afplay")
                    player.arguments = [result.url.path]
                    try? player.run()
                    player.waitUntilExit()
                }
                say(result.url.path)
                return 0
            } catch {
                return fail(error.localizedDescription)
            }

        default:
            say(usage)
            return 0
        }
    }

    static let usage = """
    鲲鹏有声 · 命令行
      voices                              列出声音
      speak "文字" [选项]                  生成语音，输出 wav 路径
        -v, --voice 名字                   默认最近创建的声音
        -s, --style 情绪                   如 开心、生气；文字里也可写 [生气]…
            --speed 慢|正常|快
        -o, --out 文件.wav                 默认 ~/Music/鲲鹏有声/
            --play                         生成后直接播放
      mcp                                 以 MCP 服务器运行（供 Agent 接入）
    """

    private struct Options {
        private var arguments: [String]

        init(_ arguments: [String]) { self.arguments = arguments }

        mutating func value(_ names: String...) -> String? {
            guard let index = arguments.firstIndex(where: names.contains), index + 1 < arguments.count else { return nil }
            let value = arguments[index + 1]
            arguments.removeSubrange(index...(index + 1))
            return value
        }

        mutating func flag(_ name: String) -> Bool {
            guard let index = arguments.firstIndex(of: name) else { return false }
            arguments.remove(at: index)
            return true
        }

        /// Whatever positional words remain once options are consumed.
        var text: String? {
            let positional = arguments.filter { !$0.hasPrefix("-") }
            return positional.isEmpty ? nil : positional.joined(separator: " ")
        }
    }
}
