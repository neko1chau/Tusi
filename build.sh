#!/bin/bash
# Builds Tusi.app into ./build. Usage: ./build.sh [--open]
#
# Architecture is controlled by TUSI_ARCH (default: native, i.e. whatever this Mac is):
#   TUSI_ARCH=arm64      swift build --arch arm64
#   TUSI_ARCH=universal  builds arm64 + x86_64 separately, lipo's them together
set -euo pipefail
cd "$(dirname "$0")"

ARCH_MODE="${TUSI_ARCH:-native}"

APP="build/Tusi.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"

# Where the binary actually lands varies by toolchain/build-system (classic SPM uses
# .build/<arch>-apple-macosx/release/, the newer Swift Build backend reuses one shared
# .build/out/Products/Release/ for every --arch invocation). --show-bin-path asks the
# toolchain directly instead of guessing, so this works either way — but because a shared
# directory gets overwritten by the next build, each slice must be copied out immediately.
case "$ARCH_MODE" in
    native)
        swift build -c release
        cp "$(swift build -c release --show-bin-path)/Tusi" "$APP/Contents/MacOS/Tusi"
        ;;
    arm64)
        swift build -c release --arch arm64
        cp "$(swift build -c release --arch arm64 --show-bin-path)/Tusi" "$APP/Contents/MacOS/Tusi"
        ;;
    universal)
        swift build -c release --arch arm64
        cp "$(swift build -c release --arch arm64 --show-bin-path)/Tusi" /tmp/tusi-arm64-slice
        swift build -c release --arch x86_64
        cp "$(swift build -c release --arch x86_64 --show-bin-path)/Tusi" /tmp/tusi-x86_64-slice
        lipo -create /tmp/tusi-arm64-slice /tmp/tusi-x86_64-slice -output "$APP/Contents/MacOS/Tusi"
        rm -f /tmp/tusi-arm64-slice /tmp/tusi-x86_64-slice
        ;;
    *)
        echo "未知 TUSI_ARCH: $ARCH_MODE（可选 native / arm64 / universal）" >&2
        exit 1
        ;;
esac

cp Resources/Tusi.icns "$APP/Contents/Resources/Tusi.icns"

# Copy .lproj folders straight into the app's own Resources — not SwiftPM's nested
# resource bundle — so Bundle.main (what SwiftUI's Text/.help and NSLocalizedString both
# read by default) finds them without any explicit `bundle:` argument anywhere in the code.
for lproj in Sources/Tusi/Resources/*.lproj; do
    [ -d "$lproj" ] && cp -R "$lproj" "$APP/Contents/Resources/"
done

cat > "$APP/Contents/Info.plist" <<'EOF'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleName</key>
    <string>Tusi</string>
    <key>CFBundleDisplayName</key>
    <string>Tusi</string>
    <key>CFBundleIdentifier</key>
    <string>com.tusi.app</string>
    <key>CFBundleExecutable</key>
    <string>Tusi</string>
    <key>CFBundleIconFile</key>
    <string>Tusi</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleDevelopmentRegion</key>
    <string>zh-Hans</string>
    <key>CFBundleLocalizations</key>
    <array>
        <string>zh-Hans</string>
        <string>en</string>
    </array>
    <key>CFBundleShortVersionString</key>
    <string>1.4.0</string>
    <key>CFBundleVersion</key>
    <string>9</string>
    <key>LSMinimumSystemVersion</key>
    <string>13.0</string>
    <key>LSUIElement</key>
    <true/>
    <key>NSHighResolutionCapable</key>
    <true/>
</dict>
</plist>
EOF

# Sign with a stable identity when one is available, otherwise ad-hoc.
#
# An ad-hoc signature's designated requirement is the binary's cdhash, so it changes on
# every build. The Keychain stores that requirement when you click "Always Allow", which
# means an ad-hoc app re-prompts for the API key after every rebuild. Signing with a real
# identity pins the requirement to the certificate instead, and the authorization sticks.
#
# Anyone building this from a clone just falls through to ad-hoc: no certificate needed,
# and the result works exactly as before.
IDENTITY="${TUSI_SIGN_IDENTITY:-Spotoast Local Dev}"
if security find-identity -v -p codesigning | grep -qF "$IDENTITY"; then
    codesign --force --sign "$IDENTITY" "$APP"
    echo "✓ 已用「$IDENTITY」签名"
else
    codesign --force --sign - "$APP"
    echo "✓ 已用 ad-hoc 签名（未找到「$IDENTITY」证书）"
fi

echo "✓ 已生成 $APP"
if [[ "${1:-}" == "--open" ]]; then
    open "$APP"
fi
