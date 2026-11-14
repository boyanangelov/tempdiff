#!/bin/bash
# Builds TempDiff, installs it to ~/Applications and starts it at login (LaunchAgent).
set -euo pipefail
cd "$(dirname "$0")"
./build.sh
DEST="$HOME/Applications/TempDiff.app"
PLIST="$HOME/Library/LaunchAgents/io.github.boyanangelov.tempdiff.plist"
mkdir -p "$HOME/Applications" "$HOME/Library/LaunchAgents"
pkill -x TempDiff 2>/dev/null || true
launchctl bootout "gui/$(id -u)" "$PLIST" 2>/dev/null || true
rm -rf "$DEST" && cp -R TempDiff.app "$DEST"
cat > "$PLIST" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>Label</key><string>io.github.boyanangelov.tempdiff</string>
  <key>ProgramArguments</key>
  <array><string>$DEST/Contents/MacOS/TempDiff</string></array>
  <key>RunAtLoad</key><true/>
  <key>KeepAlive</key><dict><key>SuccessfulExit</key><false/></dict>
  <key>ProcessType</key><string>Interactive</string>
</dict>
</plist>
PLIST
launchctl bootstrap "gui/$(id -u)" "$PLIST"
echo "Installed to $DEST; starts at login."
echo "Uninstall: launchctl bootout gui/\$(id -u) $PLIST && rm $PLIST && rm -rf $DEST"
