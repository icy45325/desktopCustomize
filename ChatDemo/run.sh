#!/bin/bash
# 构建并打包成 .app 后启动（裸可执行文件没有 bundle id，系统通知和窗口激活会不正常）。
set -euo pipefail
cd "$(dirname "$0")"
swift build -c debug
APP=.build/ChatDemo.app
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS"
cp .build/debug/ChatDemo "$APP/Contents/MacOS/ChatDemo"
cat > "$APP/Contents/Info.plist" <<'EOF'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
  <key>CFBundleIdentifier</key><string>com.example.ChatDemo</string>
  <key>CFBundleName</key><string>ChatDemo</string>
  <key>CFBundleExecutable</key><string>ChatDemo</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>LSMinimumSystemVersion</key><string>14.0</string>
  <key>NSPrincipalClass</key><string>NSApplication</string>
</dict></plist>
EOF
codesign --force --sign - "$APP" >/dev/null
open "$APP"
