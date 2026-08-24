#!/bin/bash
# 发布流水线：GitHub Release + 更新 appcast.xml（Sparkle 自动更新源）
# 前置：已运行 ./release.sh 产出签名+公证的 DMG；已配置 gh CLI 登录
set -euo pipefail
cd "$(dirname "$0")"

REPO="jackotom/videoplayer-mac"
VERSION="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' Info.plist)"
DMG="VideoPlayer-${VERSION}.dmg"
TAG="v${VERSION}"

[ -f "${DMG}" ] || { echo "❌ 未找到 ${DMG}，请先运行 ./release.sh（签名+公证）"; exit 1; }
[ -x tools/generate_appcast ] || { echo "❌ 请先运行 ./scripts/fetch_sparkle.sh"; exit 1; }

echo "==> 创建 GitHub Release ${TAG} 并上传 ${DMG} ..."
if gh release view "${TAG}" --repo "${REPO}" >/dev/null 2>&1; then
    echo "    Release ${TAG} 已存在，跳过创建。"
else
    gh release create "${TAG}" "${DMG}" \
        --repo "${REPO}" \
        --title "视频播放器 ${VERSION}" \
        --notes "本次更新内容请在此填写。"
fi

echo "==> 生成 appcast.xml（EdDSA 私钥自动取自钥匙串）..."
# generate_appcast 只扫描平铺目录；appcast.xml 会复用并保留历史版本条目，
# --download-url-prefix 仅作用于本次新增的条目
mkdir -p appcast_work
cp "${DMG}" "appcast_work/"
./tools/generate_appcast \
    --download-url-prefix "https://github.com/${REPO}/releases/download/${TAG}/" \
    --full-release-notes-url "https://github.com/${REPO}/releases/tag/${TAG}" \
    --link "https://github.com/${REPO}" \
    appcast_work/
mv appcast_work/appcast.xml appcast.xml

echo "==> 提交并推送 appcast.xml（Sparkle feed URL 指向仓库 main 分支）..."
git add appcast.xml
git commit -m "release: ${TAG} appcast 更新" || echo "（无变化，跳过提交）"
git push

echo ""
echo "✅ 发布完成：${TAG}"
echo "   安装包：https://github.com/${REPO}/releases/tag/${TAG}"
echo "   已安装用户将在启动时收到自动更新提示。"
