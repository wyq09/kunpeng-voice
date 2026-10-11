# AGENTS.md

This file provides guidance to WARP (warp.dev) when working with code in this repository.

## Project

鲲鹏有声 (Kunpeng Voice) is a native macOS 15+ / Apple Silicon SwiftUI app that clones a voice from a short sample and synthesizes speech fully on-device with MLX. One executable (`CloneVoice`) serves as the GUI app, a CLI, and an MCP server. User-facing strings, logs and error messages are in Chinese; keep new UI text in Chinese.

## Build & run

MLX's Metal shaders must be compiled by `xcodebuild`. `swift build` compiles the Swift code, but the resulting binary can't run inference. Requires Xcode 26+ (Swift 6.2).

```bash
xcodebuild -downloadComponent MetalToolchain   # first time only
./build.sh                                      # Release → build/鲲鹏有声.app
CONFIG=Debug ./build.sh                         # Debug build
open build/鲲鹏有声.app
```

- `build.sh` writes the full xcodebuild output to `build/xcodebuild.log` and prints only the `error:` lines when the build fails. It then puts the `.app` together by hand: binary, `Resources/Info.plist`, icons, SPM resource bundles, and the Cmlx `default.metallib` copied to `Contents/MacOS/mlx.metallib`. Finally it ad-hoc codesigns with `Resources/CloneVoice.entitlements`. Any new runtime resource or bundle has to make it into this assembly step.
- No test targets and no linter/formatter config exist. To check a change, build it and run the CLI against a downloaded model:

```bash
BIN="build/鲲鹏有声.app/Contents/MacOS/CloneVoice"
"$BIN" voices
CLONEVOICE_DEBUG_PACE=1 "$BIN" speak "[开心]你好呀！[平静]今天过得怎么样？" --voice <name> --play
"$BIN" clean input.wav -o out.wav     # denoise only
"$BIN" mcp                            # stdio MCP server
```

- `CLONEVOICE_DEBUG_PACE=1` prints a stderr report for every chunk and every take: pace, speaker similarity, pitch shift, retry scores, and whether it fell back to faithful. Use it whenever you tune synthesis.
- `KP_SNAPSHOT=/some/dir` makes the GUI save window screenshots (`shot0.png`, `shot1.png`) 3 s and 6 s after launch. Use it to check UI changes visually.
- CI (`.github/workflows/build.yml`, `macos-26`) runs `./build.sh` on pushes to main and on PRs. Pushing a `v*` tag stamps the version into `Info.plist`, builds `KunpengVoice-macOS.dmg`, and publishes a GitHub Release.

## Architecture

### Entry point and process modes
`CloneVoiceApp.swift`: `AppEntry.main` checks the first argument against `CommandLineTool.commands` (`mcp`, `voices`, `speak`, `clean`, `help`). If it matches, the process runs headless and never starts SwiftUI. In headless mode, stdout is redirected to stderr because model libraries print to stdout. Results and MCP JSON-RPC are written to a duplicated original stdout handle, so never `print()` in code reachable from CLI/MCP. `HeadlessSpeaker` is the shared non-UI path for both the CLI and `MCPServer`. It creates its own `VoiceStore`/`ModelManager`/`VoiceEngine`.

In GUI mode, the app-wide `@Observable` `@MainActor` objects (`VoiceStore`, `VoiceEngine`, `ModelManager`, `Player`, `JobStore`, `Generator`, `AgentSetup`, `SmartPhrasing`) are created in `CloneVoiceApp` and injected with `.environment(...)`.

### Synthesis pipeline (`Engine/VoiceEngine.swift`, the core)
1. `StyledScript` (`Models/StyledScript.swift`) parses inline `[情绪]` / `【情绪】` tags (titles, raw values, or aliases) into style segments. Unknown tags are dropped from the spoken text.
2. `VoiceEngine.phrase` splits each segment into paragraphs and then chunks. If smart phrasing is configured (`ScriptPolisher`, OpenAI-compatible LLM, config in `polisher.json`), the LLM supplies punctuation, results are cached per paragraph, and `TextChunker` packs by that punctuation. Max chunk length depends on the model (`ModelSpec.chunkLength`: CosyVoice 60, VoxCPM 90, Qwen3 120 chars).
3. Each chunk goes to the `SynthesisWorker` actor, which owns the non-Sendable MLX model. `generateMatchingVoice` scores every take on **speaker similarity** (CAM++ embedding cosine vs. the voice's own median "plain take" baseline), **pitch drift** vs. the reference median pitch, and **pace**. When a take drifts, an acted emotion first gets one reroll with a new seed (`variant`). After that the worker retries in `faithful` mode, which drops the style to keep the voice. A badly wrong pace means garbled content and is rerolled in the same mode.
4. Post-processing (`AudioEffects`, `PaceControl`): takes are time-stretched to the style's target tempo (only drift beyond ±8% is corrected, clamped to 0.75–1.35). A small pitch shift is applied only when the model did not act the emotion itself. Pauses between chunks depend on the boundary type (clause, sentence, paragraph). The output is loudness-normalized.
5. The previous chunk (`SpokenChunk`, pace-corrected and never pitch-shifted) is passed to the next generation so backends that support continuation keep tone and pace consistent.

### Backends (`CloneBackend` protocol)
- `CosyVoiceBackend` (CosyVoice 3, from vendored `CosyVoiceTTS`): instructions use instruct2 mode, which hides the reference tokens from the LLM. The voice profile **must** include the CAM++ speaker embedding, or emotions pull the timbre to a different person. Profiles are cached per sample and rebuilt once the embedder becomes available.
- `VoxCPMBackend` (VoxCPM 2 and 1.5, from vendored `VoxCPM2TTS`): picks continuation of the reference, continuation of the previous chunk, or style-instruct mode depending on style, `faithful`, and `variant`. VoxCPM 1.5 always continues the reference.
- `Qwen3Backend` (`mlx-audio-swift` `MLXAudioTTS`): has no instruction support. It approximates emotion through sampling temperature, which is capped at 0.85.
- Only CosyVoice and VoxCPM2 report `supportsEmotionInstruction`. Per-style instructions, VoxCPM style descriptions and `Prosody` (temperature, pitch, tempo, pause) all live in `Models/Delivery.swift`.
- Seeds are fixed (`20_260_806`) and offset by `variant` so chunks of one script sound like one take while retries still differ.

`情绪标签导致音色切换：根因与修复方案.md` documents why tagged segments used to sound like a different speaker and explains the design behind CAM++ anchoring, the similarity-based retries, the ±50-cent pitch cap and the temperature cap. Read it before changing the retry or prosody logic.

### Models & downloads
- `Models/ModelCatalog.swift` is the single list of supported HF repos. A model's family decides its backend, download patterns and chunk length.
- `ModelManager` stores weights in `~/Library/Application Support/CloneVoice/Models/<repo_id with / → _>/`. A `.complete` marker file means the download finished.
- `ResumableDownloader` downloads file by file with HTTP Range resume. Partial files go to `.partial/`. It alternates between `huggingface.co` and `hf-mirror.com` with backoff. Backends always load with `offlineMode: true` from that directory.
- Auxiliary models (the DeepFilterNet3 denoiser in `Audio/VoiceCleaner.swift` and the CAM++ speaker model in `Audio/SpeakerEmbedder.swift`) download on demand into separate folders next to each other, outside `Models/`, so model cleanup never deletes them. Synthesis must never block on these downloads for long: `SpeakerEmbedder` returns `nil` and similarity checks are skipped.

### Persistence & cross-process jobs
- `VoiceStore`: `voices.json` plus the sample and clip `.wav` files in `~/Library/Application Support/CloneVoice/`.
- `JobStore`/`JobRecorder`: every generation, whether from the app, the CLI or MCP, writes its own `Jobs/<uuid>.json`. The GUI watches that directory, so it shows CLI/MCP jobs live. A job whose PID no longer exists is marked as failed.
- `Generator` owns in-app generation tasks per voice so they keep running when the user navigates elsewhere. CLI/MCP output defaults to `~/Music/鲲鹏有声/`.

### Vendored code
`Vendor/SpeechSwift` is a local SPM package (CosyVoice 3, VoxCPM 2, and DeepFilterNet3 `SpeechEnhancement`) vendored from soniqo/speech-swift. It's vendored to avoid that package's conflicting mlx-swift-lm pin. Local modifications are marked with `CloneVoice patch` comments; keep using that marker when editing vendored files.

## Gotchas
- The package uses `swift-tools-version:6.2` but compiles the app target in **Swift 5 language mode** (`.swiftLanguageMode(.v5)`).
- `VoiceEngine.polish` is deliberately a `nonisolated static` function and not inlined into the `addTask` closure. Inlining it triggers a Swift -O miscompile in which the task group returns empty and crashes. Keep task-group child bodies out of closures in the same way.
- Call `releaseGPUMemory()` after each take and when switching models. MLX memory pressure is the main stability risk.
- `.teamai/` is the source of truth for team-shared AI skills and rules. The copies under `.claude/`, `.cursor/`, `.codex/`, `.github/skills`, `.opencode/`, `.codebuddy/`, `.workbuddy/` and `.pi/` are synced from it, so edit `.teamai/` rather than the copies.
