# 鲲鹏有声

原生 macOS 声音克隆应用。录 10 秒左右的朗读，之后输入任意文字，就能用你的声音读出来。全部在本机运行，音频不上传。

- 界面：SwiftUI（macOS 15+，Apple Silicon）
- 推理：[mlx-audio-swift](https://github.com/Blaizzy/mlx-audio-swift) + `Qwen3-TTS-12Hz-1.7B-Base-8bit`（零样本克隆，支持中英日韩等）
- 上传音频自动识别文字：系统 Speech 框架

## 构建

```bash
xcodebuild -downloadComponent MetalToolchain   # 仅首次
./build.sh                                      # 产物：build/鲲鹏有声.app
open build/鲲鹏有声.app
```

首次启动会自动下载模型（3.1 GB），huggingface.co 不通时自动切换 hf-mirror.com。

## 数据位置

`~/Library/Application Support/CloneVoice/`

- `voices.json`：声音库与生成记录
- `*.wav`：声音样本与生成的音频
- `Models/`：模型权重
