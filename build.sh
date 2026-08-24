#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")"

APP_NAME="VideoPlayer"
BUNDLE_DIR="build/${APP_NAME}.app"

rm -rf "${BUNDLE_DIR}"
mkdir -p "${BUNDLE_DIR}/Contents/MacOS"
mkdir -p "${BUNDLE_DIR}/Contents/Resources"

echo "==> 编译 main.swift + FFmpegPlayer.swift ..."
BREW_PREFIX="$(brew --prefix 2>/dev/null || echo /opt/homebrew)"
SPARKLE_FLAGS=()
if [ -d "Sparkle.framework" ]; then
    SPARKLE_FLAGS=(-F . -framework Sparkle)
fi
swiftc -swift-version 5 -O \
    -import-objc-header bridge.h \
    -Xcc -I"${BREW_PREFIX}/include" \
    -L"${BREW_PREFIX}/lib" \
    "${SPARKLE_FLAGS[@]}" \
    -lavcodec -lavformat -lavutil -lswscale -lswresample \
    -framework Cocoa \
    -framework AVKit \
    -framework AVFoundation \
    -framework CoreMedia \
    -framework CoreVideo \
    -framework CoreAudio \
    -framework AudioToolbox \
    -framework Accelerate \
    -framework MediaPlayer \
    -o "${BUNDLE_DIR}/Contents/MacOS/${APP_NAME}" \
    main.swift \
    Subtitle.swift \
    Settings.swift \
    ControlBar.swift \
    FFmpegPlayer.swift

echo "==> 拷贝 Info.plist ..."
cp Info.plist "${BUNDLE_DIR}/Contents/Info.plist"

if [ -f "AppIcon.icns" ]; then
    echo "==> 拷贝图标 ..."
    cp AppIcon.icns "${BUNDLE_DIR}/Contents/Resources/AppIcon.icns"
fi

echo "==> 打包 FFmpeg 动态库（@rpath 内嵌）..."
mkdir -p "${BUNDLE_DIR}/Contents/Frameworks"
python3 bundle_dylibs.py \
    "${BUNDLE_DIR}/Contents/MacOS/${APP_NAME}" \
    "${BUNDLE_DIR}/Contents/Frameworks"

# Sparkle 自动更新框架内嵌
if [ -d "Sparkle.framework" ]; then
    echo "==> 内嵌 Sparkle.framework（自动更新）..."
    rm -rf "${BUNDLE_DIR}/Contents/Frameworks/Sparkle.framework"
    cp -R "Sparkle.framework" "${BUNDLE_DIR}/Contents/Frameworks/"
fi

echo "==> 签名 ..."
# 优先使用 Developer ID Application 证书（公证分发）；找不到则退回 ad-hoc（本机测试）
DEV_ID="${SIGN_IDENTITY:-}"
if [ -z "$DEV_ID" ]; then
    DEV_ID=$(security find-identity -v -p codesigning 2>/dev/null \
        | grep -o '"Developer ID Application: [^"]*"' | head -1 | tr -d '"' || true)
fi
if [ -n "$DEV_ID" ]; then
    echo "   使用 Developer ID 签名：${DEV_ID}"
    for dylib in "${BUNDLE_DIR}/Contents/Frameworks/"*.dylib; do
        [ -f "$dylib" ] || continue
        codesign --force --sign "${DEV_ID}" --timestamp "$dylib"
    done
    if [ -d "${BUNDLE_DIR}/Contents/Frameworks/Sparkle.framework" ]; then
        codesign --force --sign "${DEV_ID}" --timestamp --deep \
            "${BUNDLE_DIR}/Contents/Frameworks/Sparkle.framework"
    fi
    codesign --force --sign "${DEV_ID}" --timestamp --options runtime \
        --entitlements entitlements.plist "${BUNDLE_DIR}"
else
    echo "   未找到 Developer ID 证书，使用 ad-hoc 签名（仅供本机测试）"
    codesign --force --deep --sign - "${BUNDLE_DIR}"
fi
codesign --verify --deep --strict "${BUNDLE_DIR}" >/dev/null 2>&1 || true

echo ""
echo "✅ 构建完成：${BUNDLE_DIR}（已内嵌 FFmpeg，可独立分发）"
echo "   运行：open build/${APP_NAME}.app"
