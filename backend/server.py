#!/usr/bin/env python3
"""Qwen3-ASR backend server for macOS speech recognition UI."""

import os
import subprocess
import tempfile
import threading
from contextlib import asynccontextmanager

import numpy as np
import torch
from fastapi import FastAPI, File, Form, UploadFile
from fastapi.middleware.cors import CORSMiddleware
from huggingface_hub import snapshot_download
from qwen_asr import Qwen3ASRModel

BASE_DIR = os.path.dirname(os.path.dirname(__file__))

MODEL_PATH = os.environ.get(
    "QWEN3_ASR_MODEL_PATH",
    os.path.join(BASE_DIR, "models", "models--Qwen--Qwen3-ASR-1.7B",
                 "snapshots", "7278e1e70fe206f11671096ffdd38061171dd6e5")
)

ALIGNER_PATH = os.path.join(BASE_DIR, "models", "Qwen3-ForcedAligner-0.6B")
DEVICE = os.environ.get("QWEN3_ASR_DEVICE", "mps" if torch.backends.mps.is_available() else "cpu")
DTYPE = torch.float16 if DEVICE == "mps" else torch.float32

model = None
model_exists = False
aligner_available = False
timestamps_supported = False

download_state = {
    "status": "idle",
    "progress": 0,
    "message": "",
}

def _check_model_exists():
    if not os.path.isdir(MODEL_PATH):
        return False
    try:
        return any(f.endswith(".safetensors") for f in os.listdir(MODEL_PATH))
    except OSError:
        return False

def _check_aligner_available():
    return os.path.isdir(ALIGNER_PATH) and any(
        f.endswith(".safetensors") for f in os.listdir(ALIGNER_PATH)
    )


def _build_sentence_timestamps(audio: np.ndarray, sr: int, text: str) -> list[dict]:
    if not text.strip():
        return []

    import re
    raw = re.split(r'(?<=[。！？.!?])\s*', text.strip())
    sentences = [s.strip() for s in raw if s.strip()]
    if not sentences:
        return []

    # Speech-probability weighted time warping
    frame_len = int(0.03 * sr)
    hop_len = int(0.01 * sr)
    num_frames = max(1, (len(audio) - frame_len) // hop_len + 1)
    hop_time = hop_len / sr

    rms = np.zeros(num_frames)
    for i in range(num_frames):
        start = i * hop_len
        frame = audio[start:start + frame_len]
        rms[i] = max(1e-10, np.sqrt(np.mean(frame ** 2)))

    rms_db = 20 * np.log10(rms)
    noise_floor = np.percentile(rms_db, 15)
    speech_prob = np.clip((rms_db - noise_floor) / (-noise_floor), 0, 1)
    try:
        from scipy.ndimage import uniform_filter1d
        speech_prob = uniform_filter1d(speech_prob, size=3)
    except ImportError:
        pass

    cum_speech = np.cumsum(speech_prob) * hop_time
    total_speech = cum_speech[-1]
    frame_times = np.arange(num_frames) * hop_time

    if total_speech < 0.01:
        duration = len(audio) / sr
        total_chars = sum(len(s) for s in sentences)
        result = []
        cum = 0
        for s in sentences:
            sc = len(s)
            start = cum / total_chars * duration
            cum += sc
            end = cum / total_chars * duration
            result.append({"start": start, "end": end, "text": s})
        return result

    total_chars = sum(len(s) for s in sentences)

    def speech_to_wall(speech_time: float) -> float:
        return float(np.interp(speech_time, cum_speech, frame_times))

    result = []
    cum_chars = 0
    for s in sentences:
        sc = len(s)
        st = cum_chars / total_chars * total_speech
        cum_chars += sc
        et = cum_chars / total_chars * total_speech
        result.append({
            "start": speech_to_wall(st),
            "end": speech_to_wall(et),
            "text": s,
        })

    return result


def _group_word_timestamps(word_timestamps: list, full_text: str) -> list[dict]:
    """Group forced-aligner word-level timestamps into sentences.

    word_timestamps may lack punctuation, so full_text (with punctuation)
    is used for sentence boundary detection.
    """
    import re
    words = word_timestamps
    non_content = set(' \t\n\r\u3000。！？.!?，,、；;：:""''「」『』【】（）()…—–－-《》〈〉')

    # Align each content char in full_text to a word index by walking
    # through words sequentially — avoids fragile substring matching.
    align = []
    wi = 0
    ci = 0
    for fc in full_text:
        if fc in non_content:
            align.append(-1)
            continue
        while wi < len(words) and ci >= len(words[wi].text):
            wi += 1
            ci = 0
        if wi >= len(words):
            align.append(-1)
            continue
        align.append(wi)
        ci += 1

    # Find sentence spans in full_text
    sentences = []
    for m in re.finditer(r'[^。！？.!?]*[。！？.!?]?\s*', full_text):
        s, e = m.start(), m.end()
        if e > s and full_text[s:e].strip():
            sentences.append((s, e))

    result = []
    for s, e in sentences:
        word_idxs = sorted({align[i] for i in range(s, min(e, len(align))) if align[i] >= 0})
        if not word_idxs:
            continue
        result.append({
            "start": words[word_idxs[0]].start_time,
            "end": words[word_idxs[-1]].end_time,
            "text": full_text[s:e].strip(),
        })

    if not result:
        return [{"start": words[0].start_time, "end": words[-1].end_time, "text": full_text}]

    return result


def decode_audio(audio_bytes: bytes) -> np.ndarray:
    """Decode any audio format to float32 mono 16kHz PCM via ffmpeg."""
    with tempfile.NamedTemporaryFile(suffix=".audio", delete=True) as tmp_in:
        tmp_in.write(audio_bytes)
        tmp_in.flush()

        proc = subprocess.run(
            [
                "ffmpeg", "-i", tmp_in.name,
                "-f", "f32le", "-acodec", "pcm_f32le",
                "-ar", "16000", "-ac", "1",
                "-loglevel", "error",
                "pipe:1",
            ],
            capture_output=True,
        )
        if proc.returncode != 0 or not proc.stdout:
            raise ValueError(f"ffmpeg decode failed: {proc.stderr.decode()}")
        audio = np.frombuffer(proc.stdout, dtype=np.float32).copy()
        if len(audio) == 0:
            raise ValueError("Decoded audio is empty")
        return audio


def get_model():
    global model, model_exists, aligner_available, timestamps_supported
    if model is not None:
        return model

    model_exists = _check_model_exists()
    aligner_available = _check_aligner_available()

    if not model_exists:
        print(f"Model not found at {MODEL_PATH}. Ready for download.")
        return None

    print(f"Loading Qwen3-ASR model from {MODEL_PATH} on {DEVICE}...")
    kwargs = dict(
        dtype=DTYPE,
        device_map=DEVICE,
        max_new_tokens=2048,
        max_inference_batch_size=1,
    )
    if aligner_available:
        print(f"Loading forced aligner from {ALIGNER_PATH}...")
        kwargs["forced_aligner"] = ALIGNER_PATH
        kwargs["forced_aligner_kwargs"] = dict(
            dtype=DTYPE,
            device_map=DEVICE,
        )
        timestamps_supported = True
    else:
        print("Forced aligner not available, timestamps disabled.")

    model = Qwen3ASRModel.from_pretrained(MODEL_PATH, **kwargs)
    print("Model loaded.")
    return model


def _download_thread():
    global download_state, model, model_exists, aligner_available, timestamps_supported
    try:
        download_state["status"] = "downloading"
        download_state["progress"] = 0
        download_state["message"] = "Downloading Qwen3-ASR model... (~3GB)"

        os.makedirs(MODEL_PATH, exist_ok=True)
        download_state["progress"] = 10
        snapshot_download(
            "Qwen/Qwen3-ASR-1.7B",
            local_dir=MODEL_PATH,
            local_dir_use_symlinks=False,
        )

        download_state["progress"] = 45
        download_state["message"] = "Downloading forced aligner model..."
        os.makedirs(ALIGNER_PATH, exist_ok=True)
        download_state["progress"] = 50
        snapshot_download(
            "Qwen/Qwen3-ForcedAligner-0.6B",
            local_dir=ALIGNER_PATH,
            local_dir_use_symlinks=False,
        )

        download_state["progress"] = 85
        download_state["message"] = "Loading models into memory..."
        download_state["progress"] = 90
        get_model()

        download_state["status"] = "done"
        download_state["progress"] = 100
        download_state["message"] = "Models ready."

    except Exception as e:
        download_state["status"] = "error"
        download_state["progress"] = -1
        download_state["message"] = str(e)
        import traceback
        traceback.print_exc()


@asynccontextmanager
async def lifespan(app: FastAPI):
    global model_exists, aligner_available, timestamps_supported
    model_exists = _check_model_exists()
    aligner_available = _check_aligner_available()
    if model_exists:
        get_model()
    else:
        print("Model not found; server running in setup mode.")
    yield


app = FastAPI(title="Qwen3-ASR Server", lifespan=lifespan)

app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)


@app.get("/health")
async def health():
    return {
        "status": "ok",
        "device": DEVICE,
        "model_loaded": model is not None,
        "timestamps_supported": timestamps_supported,
    }


@app.get("/model-status")
async def model_status():
    return {
        "model_loaded": model is not None,
        "model_exists_on_disk": _check_model_exists(),
        "aligner_available": _check_aligner_available(),
        "device": DEVICE,
        "download": download_state,
    }


@app.post("/download-model")
async def download_model():
    global download_state
    if download_state["status"] == "downloading":
        return {"status": "already_downloading", "message": download_state["message"]}

    download_state = {"status": "downloading", "progress": 0, "message": "Starting download..."}
    thread = threading.Thread(target=_download_thread, daemon=True)
    thread.start()
    return {"status": "started"}


@app.get("/download-status")
async def download_status():
    return download_state


@app.post("/reload-model")
async def reload_model():
    global model, model_exists, aligner_available, timestamps_supported
    model = None
    get_model()
    return {
        "model_loaded": model is not None,
        "timestamps_supported": timestamps_supported,
    }


@app.post("/transcribe")
async def transcribe(
    file: UploadFile = File(...),
    language: str = Form(default=""),
    return_timestamps: str = Form(default="false"),
):
    try:
        audio_bytes = await file.read()
        audio_data = decode_audio(audio_bytes)

        max_samples = 10 * 60 * 16000
        if len(audio_data) > max_samples:
            audio_data = audio_data[:max_samples]

        m = get_model()
        if m is None:
            from fastapi.responses import JSONResponse
            return JSONResponse(
                {"error": "Model not installed. Please download the model first."},
                status_code=503,
            )
        lang = language.strip() if language.strip() else None

        results = m.transcribe(
            audio=(audio_data, 16000),
            language=lang,
            return_time_stamps=timestamps_supported,
        )
        text = results[0].text

        if timestamps_supported and hasattr(results[0], "time_stamps") and results[0].time_stamps:
            timestamps = _group_word_timestamps(results[0].time_stamps, text)
        else:
            timestamps = _build_sentence_timestamps(audio_data, 16000, text)

        return {
            "text": text,
            "language": results[0].language,
            "duration": len(audio_data) / 16000,
            "timestamps": timestamps,
        }

    except Exception as e:
        import traceback
        traceback.print_exc()
        from fastapi.responses import JSONResponse
        return JSONResponse(
            {"error": f"Transcription failed: {e}"},
            status_code=500,
        )


if __name__ == "__main__":
    import uvicorn
    uvicorn.run(app, host="127.0.0.1", port=8765, timeout_keep_alive=300)
