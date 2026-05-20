#!/bin/bash
set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
VENV_DIR="$SCRIPT_DIR/.venv"

echo "=== Qwen3-ASR macOS App ==="

find_python() {
  for py in /opt/homebrew/bin/python3.12 /opt/homebrew/bin/python3 /usr/local/bin/python3.12 /usr/local/bin/python3 python3.12 python3; do
    if command -v "$py" &>/dev/null; then
      echo "$py"
      return
    fi
  done
  echo "python3"
}

PYTHON=$(find_python)
echo "Using Python: $PYTHON"

check_python() {
  local ver
  ver=$("$PYTHON" -c "import sys; print(f'{sys.version_info.major}.{sys.version_info.minor}')" 2>/dev/null || echo "0.0")
  local major minor
  major=$(echo "$ver" | cut -d. -f1)
  minor=$(echo "$ver" | cut -d. -f2)
  if [ "$major" -lt 3 ] || ([ "$major" -eq 3 ] && [ "$minor" -lt 10 ]); then
    echo "ERROR: Python 3.10+ is required (found $ver)."
    echo "Install with: brew install python@3.12"
    exit 1
  fi
}
check_python

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
      "$PYTHON" -m venv "$VENV_DIR"
    fi
    echo "Installing Python dependencies..."
    source "$VENV_DIR/bin/activate"
    pip install --upgrade pip
    pip install --extra-index-url https://pypi.org/simple/ qwen-asr fastapi uvicorn huggingface_hub scipy
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
"$VENV_DIR/bin/python3" "$SCRIPT_DIR/backend/server.py" &
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
