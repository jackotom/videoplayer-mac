#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")"

APP="build/VideoPlayer.app"
VERSION="1.0.6"
DMG="VideoPlayer-${VERSION}.dmg"
STAGING=".dmg_staging"

[ -d "$APP" ] || { echo "❌ 未找到 $APP，请先运行 ./build.sh"; exit 1; }

rm -rf "$STAGING" "$DMG"
mkdir -p "$STAGING"
cp -R "$APP" "$STAGING/"
ln -s /Applications "$STAGING/Applications"

echo "==> 创建 DMG 镜像 ..."
hdiutil create \
    -volname "视频播放器" \
    -srcfolder "$STAGING" \
    -ov \
    -format UDZO \
    "$DMG"

rm -rf "$STAGING"
echo ""
echo "✅ 生成安装镜像：$DMG"
echo "   双击挂载后，把「视频播放器」拖入 Applications 即可"
