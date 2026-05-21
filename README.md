# QwenTranscribe macOS

Native macOS speech transcription app using [Qwen3-ASR](https://huggingface.co/Qwen/Qwen3-ASR-1.7B). Upload audio, get automatic transcriptions with sentence-level timestamps, and export SRT subtitles.

[中文文档](README_CN.md)

## Features

- **🎯 Speech-to-Text** — Upload any audio file, get instant transcription in 20+ languages
- **⏱️ Sentence Timestamps** — Every sentence has start/end times; click to seek playback
- **📝 SRT Export** — Export subtitles as standard SRT files for any video player
- **✏️ Inline Editing** — Correct transcription errors directly in the timeline
- **▶️ Playback Sync** — Built-in audio player with active sentence highlighting

## Prerequisites

- **macOS 14 (Sonoma)** or later
- **Xcode** (with Swift 6 toolchain) — `xcode-select --install`
- **Python 3.10+**
- **ffmpeg** — `brew install ffmpeg`

## Quick Start

```bash
# Clone
git clone git@github.com:dcchanInSz/qwen-transcribe.git
cd qwen-transcribe

# One command to set up & run
./start.sh
```

The first run will automatically create a Python virtual environment and install dependencies.

The first time the app launches without a model, a **Settings** window will appear automatically — click **Download Model** to download Qwen3-ASR 1.7B (~3GB). After download completes, the model loads automatically and the app is ready to use.

## Manual Setup

If you prefer to set things up manually:

```bash
python3 -m venv .venv
source .venv/bin/activate
pip install -r backend/requirements.txt
cd app && swift run
```

## Architecture

- `backend/server.py` — Python FastAPI server running Qwen3-ASR model on localhost:8765
- `app/` — Native SwiftUI macOS app (no external Swift dependencies)
- The Swift app auto-starts and monitors the Python backend; both are killed on exit

## Model Storage

Models are downloaded to `models/` (gitignored) via HuggingFace Hub:
- `models/models--Qwen--Qwen3-ASR-1.7B/` — ASR model
- `models/Qwen3-ForcedAligner-0.6B/` — Forced aligner for word-level timestamps

## Supported Languages

Chinese, English, Cantonese, Arabic, German, French, Spanish, Portuguese, Indonesian, Italian, Korean, Russian, Thai, Vietnamese, Japanese, Turkish, Hindi, Malay, Dutch, Swedish, and auto-detection.
