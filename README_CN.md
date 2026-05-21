# QwenTranscribe macOS

基于 [Qwen3-ASR](https://huggingface.co/Qwen/Qwen3-ASR-1.7B) 的原生 macOS 语音转录应用。上传音频文件，自动生成带时间戳的字幕并导出 SRT。

[English](README.md)

## 特性

- **🎯 语音转文字** — 上传音频，自动转录，支持 20+ 语言
- **⏱️ 句子级时间戳** — 每句标注起止时间，点击跳转播放
- **📝 字幕导出** — 一键导出 SRT 字幕文件
- **✏️ 在线编辑** — 直接修改转录结果，修正识别错误
- **▶️ 边听边看** — 内置播放器，当前句子高亮跟随

## 环境要求

- **macOS 14 (Sonoma)** 及以上
- **Xcode**（含 Swift 6 工具链）—— `xcode-select --install`
- **Python 3.10+**
- **ffmpeg** —— `brew install ffmpeg`

## 快速开始

```bash
# 克隆仓库
git clone https://github.com/dcchanInSz/qwen3-asr-mac.git
cd qwen3-asr-mac

# 一条命令完成配置和启动
./start.sh
```

首次运行会自动创建 Python 虚拟环境并安装依赖。

首次启动时如果没有模型，**设置**窗口会自动弹出 —— 点击 **下载模型** 即可下载 Qwen3-ASR 1.7B（约 3GB）。下载完成后模型自动加载，应用即可使用。

## 手动配置

如果需要手动配置：

```bash
python3 -m venv .venv
source .venv/bin/activate
pip install -r backend/requirements.txt
cd app && swift run
```

## 架构

- `backend/server.py` —— Python FastAPI 服务端，在 localhost:8765 上运行 Qwen3-ASR 模型
- `app/` —— 原生 SwiftUI macOS 应用（无外部 Swift 依赖）
- Swift 应用自动启动并监控 Python 后端；退出时两者都会被终止

## 模型存储

模型通过 HuggingFace Hub 下载到 `models/` 目录（已 gitignore）：
- `models/models--Qwen--Qwen3-ASR-1.7B/` —— ASR 模型
- `models/Qwen3-ForcedAligner-0.6B/` —— 强制对齐器，用于词级时间戳

## 支持语言

中文、英语、粤语、阿拉伯语、德语、法语、西班牙语、葡萄牙语、印尼语、意大利语、韩语、俄语、泰语、越南语、日语、土耳其语、印地语、马来语、荷兰语、瑞典语，以及自动检测。
