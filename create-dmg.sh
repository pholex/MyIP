#!/bin/bash
# MyIP DMG 打包脚本

cd "$(dirname "$0")"

# 检查 create-dmg 工具是否已安装
if ! command -v create-dmg &> /dev/null; then
    echo "错误: create-dmg 工具未安装"
    echo "请运行: brew install create-dmg"
    exit 1
fi

# 推出所有已挂载的 DMG
for vol in /Volumes/MyIP*; do
  [ -d "$vol" ] && hdiutil detach "$vol" 2>/dev/null
done

create-dmg \
  --volname "MyIP" \
  --window-size 600 500 \
  --background "build/background.png" \
  --icon-size 128 \
  --icon "MyIP.app" 150 250 \
  --app-drop-link 450 250 \
  --no-internet-enable \
  "build/release/MyIP.dmg" \
  "build/release/MyIP.app"
