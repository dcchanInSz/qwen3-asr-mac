#!/bin/bash
set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
VENV_DIR="$SCRIPT_DIR/.venv"

echo "=== Qwen3-ASR macOS App ==="

setup_venv() {
  if [ ! -f "$VENV_DIR/bin/activate" ]; then
    echo "Creating Python virtual environment..."
    python3 -m venv "$VENV_DIR"
    echo "Installing Python dependencies..."
    source "$VENV_DIR/bin/activate"
    pip install --upgrade pip
    pip install -r "$SCRIPT_DIR/backend/requirements.txt"
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
