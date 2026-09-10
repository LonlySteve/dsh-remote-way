#!/bin/zsh
# ============================================================================
#  dsh-phone-url.sh — 一条命令启动 dsh web，并打印「手机可直接打开的网址」
#
#  用法:
#      ~/dsh-phone-url.sh
#      DSH_HARNESS_DIR=/path/to/deepseek-harness ~/dsh-phone-url.sh   # 自定义 dsh 目录
#      DSH_PHONE_HOST=xxx.ts.net ~/dsh-phone-url.sh                   # 自定义 tailnet 域名
#
#  它做的三件事:
#    1. 若 3080 已被旧 dsh web 占用，先自动停掉（避免 EADDRINUSE）。
#    2. 用 `pnpm dsh web --trusted-host <你的 tailnet 域名>` 启动。
#    3. 解析启动行的 ?token=，打印手机可用的两条网址（Tailscale / SSH）。
#
#  为什么必须用本脚本: 手动 `pnpm dsh web` 很容易漏掉 `--trusted-host`（会导致
#  手机走 Tailscale 时 403），且每次重启 token 会变、需要重新拼网址。
# ============================================================================
set -euo pipefail

DIR="${DSH_HARNESS_DIR:-$HOME/deepseek-harness}"

# tailnet 域名: 优先用环境变量，否则从 tailscale 自动探测
HOST="${DSH_PHONE_HOST:-}"
if [[ -z "$HOST" ]]; then
  HOST="$(tailscale status --json 2>/dev/null | python3 -c 'import json,sys;print(((json.load(sys.stdin).get("Self") or {}).get("DNSName") or "").rstrip("."))' 2>/dev/null || true)"
fi
if [[ -z "$HOST" ]]; then
  echo "error: 无法自动获取 tailnet 域名；请设置 DSH_PHONE_HOST=<你的Mac>.ts.net" >&2
  exit 1
fi

if [[ ! -d "$DIR" ]]; then
  echo "error: dsh 目录不存在: $DIR（用 DSH_HARNESS_DIR 指定）" >&2
  exit 1
fi

# 若 3080 已被旧 dsh web 占用，先停掉，避免 EADDRINUSE
EXIST="$(lsof -tiTCP:3080 -sTCP:LISTEN 2>/dev/null || true)"
if [[ -n "$EXIST" ]]; then
  echo "==> 检测到 3080 已被占用（旧 dsh web，pid: $(echo "$EXIST" | tr '\n' ' ')），先停掉..."
  echo "$EXIST" | xargs -r kill 2>/dev/null || true
  sleep 2
fi

echo "==> 启动 dsh web（--trusted-host $HOST）"
(
  cd "$DIR"
  pnpm dsh web --trusted-host "$HOST"
) 2>&1 | while IFS= read -r line; do
  # 形如: dsh web: http://127.0.0.1:3080/?token=XXXX
  if [[ "$line" == *"dsh web: http://127.0.0.1:3080/?token="* ]]; then
    token="${line##*token=}"
    token="${token%% *}"      # 去掉可能跟在后面的 (LAN: ...)
    printf '\n\033[1;32m📱 手机可打开（两条路都试）:\033[0m\n'
    printf '   \033[36m① Tailscale（熄屏不掉·推荐）:\033[0m  https://%s/?token=%s\n' "$HOST" "$token"
    printf '   \033[36m② SSH 转发（需 Termius 隧道）:\033[0m   http://127.0.0.1:3080/?token=%s\n' "$token"
    printf '\n   ⚠️ token 每进程唯一：重启 dsh web 会换新 token；用本脚本重启即可自动重新打印。\n\n'
  fi
  printf '%s\n' "$line"
done
