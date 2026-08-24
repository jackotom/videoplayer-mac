#!/bin/bash
# 发布流水线：Developer ID 签名 → 公证 → 装订 → 公证 DMG → 产出安装包
#
# 一次性前置准备：
#   1. 在 developer.apple.com 创建并安装「Developer ID Application」证书
#      （Certificates → ＋ → Developer ID Application → 下载双击安装进钥匙串）
#   2. 存储公证凭据（二选一）：
#      · Apple ID + App 专用密码（appleid.apple.com 生成）：
#        xcrun notarytool store-credentials VideoPlayerNotary \
#          --apple-id "你的AppleID" --team-id "82DSTW66J3" --password "App专用密码"
#      · App Store Connect API 密钥（推荐，App Store Connect → 用户与访问 → 集成 → 团队密钥）：
#        xcrun notarytool store-credentials VideoPlayerNotary \
#          --key ~/Downloads/AuthKey_XXXXXXXX.p8 --key-id KEYID --issuer ISSUERID
set -euo pipefail
cd "$(dirname "$0")"

APP="build/VideoPlayer.app"
DMG="VideoPlayer-1.0.6.dmg"
PROFILE="${NOTARY_PROFILE:-VideoPlayerNotary}"

echo "==> 编译 + Developer ID 签名 ..."
./build.sh

echo "==> 验证签名 ..."
codesign --verify --deep --strict --verbose=2 "${APP}"

echo "==> 提交公证（首次约 1-5 分钟）..."
xcrun notarytool submit "${APP}" --keychain-profile "${PROFILE}" --wait

echo "==> 装订公证票据到 App ..."
xcrun stapler staple "${APP}"

echo "==> 打包 DMG ..."
./make_dmg.sh

echo "==> 公证 DMG 并装订 ..."
xcrun notarytool submit "${DMG}" --keychain-profile "${PROFILE}" --wait
xcrun stapler staple "${DMG}"

echo ""
echo "✅ 发布完成：${DMG}（已签名 + 已公证 + 已装订，对方双击即装，无 Gatekeeper 拦截）"
xcrun stapler validate "${DMG}"
