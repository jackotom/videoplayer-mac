#!/bin/bash
# 下载 Sparkle 框架与工具（框架不入库，构建/CI 时按需拉取）
set -euo pipefail
cd "$(dirname "$0")/.."

VERSION="${1:-2.9.6}"

if [ -d Sparkle.framework ] && [ -x tools/generate_appcast ]; then
    echo "Sparkle ${VERSION} 已就绪，跳过下载。"
    exit 0
fi

echo "==> 下载 Sparkle ${VERSION} ..."
TMP=$(mktemp -d)
curl -sL -o "$TMP/s.tar.xz" "https://github.com/sparkle-project/Sparkle/releases/download/${VERSION}/Sparkle-${VERSION}.tar.xz"
tar -xJf "$TMP/s.tar.xz" -C "$TMP"

[ -d "$TMP/Sparkle.framework" ] || { echo "❌ 解压失败"; exit 1; }
rm -rf Sparkle.framework
mv "$TMP/Sparkle.framework" Sparkle.framework

mkdir -p tools
cp "$TMP/bin/generate_appcast" "$TMP/bin/generate_keys" "$TMP/bin/sign_update" tools/
chmod +x tools/*
rm -rf "$TMP"
echo "✅ Sparkle ${VERSION} 已就绪（Sparkle.framework + tools/）"
