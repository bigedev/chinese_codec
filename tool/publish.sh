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
#   2. 默认走本地 7897（Clash Verge 的 mixed 端口，http 与 socks5 同一个口）。
#      连不上就自动直连，不会因为代理没开而把发布卡死。换端口 PUB_PROXY=... 与
#      PUB_SOCKS_PROXY=...；强制直连用 PUB_PROXY=。
set -euo pipefail

cd "$(dirname "$0")/.."

DART_BIN="${DART_BIN:-dart}"
PUB_PROXY="${PUB_PROXY-http://127.0.0.1:7897}"
PUB_SOCKS_PROXY="${PUB_SOCKS_PROXY-socks5://127.0.0.1:7897}"
PUB_PUBLISH_URL="${PUB_PUBLISH_URL:-https://pub.dev}"

# pub 的凭据位置随平台/版本不同：macOS 上是 ~/Library/Application Support/dart，
# Linux 与老版本在 $XDG_CONFIG_HOME/dart 或 ~/.config/dart。写死任何一个都会误判成
# 「没登录」，所以按候选顺序探测，也可以用 PUB_CREDENTIALS 直接指定。
CREDENTIALS="${PUB_CREDENTIALS:-}"
if [ -z "$CREDENTIALS" ]; then
  for candidate in \
    "${XDG_CONFIG_HOME:-$HOME/.config}/dart/pub-credentials.json" \
    "$HOME/Library/Application Support/dart/pub-credentials.json"; do
    if [ -f "$candidate" ]; then
      CREDENTIALS="$candidate"
      break
    fi
  done
fi

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

# ---------- 代理（默认 7897，连不上就直连） ----------
if [ -n "$PUB_PROXY" ]; then
  if curl -s -m 2 -o /dev/null "$PUB_PROXY" 2>/dev/null; then
    export HTTP_PROXY="$PUB_PROXY"
    export HTTPS_PROXY="$PUB_PROXY"
    export ALL_PROXY="$PUB_SOCKS_PROXY"
    export NO_PROXY="${NO_PROXY:-localhost,127.0.0.1}"
    echo "== 走代理 ${PUB_PROXY}（socks ${PUB_SOCKS_PROXY}）=="
  else
    echo "== ${PUB_PROXY} 连不上，直接直连 =="
  fi
fi

# ---------- 检查 ----------
echo '== format =='
"$DART_BIN" format --output=none --set-exit-if-changed lib test example tool

echo '== analyze =='
"$DART_BIN" analyze

echo '== test =='
"$DART_BIN" test

echo '== dry run =='
# dry-run 把 warning 也算失败（退出码 1），工作区有未提交改动就会中招。
# 直接让 set -e 掐掉的话，看起来像「发布完了」却什么都没发生，所以这里自己接住。
if ! PUB_HOSTED_URL="$PUB_PUBLISH_URL" "$DART_BIN" pub publish --dry-run; then
  echo
  echo 'dry-run 没通过：上面的问题先处理掉再发（工作区有未提交改动也会被算成 warning）。'
  exit 1
fi

if [ "${1:-}" = '--dry-run' ]; then
  echo '只做了检查，没有发布'
  exit 0
fi

# ---------- 发布 ----------
if [ -z "$CREDENTIALS" ]; then
  echo '还没登录 pub.dev（没找到 pub-credentials.json）。先执行：'
  echo "  PUB_HOSTED_URL=${PUB_PUBLISH_URL} ${DART_BIN} pub login"
  exit 1
fi
echo "== 凭据 ${CREDENTIALS} =="

echo
echo "即将发布 ${VERSION} 到 ${PUB_PUBLISH_URL}（Ctrl-C 取消）"
sleep 3
PUB_HOSTED_URL="$PUB_PUBLISH_URL" "$DART_BIN" pub publish --force

echo
echo "发布完成。别忘了打 tag："
echo "  git tag -a ${VERSION} -m 'chinese_codec ${VERSION}' && git push origin ${VERSION}"
