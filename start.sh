#!/bin/bash
set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
VENV_DIR="$SCRIPT_DIR/.venv"

echo "=== Qwen3-ASR macOS App ==="

needs_setup() {
  if [ ! -f "$VENV_DIR/bin/python3" ]; then
    return 0
  fi
  if ! "$VENV_DIR/bin/python3" -c "import numpy" 2>/dev/null; then
    return 0
  fi
  return 1
}

setup_venv() {
  if needs_setup; then
    if [ ! -f "$VENV_DIR/bin/activate" ]; then
      echo "Creating Python virtual environment..."
      python3 -m venv "$VENV_DIR"
    fi
    echo "Installing Python dependencies..."
    source "$VENV_DIR/bin/activate"
    pip install --upgrade pip
    pip install qwen-asr
    pip install fastapi uvicorn huggingface_hub scipy
  fi
  source "$VENV_DIR/bin/activate"
}

cleanup() {
  kill $BACKEND_PID 2>/dev/null || true
  lsof -ti :8765 | xargs kill -9 2>/dev/null || true
}

trap cleanup EXIT

setup_venv

lsof -ti :8765 | xargs kill -9 2>/dev/null || true

echo "Starting backend..."
python3 "$SCRIPT_DIR/backend/server.py" &
BACKEND_PID=$!

echo "Waiting for backend..."
for i in $(seq 1 60); do
  if curl -s http://127.0.0.1:8765/health > /dev/null 2>&1; then
    echo "Backend ready."
    break
  fi
  sleep 2
done

echo "Building & launching app..."
cd "$SCRIPT_DIR/app"
swift run
