#!/usr/bin/env bash
# 本地发布 chinese_codec 到 pub.dev。
#
#   tool/publish.sh             先 dry-run，确认后发布
#   tool/publish.sh --dry-run   只跑检查
#
# 两件环境上的坑，脚本自己处理：
#   1. 本机 ~/.zshrc 里设了 PUB_HOSTED_URL=https://pub.flutter-io.cn（国内镜像）。
#      镜像只读、不代理发布，直接照着发会以「requested authentication」失败。
#      所以 publish 这两步单独把 PUB_HOSTED_URL 覆盖成 pub.dev；依赖解析不受影响。
#   2. 没有常开代理。确实要走代理时显式给：
#      PUB_PROXY=http://127.0.0.1:7890 tool/publish.sh
set -euo pipefail

cd "$(dirname "$0")/.."

DART_BIN="${DART_BIN:-dart}"
PUB_PROXY="${PUB_PROXY:-}"
PUB_PUBLISH_URL="${PUB_PUBLISH_URL:-https://pub.dev}"
CREDENTIALS="$HOME/.config/dart/pub-credentials.json"

# ---------- 版本一致性 ----------
VERSION="$(sed -n 's/^version:[[:space:]]*//p' pubspec.yaml | head -1)"
if [ -z "$VERSION" ]; then
  echo 'pubspec.yaml 里没有 version'
  exit 1
fi
if ! grep -q "^## ${VERSION}" CHANGELOG.md; then
  echo "CHANGELOG.md 里没有 ${VERSION} 的小节，先补上再发"
  exit 1
fi
echo "== 版本 ${VERSION}，发布目标 ${PUB_PUBLISH_URL} =="

if [ -n "${PUB_HOSTED_URL:-}" ] && [ "${PUB_HOSTED_URL}" != "$PUB_PUBLISH_URL" ]; then
  echo "   环境里 PUB_HOSTED_URL=${PUB_HOSTED_URL}（镜像，只读），publish 这两步会临时覆盖"
fi

if [ -n "$(git status --porcelain)" ]; then
  echo '注意：工作区不干净，pub 会给出警告（不影响发布，但建议先提交）'
  git status --short
fi

# ---------- 代理（默认不用） ----------
if [ -n "$PUB_PROXY" ]; then
  export HTTP_PROXY="$PUB_PROXY"
  export HTTPS_PROXY="$PUB_PROXY"
  export NO_PROXY="${NO_PROXY:-localhost,127.0.0.1}"
  echo "== 走代理 $PUB_PROXY =="
fi

# ---------- 检查 ----------
echo '== format =='
"$DART_BIN" format --output=none --set-exit-if-changed lib test example tool

echo '== analyze =='
"$DART_BIN" analyze

echo '== test =='
"$DART_BIN" test

echo '== dry run =='
PUB_HOSTED_URL="$PUB_PUBLISH_URL" "$DART_BIN" pub publish --dry-run

if [ "${1:-}" = '--dry-run' ]; then
  echo '只做了检查，没有发布'
  exit 0
fi

# ---------- 发布 ----------
if [ ! -f "$CREDENTIALS" ]; then
  echo "还没登录 pub.dev（找不到 $CREDENTIALS）。先执行："
  echo "  PUB_HOSTED_URL=$PUB_PUBLISH_URL $DART_BIN pub login"
  exit 1
fi

echo
echo "即将发布 ${VERSION} 到 ${PUB_PUBLISH_URL}（Ctrl-C 取消）"
sleep 3
PUB_HOSTED_URL="$PUB_PUBLISH_URL" "$DART_BIN" pub publish --force

echo
echo "发布完成。别忘了打 tag："
echo "  git tag -a ${VERSION} -m 'chinese_codec ${VERSION}' && git push origin ${VERSION}"
