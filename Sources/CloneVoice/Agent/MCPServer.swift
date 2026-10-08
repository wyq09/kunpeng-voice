import Foundation

/// Minimal Model Context Protocol server over stdio (newline-delimited JSON-RPC 2.0).
@MainActor
final class MCPServer {
    private let speaker = HeadlessSpeaker()
    private let output: FileHandle

    init(output: FileHandle) {
        self.output = output
    }

    func run() async {
        do {
            for try await line in FileHandle.standardInput.bytes.lines where !line.isEmpty {
                await handle(line)
            }
        } catch {
            log("stdin closed: \(error)")
        }
    }

    // MARK: - JSON-RPC

    private func handle(_ line: String) async {
        guard let message = (try? JSONSerialization.jsonObject(with: Data(line.utf8))) as? [String: Any],
              let method = message["method"] as? String
        else {
            send(["jsonrpc": "2.0", "id": NSNull(), "error": ["code": -32700, "message": "Parse error"]])
            return
        }
        let id = message["id"]
        let params = message["params"] as? [String: Any] ?? [:]

        switch method {
        case "initialize":
            reply(id, [
                "protocolVersion": params["protocolVersion"] as? String ?? "2025-06-18",
                "capabilities": ["tools": [String: Any]()],
                "serverInfo": ["name": "clonevoice", "title": "鲲鹏有声", "version": "1.0"],
                "instructions": "用用户克隆的声音把文字读出来，生成本地 wav 文件。先调用 list_voices 查看可用声音，再调用 speak。",
            ])
        case "ping":
            reply(id, [:])
        case "tools/list":
            reply(id, ["tools": Self.tools])
        case "tools/call":
            let name = params["name"] as? String ?? ""
            let arguments = params["arguments"] as? [String: Any] ?? [:]
            reply(id, await callTool(name, arguments))
        default:
            guard let id else { return }
            send(["jsonrpc": "2.0", "id": id, "error": ["code": -32601, "message": "Method not found: \(method)"]])
        }
    }

    private func reply(_ id: Any?, _ result: [String: Any]) {
        guard let id else { return }
        send(["jsonrpc": "2.0", "id": id, "result": result])
    }

    private func send(_ object: [String: Any]) {
        guard var data = try? JSONSerialization.data(withJSONObject: object) else { return }
        data.append(0x0A)
        output.write(data)
    }

    private func log(_ text: String) {
        FileHandle.standardError.write(Data("[clonevoice] \(text)\n".utf8))
    }

    // MARK: - Tools

    private func callTool(_ name: String, _ arguments: [String: Any]) async -> [String: Any] {
        do {
            switch name {
            case "list_voices":
                return Self.text(listVoices())
            case "speak":
                return Self.text(try await speak(arguments))
            default:
                return Self.text("未知工具：\(name)", isError: true)
            }
        } catch {
            return Self.text(error.localizedDescription, isError: true)
        }
    }

    private func listVoices() -> String {
        let voices = speaker.voices
        guard !voices.isEmpty else { return HeadlessSpeaker.Failure.noVoices.localizedDescription }
        let lines = voices.enumerated().map { index, voice in
            "- \(voice.name)（\(voice.primaryLanguage.title)，样本 \(Int(voice.duration.rounded())) 秒）\(index == 0 ? " ← 默认" : "")"
        }
        return "可用的声音：\n" + lines.joined(separator: "\n")
    }

    private func speak(_ arguments: [String: Any]) async throws -> String {
        guard let text = arguments["text"] as? String,
              !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        else { return "缺少 text：请提供要读的文字。" }

        let output = (arguments["output_path"] as? String).map {
            URL(fileURLWithPath: ($0 as NSString).expandingTildeInPath)
        }
        let result = try await speaker.speak(
            text: text,
            voiceName: arguments["voice"] as? String,
            style: HeadlessSpeaker.style(named: arguments["style"] as? String),
            speed: HeadlessSpeaker.speed(named: arguments["speed"] as? String),
            output: output,
            source: .mcp
        )
        if arguments["play"] as? Bool == true { AudioPlayback.play(result.url) }
        return "已用「\(result.voiceName)」生成 \(String(format: "%.1f", result.duration)) 秒音频（\(result.modelName)）：\n\(result.url.path)"
    }

    private static func text(_ text: String, isError: Bool = false) -> [String: Any] {
        ["content": [["type": "text", "text": text]], "isError": isError]
    }

    private static let tools: [[String: Any]] = [
        [
            "name": "list_voices",
            "title": "列出克隆的声音",
            "description": "列出用户在「鲲鹏有声」里克隆的所有声音。",
            "inputSchema": ["type": "object", "properties": [String: Any]()],
        ],
        [
            "name": "speak",
            "title": "用克隆的声音说话",
            "description": """
            用用户克隆的声音把文字读出来，保存为 wav 文件并返回路径。完全在本机运行。
            文字里可以用 [生气]、[开心]、[害怕] 这样的标签分段控制情绪，标签作用到下一个标签为止。
            可用情绪：\(SpeechStyle.allCases.map(\.title).joined(separator: "、"))。
            """,
            "inputSchema": [
                "type": "object",
                "properties": [
                    "text": ["type": "string", "description": "要读的文字，可包含 [情绪] 标签"],
                    "voice": ["type": "string", "description": "声音名字，不填用最近创建的声音"],
                    "style": [
                        "type": "string",
                        "enum": SpeechStyle.allCases.map(\.title),
                        "description": "没有标签的文字用的情绪，默认「自然」",
                    ],
                    "speed": ["type": "string", "enum": ["慢", "正常", "快"], "description": "语速，默认正常"],
                    "output_path": ["type": "string", "description": "保存位置（.wav），默认 ~/Music/鲲鹏有声/"],
                    "play": ["type": "boolean", "description": "生成后直接在这台 Mac 上播放"],
                ],
                "required": ["text"],
            ],
        ],
    ]
}

enum AudioPlayback {
    /// Plays through `afplay` so playback outlives this process.
    static func play(_ url: URL) {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/afplay")
        process.arguments = [url.path]
        try? process.run()
    }
}
