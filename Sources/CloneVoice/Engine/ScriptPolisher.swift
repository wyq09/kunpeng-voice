import Foundation

/// OpenAI-compatible chat endpoints that can re-punctuate a script for reading aloud.
enum PolisherProvider: String, Codable, CaseIterable, Identifiable {
    case deepseek, qwen, zhipu, kimi, openai, ollama, custom

    var id: String { rawValue }

    var title: String {
        switch self {
        case .deepseek: "DeepSeek"
        case .qwen: "通义千问"
        case .zhipu: "智谱 GLM"
        case .kimi: "Kimi"
        case .openai: "OpenAI"
        case .ollama: "Ollama（本机）"
        case .custom: "自定义"
        }
    }

    var baseURL: String {
        switch self {
        case .deepseek: "https://api.deepseek.com/v1"
        case .qwen: "https://dashscope.aliyuncs.com/compatible-mode/v1"
        case .zhipu: "https://open.bigmodel.cn/api/paas/v4"
        case .kimi: "https://api.moonshot.cn/v1"
        case .openai: "https://api.openai.com/v1"
        case .ollama: "http://localhost:11434/v1"
        case .custom: ""
        }
    }

    var model: String {
        switch self {
        case .deepseek: "deepseek-chat"
        case .qwen: "qwen-plus"
        case .zhipu: "glm-4-flash"
        case .kimi: "moonshot-v1-8k"
        case .openai: "gpt-4o-mini"
        case .ollama: "qwen3:4b"
        case .custom: ""
        }
    }

    var keyPage: URL? {
        switch self {
        case .deepseek: URL(string: "https://platform.deepseek.com/api_keys")
        case .qwen: URL(string: "https://bailian.console.aliyun.com/?apiKey=1")
        case .zhipu: URL(string: "https://open.bigmodel.cn/usercenter/apikeys")
        case .kimi: URL(string: "https://platform.moonshot.cn/console/api-keys")
        case .openai: URL(string: "https://platform.openai.com/api-keys")
        case .ollama, .custom: nil
        }
    }

    var needsKey: Bool { self != .ollama }
}

/// Phrasing styles the user starts from; the chosen text stays editable.
enum PromptPreset: String, Codable, CaseIterable, Identifiable {
    case voiceover, story, news, custom

    var id: String { rawValue }

    var title: String {
        switch self {
        case .voiceover: "口播"
        case .story: "讲故事"
        case .news: "新闻播报"
        case .custom: "自定义"
        }
    }

    var prompt: String {
        switch self {
        case .voiceover:
            "你是口播稿断句编辑。按真人口播的自然停顿调整标点：太长的句子在意群处加逗号，句子结束用句号、问号或感叹号，不要在词语中间断开；转折、强调前可以稍作停顿。"
        case .story:
            "你是有声书断句编辑。像讲故事一样断句：节奏放慢，对话、转折和情绪变化处多停顿，长句拆成短句，用逗号和句号营造呼吸感。"
        case .news:
            "你是新闻播报断句编辑。按新闻播报的节奏断句：句子短而清楚，主语和谓语之间不断开，数字、人名、机构名保持完整，每句以句号结束。"
        case .custom:
            ""
        }
    }
}

struct PolisherConfig: Codable, Equatable {
    var isEnabled = false
    var provider = PolisherProvider.deepseek
    var baseURL = PolisherProvider.deepseek.baseURL
    var model = PolisherProvider.deepseek.model
    var apiKey = ""
    var preset = PromptPreset.voiceover
    var prompt = PromptPreset.voiceover.prompt

    var isUsable: Bool {
        isEnabled && URL(string: baseURL)?.host != nil && !model.isEmpty && (!provider.needsKey || !apiKey.isEmpty)
    }

    /// A private file rather than the Keychain: the ad-hoc signed app (and its CLI) would
    /// otherwise trigger a Keychain prompt after every rebuild.
    private static var fileURL: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("CloneVoice/polisher.json")
    }

    static func load() -> PolisherConfig {
        (try? Data(contentsOf: fileURL)).flatMap { try? JSONDecoder().decode(PolisherConfig.self, from: $0) } ?? PolisherConfig()
    }

    func save() {
        guard let data = try? JSONEncoder().encode(self) else { return }
        try? data.write(to: Self.fileURL, options: [.atomic])
        try? FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: Self.fileURL.path)
    }
}

/// Asks a language model to re-break a script into natural spoken phrases. Only punctuation and
/// line breaks may change; any edit to the words themselves rejects the result.
enum ScriptPolisher {
    enum Failure: LocalizedError {
        case badResponse(String)
        case changedWords

        var errorDescription: String? {
            switch self {
            case .badResponse(let detail): detail
            case .changedWords: "模型改动了原文，已改用标点断句"
            }
        }
    }

    /// Returns one line per spoken phrase.
    static func lines(for paragraph: String, maxLength: Int, config: PolisherConfig) async throws -> [String] {
        let reply = try await complete(
            system: instructions(config.prompt, maxLength: maxLength),
            user: paragraph,
            config: config
        )
        let lines = reply
            .replacingOccurrences(of: #"(?s)<think>.*?</think>"#, with: "", options: .regularExpression)
            .components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
        guard spokenContent(of: lines.joined()) == spokenContent(of: paragraph) else { throw Failure.changedWords }
        return lines
    }

    /// Round-trips a short sample; used by the settings screen.
    static func check(_ config: PolisherConfig) async throws {
        _ = try await lines(for: "今天天气不错我们一起出去走走吧", maxLength: 40, config: config)
    }

    /// Words without punctuation or spacing — the part that must survive polishing untouched.
    static func spokenContent(of text: String) -> String {
        String(String.UnicodeScalarView(text.unicodeScalars.filter {
            !CharacterSet.punctuationCharacters.contains($0)
                && !CharacterSet.symbols.contains($0)
                && !CharacterSet.whitespacesAndNewlines.contains($0)
        }))
    }

    /// The user's prompt sets the phrasing style; the fixed rules keep the output machine-checkable.
    private static func instructions(_ prompt: String, maxLength: Int) -> String {
        """
        \(prompt.trimmingCharacters(in: .whitespacesAndNewlines))

        以下是语音合成的硬性要求，必须遵守：
        1. 绝对不能增加、删除、替换或调换任何文字、数字、字母，只能增删或修改标点符号。
        2. 句号、问号、感叹号之间的句子不要超过 \(maxLength) 个字，太长就在合适的位置改成句号。
        3. 只输出处理后的文本，不要任何解释。
        """
    }

    private static func complete(system: String, user: String, config: PolisherConfig) async throws -> String {
        guard let url = URL(string: config.baseURL.trimmingCharacters(in: CharacterSet(charactersIn: "/ ")) + "/chat/completions") else {
            throw Failure.badResponse("接口地址不对")
        }
        var request = URLRequest(url: url, timeoutInterval: 60)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if !config.apiKey.isEmpty { request.setValue("Bearer \(config.apiKey)", forHTTPHeaderField: "Authorization") }
        request.httpBody = try JSONSerialization.data(withJSONObject: [
            "model": config.model,
            "temperature": 0.2,
            "stream": false,
            "messages": [
                ["role": "system", "content": system],
                ["role": "user", "content": user],
            ],
        ])

        let data: Data, response: URLResponse
        do {
            (data, response) = try await URLSession.shared.data(for: request)
        } catch let error as URLError where error.code == .cancelled {
            throw CancellationError()
        } catch {
            throw Failure.badResponse("连不上接口，检查网络或地址")
        }
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        guard status == 200 else {
            switch status {
            case 401, 403: throw Failure.badResponse("API Key 无效或没有权限")
            case 404: throw Failure.badResponse("接口地址或模型名不对")
            case 429: throw Failure.badResponse("调用太频繁或余额不足")
            default:
                let message = (json?["error"] as? [String: Any])?["message"] as? String
                throw Failure.badResponse(message.map { "接口报错：\($0)" } ?? "接口报错（\(status)）")
            }
        }
        guard let choices = json?["choices"] as? [[String: Any]],
              let content = (choices.first?["message"] as? [String: Any])?["content"] as? String
        else { throw Failure.badResponse("接口返回的格式看不懂") }
        return content
    }
}
