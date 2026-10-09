import Observation
import SwiftUI

/// App-wide state of the optional language-model phrasing step.
@MainActor
@Observable
final class SmartPhrasing {
    var config = PolisherConfig.load()
    var isPresented = false

    var summary: String {
        guard config.isEnabled else { return "智能断句：关" }
        return config.isUsable ? "智能断句：\(config.provider.title)" : "智能断句：未配置完"
    }

    func save(_ config: PolisherConfig) {
        self.config = config
        config.save()
    }
}

struct SmartPhrasingView: View {
    @Environment(SmartPhrasing.self) private var phrasing
    @Environment(\.dismiss) private var dismiss

    @State private var draft = PolisherConfig()
    @State private var checkState: CheckState = .idle

    private enum CheckState: Equatable {
        case idle, checking, passed(TimeInterval), failed(String)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Form {
                Section {
                    Toggle(isOn: $draft.isEnabled) {
                        Text("生成前先让大模型断句")
                        Text("按朗读习惯调整标点和停顿，原文一个字都不改。模型若改了字会自动放弃，改用标点断句。")
                    }
                }
                if draft.isEnabled {
                    serviceSection
                    promptSection
                }
            }
            .formStyle(.grouped)
            Divider()
            footer
        }
        .frame(width: 560, height: draft.isEnabled ? 640 : 220)
        .onAppear { draft = phrasing.config }
        .onChange(of: draft) { _, _ in if checkState != .checking { checkState = .idle } }
    }

    private var serviceSection: some View {
        Section("大模型接口（兼容 OpenAI 格式）") {
            Picker("服务", selection: Binding(
                get: { draft.provider },
                set: { provider in
                    draft.provider = provider
                    if provider != .custom {
                        draft.baseURL = provider.baseURL
                        draft.model = provider.model
                    }
                }
            )) {
                ForEach(PolisherProvider.allCases) { Text($0.title).tag($0) }
            }
            TextField("接口地址", text: $draft.baseURL, prompt: Text("https://…/v1"))
            TextField("模型", text: $draft.model)
            if draft.provider.needsKey {
                LabeledContent("API Key") {
                    HStack {
                        SecureField("API Key", text: $draft.apiKey).labelsHidden()
                        if let page = draft.provider.keyPage {
                            Link("获取", destination: page).font(.caption)
                        }
                    }
                }
            }
        }
    }

    private var promptSection: some View {
        Section {
            Picker("风格", selection: Binding(
                get: { draft.preset },
                set: { preset in
                    draft.preset = preset
                    if preset != .custom { draft.prompt = preset.prompt }
                }
            )) {
                ForEach(PromptPreset.allCases) { Text($0.title).tag($0) }
            }
            .pickerStyle(.segmented)
            TextEditor(text: Binding(
                get: { draft.prompt },
                set: { text in
                    draft.prompt = text
                    if text != draft.preset.prompt { draft.preset = .custom }
                }
            ))
            .font(.callout)
            .frame(minHeight: 110)
        } header: {
            Text("提示词")
        } footer: {
            Text("可以随意修改。「不改原文一个字」这类硬性要求会自动附加，不用写。")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private var footer: some View {
        HStack(spacing: 10) {
            if draft.isEnabled {
                Button("测试连接", action: check)
                    .disabled(!draft.isUsable || checkState == .checking)
                checkStatus
            }
            Spacer()
            Button("取消", role: .cancel) { dismiss() }
                .keyboardShortcut(.cancelAction)
            Button("保存") {
                phrasing.save(draft)
                dismiss()
            }
            .keyboardShortcut(.defaultAction)
            .buttonStyle(.kpPrimary)
        }
        .padding(16)
    }

    @ViewBuilder
    private var checkStatus: some View {
        switch checkState {
        case .idle:
            if draft.isEnabled, !draft.isUsable {
                Text(draft.provider.needsKey && draft.apiKey.isEmpty ? "填上 API Key 就能用" : "把地址和模型填完整")
                    .font(.caption).foregroundStyle(.secondary)
            }
        case .checking:
            ProgressView().controlSize(.small)
        case .passed(let seconds):
            Label(String(format: "可以用 · %.1f 秒", seconds), systemImage: "checkmark.circle.fill")
                .font(.caption).foregroundStyle(Color.kpCyan)
        case .failed(let message):
            Label(message, systemImage: "exclamationmark.triangle.fill")
                .font(.caption).foregroundStyle(Color.kpGold).lineLimit(2)
        }
    }

    private func check() {
        let config = draft
        checkState = .checking
        Task {
            let started = Date.now
            do {
                try await ScriptPolisher.check(config)
                checkState = .passed(Date.now.timeIntervalSince(started))
            } catch {
                checkState = .failed(error.localizedDescription)
            }
        }
    }
}
