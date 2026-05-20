#!/bin/bash
set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
VENV_DIR="$SCRIPT_DIR/.venv"

echo "=== Qwen3-ASR macOS App ==="

echo "Starting backend..."
lsof -ti :8765 | xargs kill -9 2>/dev/null || true
source "$VENV_DIR/bin/activate"
python3 "$SCRIPT_DIR/backend/server.py" &
BACKEND_PID=$!

echo "Waiting for backend (model loading)..."
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

kill $BACKEND_PID 2>/dev/null || true
