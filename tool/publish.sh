#!/usr/bin/env bash
# 本地发布 chinese_codec 到 pub.dev。
#
#   tool/publish.sh             先 dry-run，确认后发布
#   tool/publish.sh --dry-run   只跑检查
#
# 默认直连，不碰代理（这台机器没有常开代理）。确实要走代理时显式给：
#   PUB_PROXY=http://127.0.0.1:7890 tool/publish.sh
set -euo pipefail

cd "$(dirname "$0")/.."

DART_BIN="${DART_BIN:-dart}"
PUB_PROXY="${PUB_PROXY:-}"

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
echo "== 版本 ${VERSION} =="

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
"$DART_BIN" pub publish --dry-run

if [ "${1:-}" = '--dry-run' ]; then
  echo '只做了检查，没有发布'
  exit 0
fi

# ---------- 发布 ----------
echo
echo "即将发布 ${VERSION} 到 pub.dev（Ctrl-C 取消）"
sleep 3
"$DART_BIN" pub publish --force

echo
echo "发布完成。别忘了打 tag："
echo "  git tag -a ${VERSION} -m 'chinese_codec ${VERSION}' && git push origin ${VERSION}"
