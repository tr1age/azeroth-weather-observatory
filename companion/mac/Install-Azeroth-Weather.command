#!/bin/bash
set -euo pipefail
printf '%s\n' 'Azeroth Weather Companion' 'This enables automatic sharing of weather, zone, realm, estimated layer, time and a random installation ID. Reports are public. No character or account name is sent.'
read -r -p 'Type YES to install and enable sharing: ' answer
if [[ "$answer" != YES ]]; then echo 'Installation cancelled.'; exit 0; fi
source_dir="$(cd "$(dirname "$0")" && pwd)"
install_dir="$HOME/Library/Application Support/AzerothWeatherCompanion"
agent_dir="$HOME/Library/LaunchAgents"
agent="$agent_dir/com.craftingworlds.azerothweather.plist"
mkdir -p "$install_dir" "$agent_dir"
launchctl bootout "gui/$(id -u)/com.craftingworlds.azerothweather" 2>/dev/null || true
cp "$source_dir/AzerothWeatherCompanion" "$install_dir/AzerothWeatherCompanion"
chmod 700 "$install_dir/AzerothWeatherCompanion"
/usr/bin/plutil -create xml1 "$agent"
/usr/libexec/PlistBuddy -c 'Add :Label string com.craftingworlds.azerothweather' "$agent"
/usr/libexec/PlistBuddy -c 'Add :ProgramArguments array' "$agent"
/usr/libexec/PlistBuddy -c "Add :ProgramArguments:0 string $install_dir/AzerothWeatherCompanion" "$agent"
/usr/libexec/PlistBuddy -c 'Add :RunAtLoad bool true' "$agent"
launchctl bootstrap "gui/$(id -u)" "$agent"
printf '%s\n' 'Installed! Use /reload or log out in WoW to share saved reports.'
read -r -p 'Press Return to close.' _
