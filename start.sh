#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
cd "$ROOT_DIR"

OPEN_BROWSER=1
CHECK_ONLY=0

for arg in "$@"; do
  case "$arg" in
    --no-browser)
      OPEN_BROWSER=0
      ;;
    --check)
      CHECK_ONLY=1
      ;;
    *)
      echo "[yt-dlp-ui] 未知参数: $arg"
      echo "用法: ./start.sh [--check] [--no-browser]"
      exit 2
      ;;
  esac
done

if ! command -v python3 >/dev/null 2>&1; then
  echo "[yt-dlp-ui] 未找到 python3，请先安装 Python 3.10+"
  exit 1
fi

VENV_DIR="$ROOT_DIR/.venv"
PYTHON_BIN="$VENV_DIR/bin/python"
PIP_BIN="$VENV_DIR/bin/pip"
REQ_FILE="$ROOT_DIR/requirements.txt"
REQ_HASH_FILE="$VENV_DIR/.requirements.sha256"
APP_HOST="127.0.0.1"
APP_PORT="17800"
APP_URL="http://${APP_HOST}:${APP_PORT}"

wait_for_server() {
  local host="$1"
  local port="$2"
  local attempts="${3:-80}"
  local interval="${4:-0.25}"

  "$PYTHON_BIN" - "$host" "$port" "$attempts" "$interval" <<'PY'
import socket
import sys
import time

host = sys.argv[1]
port = int(sys.argv[2])
attempts = int(float(sys.argv[3]))
interval = float(sys.argv[4])

for _ in range(attempts):
    sock = socket.socket()
    sock.settimeout(interval)
    try:
        sock.connect((host, port))
    except OSError:
        time.sleep(interval)
    else:
        sock.close()
        raise SystemExit(0)

raise SystemExit(1)
PY
}

open_browser_url() {
  local url="$1"

  if command -v xdg-open >/dev/null 2>&1; then
    xdg-open "$url" >/dev/null 2>&1 && return 0
  fi

  if command -v open >/dev/null 2>&1; then
    open "$url" >/dev/null 2>&1 && return 0
  fi

  if command -v wslview >/dev/null 2>&1; then
    wslview "$url" >/dev/null 2>&1 && return 0
  fi

  if command -v cmd.exe >/dev/null 2>&1; then
    cmd.exe /C start "" "$url" >/dev/null 2>&1 && return 0
  fi

  "$PYTHON_BIN" -m webbrowser "$url" >/dev/null 2>&1 && return 0
  return 1
}

echo "[yt-dlp-ui] 准备运行环境..."

if [ ! -x "$PYTHON_BIN" ]; then
  echo "[yt-dlp-ui] 首次运行，创建虚拟环境..."
  python3 -m venv "$VENV_DIR"
fi

REQ_HASH="$("$PYTHON_BIN" -c 'import hashlib, pathlib; print(hashlib.sha256(pathlib.Path("requirements.txt").read_bytes()).hexdigest())')"
LAST_HASH=""
if [ -f "$REQ_HASH_FILE" ]; then
  LAST_HASH="$(cat "$REQ_HASH_FILE" 2>/dev/null || true)"
fi

if [ "$REQ_HASH" != "$LAST_HASH" ]; then
  echo "[yt-dlp-ui] 安装/更新依赖..."
  "$PIP_BIN" install -q --disable-pip-version-check -r "$REQ_FILE"
  echo "$REQ_HASH" > "$REQ_HASH_FILE"
fi

if ! command -v yt-dlp >/dev/null 2>&1; then
  if ! "$PYTHON_BIN" -c "import yt_dlp" >/dev/null 2>&1; then
    echo "[yt-dlp-ui] 安装 yt-dlp..."
    "$PIP_BIN" install -q --disable-pip-version-check -U yt-dlp
  fi
fi

if [ "$CHECK_ONLY" -eq 1 ]; then
  echo "[yt-dlp-ui] 环境检查通过"
  exit 0
fi

if [ "$OPEN_BROWSER" -eq 1 ]; then
  (
    if wait_for_server "$APP_HOST" "$APP_PORT"; then
      open_browser_url "$APP_URL" || true
    fi
  ) &
fi

echo "[yt-dlp-ui] 启动中: $APP_URL"
exec "$PYTHON_BIN" app.py
