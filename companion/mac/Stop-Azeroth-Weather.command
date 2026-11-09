#!/bin/bash
set -euo pipefail
agent="$HOME/Library/LaunchAgents/com.craftingworlds.azerothweather.plist"
launchctl bootout "gui/$(id -u)/com.craftingworlds.azerothweather" 2>/dev/null || true
if [[ -f "$agent" ]]; then rm "$agent"; fi
echo 'Automatic sharing stopped. Your saved data and settings are kept.'
read -r -p 'Press Return to close.' _
