#!/bin/zsh
# Builds 我的声音.app into ./build. MLX's Metal shaders require xcodebuild (plain `swift build` cannot compile them).
set -euo pipefail
cd "$(dirname "$0")"

CONFIG="${CONFIG:-Release}"
DERIVED="build/DerivedData"
PRODUCTS="$DERIVED/Build/Products/$CONFIG"
APP="build/我的声音.app"
mkdir -p build

xcodebuild -scheme CloneVoice \
  -destination 'platform=macOS,arch=arm64' \
  -configuration "$CONFIG" \
  -derivedDataPath "$DERIVED" \
  -skipPackagePluginValidation \
  build > build/xcodebuild.log 2>&1 || {
    grep -E "error:" build/xcodebuild.log | sort -u | head -40
    echo "构建失败，完整日志见 build/xcodebuild.log"
    exit 1
  }

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$PRODUCTS/CloneVoice" "$APP/Contents/MacOS/"
cp Resources/Info.plist "$APP/Contents/"
[[ -f Resources/AppIcon.icns ]] && cp Resources/AppIcon.icns "$APP/Contents/Resources/"
for bundle in "$PRODUCTS"/*.bundle(N); do
  cp -R "$bundle" "$APP/Contents/Resources/"
done
METALLIB=$(find "$PRODUCTS" -name "default.metallib" -path "*Cmlx*" | head -1)
[[ -n "$METALLIB" ]] && cp "$METALLIB" "$APP/Contents/MacOS/mlx.metallib"

codesign --force --deep --sign - --entitlements Resources/CloneVoice.entitlements "$APP"
echo "✓ 已生成 $APP"
